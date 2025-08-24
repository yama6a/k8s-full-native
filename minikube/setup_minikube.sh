#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="kfn"

# if using Rancher Desktop, ensure inotify limits are set correctly - the default values are too low for a multi-node minikube cluster.
if ! command -v rdctl >/dev/null 2>&1; then
  echo "⚠️  If you experience Kubernetes errors such as 'too many open files', please increase the inotify limits on your host system."
  echo "⚠️  Ref: https://00formicapunk00.wordpress.com/2024/12/10/too-many-open-files-in-minikube-pod/"
else
  if ! rdctl shell -- sysctl fs.inotify.max_user_watches | grep 524288 >/dev/null; then
    echo " ⏳ Increasing inotify.max_user_watches limits ..."
    rdctl shell -- sudo sysctl -w fs.inotify.max_user_watches=524288 > /dev/null
  fi
  if ! rdctl shell -- sysctl fs.inotify.max_user_instances | grep 512 >/dev/null; then
    echo " ⏳ Increasing inotify.max_user_instances limits ..."
    rdctl shell -- sudo sysctl -w fs.inotify.max_user_instances=512 > /dev/null
  fi
fi

## check if minikube profile 'kfn' already exists, offer to cleanup if it does
if minikube profile list | grep 'kfn' > /dev/null; then
  echo "⚠️  Minikube profile 'kfn' already exists"
  echo " ❓ Do you want to delete it and create a new one? (y/n)"
  read -r answer
  if [ "$answer" != "${answer#[Yy]}" ] ;then
    minikube delete --profile="${CLUSTER_NAME}"
  else
    echo " ❌ Exiting..."
    exit 1
  fi
fi

# Info:
# --addons=metrics-server       # is needed for the metrics server to be installed in the cluster, which is required by the linkerd control plane.
# --nodes=3                     # is needed to have enough nodes for rook/ceph to be installed and distribute/replicate storage, which is required by the CNPG operator.
# --ha                          # makes all nodes control-plane nodes, so that we can have a prod-like highly available cluster.
# --cpus=3                      # if we have 3 nodes. With 1 node, use 8 or more.
# --memory=4096                 # if we have 3 nodes. With 1 node, use 8GB or more.
# --disk-size=100g              # not sure yet why we need this much disk space. But I remember that this was on purpose, even wayy before we touched rook/ceph. Re-visit this later.
# --delete-on-failure=true      # is needed to delete the minikube cluster if it fails to start, so that we can re-try without having to manually delete the cluster.
# --driver=docker               # using virtualization like vfkit caused problems with networking that I didn't want to debug right now. Only downside: need to port-forward the nginx port after setting up the cluster to enable local testing.
# --kubernetes-version=v1.33.1  # find supported k8s version here: https://github.com/kubernetes/minikube/releases or `minikube config defaults kubernetes-version | head -n 10`
# --subnet=172.17.128.0/17      # is used to avoid conflicts with docker's default subnet
# --wait=all                    # wait for all k8s control-plane components to be ready before exiting the start command
# --wait-timeout=5m             # wait up to 5 minutes for all k8s components to be ready


# start minikube
minikube start \
--profile="${CLUSTER_NAME}" \
--nodes 3 \
--ha \
--cpus=3 \
--memory=4096 \
--disk-size=100g \
--delete-on-failure=true \
--driver=docker \
--kubernetes-version=v1.33.1 \
--subnet=172.17.128.0/17 \
--addons=metrics-server \
--wait=all \
--wait-timeout=5m

# In order to use Longhorn, ensure iscsi initiator is present on every node
echo " ⏳ Ensuring iscsi tools are available on all nodes for Longhorn ..."
NODE_CONTAINERS=$(docker ps --filter "name=${CLUSTER_NAME}" --format '{{.Names}}')
for node in ${NODE_CONTAINERS}; do
  docker exec -u root "${node}" bash -euc '
    set -euo pipefail

    echo " ⏳ installing iscsiadm on node $(hostname)"

    # If iscsiadm already present, nothing to do
    if command -v iscsiadm >/dev/null 2>&1; then
      exit 0
    fi

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq open-iscsi util-linux >/dev/null 2>&1

    # start/enable iscsid (try both service and systemctl commands, (in some container runtimes the PID-1 init may not be systemd)
    service iscsid start >/dev/null 2>&1 \
      || systemctl enable --now iscsid.service >/dev/null 2>&1 \
      || { echo " ❌ Could not start iscsid - neither systemctl nor service command found" >&2; exit 1; }

    # verify installation
    if ! command -v iscsiadm >/dev/null; then
      echo " ❌ iscsiadm installation failed"
      exit 1
    fi
  '
done

echo " ✅ iscsiadm is now available on all nodes"
echo " ✅ Minikube cluster '${CLUSTER_NAME}' is ready"
