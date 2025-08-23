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

#######################################################
###################### Rook/Ceph ######################
#######################################################
#  The stuff below is needed to create loop devices   #
#  inside each minikube node, so that rook/ceph can   #
#  use them as persistent storage devices.            #
#######################################################

# ---------- ceph loop device config ----------
DISK_SIZE="20G"
IMG_DIR="/var/local/rook-disks"
IMG_BASENAME="${CLUSTER_NAME}-ceph-disk.img"
OUTFILE="./node-device.map"
# ---------------------------------------------

# tidy up old loop devices if any (from first node only, since they all share the same kernel with the host-VM, and thus the same /dev/loopX devices)
minikube ssh -p ${CLUSTER_NAME} -- "sudo losetup -a | grep -F \"${IMG_BASENAME}\" | cut -d: -f1 | xargs -r -n1 sudo losetup -d"

# ensure output file is empty / created
: > "${OUTFILE}"

# for docker-driver minikube: find node containers
NODE_CONTAINERS=$(docker ps --filter "name=${CLUSTER_NAME}" --format '{{.Names}}')
for node in ${NODE_CONTAINERS}; do
  echo " ⏳ Preparing loop device for CEPH cluster on ${node}"
  # run commands inside container; diagnostic output goes to stderr so stdout contains only the device path
  DEV_PATH=$(docker exec -u root "${node}" bash -euc "
    mkdir -p ${IMG_DIR}
    IMG=${IMG_DIR}/${IMG_BASENAME}
    DEV=\$(losetup -f --show \"\$IMG\")

    # create sparse image if missing
    if [ ! -f \"\$IMG\" ]; then
      truncate -s ${DISK_SIZE} \"\$IMG\" > /dev/null
    fi

    # ensure loop device is setup correctly and has correct permissions
    chmod 660 \"\$DEV\" || true
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT \"\$DEV\" >/dev/null || true

    # output device path on stdout only, to be captured and written to mapping file
    printf '%s' \"\$DEV\"
  ")

  # sanitize and write mapping: node:loopX
  DEV_NAME=$(basename "${DEV_PATH}" || true)
  printf '%s:%s\n' "${node}" "${DEV_NAME}" >> "${OUTFILE}"
done

echo " ✅ Loop device mapping written to ${OUTFILE}"
