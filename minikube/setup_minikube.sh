#!/usr/bin/env bash

# bash strict mode
set -euxo pipefail

# install minikube + vfit via brew if not installed
brew install minikube vfkit || true
minikube config set driver vfkit

if [ ! -d /opt/vmnet-helper ]; then
  set +x
  echo
  echo "INSTRUCTIONS:"
  echo 'machine="$(uname -m)"'
  echo 'archive="vmnet-helper-$machine.tar.gz"'
  echo 'curl -LOf "https://github.com/nirs/vmnet-helper/releases/latest/download/$archive"'
  echo 'sudo tar xvf "$archive" -C / opt/vmnet-helper'
  echo 'rm "$archive"'
  echo 'sudo install -m 0640 /opt/vmnet-helper/share/doc/vmnet-helper/sudoers.d/vmnet-helper /etc/sudoers.d/'
  echo 'sudo chmod +s /opt/vmnet-helper/bin/vmnet-helper'

  exit 1
fi

# Info:
# --addons=metrics-server       # is needed for the metrics server to be installed in the cluster, which is required by the linkerd control plane.
# --nodes=3                     # is needed to have enough nodes for rook/ceph to be installed and distribute/replicate storage, which is required by the CNPG operator.
# --cpus=4                      # if we have 3 nodes. With 1 node, use 8 or more.
# --memory=4096                 # if we have 3 nodes. With 1 node, use 8GB or more.
# --disk-size=100g              # not sure yet why we need this much disk space. But I remember that this was on purpose, even wayy before we touched rook/ceph. Re-visit this later.
# --delete-on-failure=true      # is needed to delete the minikube cluster if it fails to start, so that we can re-try without having to manually delete the cluster.
# --driver=vfkit                # because nginx ingress + port exposure on the host (i.e. localhost:30080 and localhost:30443) did not work with the docker driver on macOS. Or maybe it's just ME who couldn't get it to work ¯\_(ツ)_/¯
# --network=vmnet-shared        # is needed to allow a multi-node cluster to work with the vfkit driver. This is because the vfkit driver uses a shared network interface, which allows the nodes to communicate with each other. (see the vmnet-helper instructions above)
# --cni=calico                  # is needed to allow pods access to the internet. Calico’s default IPPool has `natOutgoing: Enabled`, so it auto-SNATs all pod egress to the VM’s IP (which has a shared net with the host and inet access), giving pods Internet access without macOS tweaks
# --kubernetes-version=v1.33.1  # find supported k8s version here: https://github.com/kubernetes/minikube/releases or `minikube config defaults kubernetes-version | head -n 10`
# --ports=30080:30080           # nginx ingress controller: node-port 30080 -> nginx-port: 80, so that we can access the services running in the cluster via localhost:30080. (todo: how to do this with multiple nodes?)
# --ports=30443:30443           # nginx ingress controller: node-port 30443 -> nginx-port: 443, so that we can access the services running in the cluster via localhost:30443. (todo: how to do this with multiple nodes?)

#
# start minikube (addons csi-hostpath-driver, volumesnapshots are needed for CNPG)
# todo: When trying this on a raspi cluster, need to isntall csi-hostpath-driver and volumesnapshots manually
minikube unpause || minikube start \
--addons=metrics-server \
--nodes=3 \
--cpus=4 \
--memory=4096 \
--disk-size=100g \
--delete-on-failure=true \
--driver=docker \
--subnet=172.17.128.0/17 \
--kubernetes-version=v1.33.1


#--cni=calico \
#--network=vmnet-shared \
#--ports=30080:30080 \ # todo: how to do this with multiple nodes?
# --subnet=172.17.128.0/17 doesn't work with --network=vmnet-shared (it will use the host's network instead)
#--ports=30443:30443 \ # todo: how to do this with multiple nodes?
#--addons=csi-hostpath-driver \ (probably don't need this, since we use rook/ceph for storage)
#--addons=volumesnapshots \ (probably don't need this, since we use rook/ceph for storage)

# rook/ceph requires a directory to store data
# probably not needed? Keep commecnted out for noe and see if it works anyways.
#for node in minikube minikube-m02 minikube-m03; do
#  minikube ssh -n "$node" -- "sudo mkdir -p /var/lib/rook && sudo chown root:root /var/lib/rook && sudo chmod 755 /var/lib/rook"
#done
