#!/usr/bin/env bash

# bash strict mode
set -euo pipefail

# Fix for Rancher Desktop on MacOS:
# rancher desktop has too low inotify limits for three nodes.
# Ref: https://github.com/rancher-sandbox/rancher-desktop/discussions/1567
#if command -v rdctl >/dev/null 2>&1; then
#  echo "Rancher Desktop detected, current inotify limits:"
#  current_watches=$(rdctl shell -- sysctl -n fs.inotify.max_user_watches | tr -d '\r')
#  current_instances=$(rdctl shell -- sysctl -n fs.inotify.max_user_instances | tr -d '\r')
#  echo "fs.inotify.max_user_watches: $current_watches"
#  echo "fs.inotify.max_user_instances: $current_instances"
#  if [ "$current_watches" -lt 256000 ] || [ "$current_instances" -lt 256 ]; then
#    echo "Limits are too low, increasing them..."
#    rdctl shell -- sudo sysctl -w fs.inotify.max_user_watches=256000
#    rdctl shell -- sudo sysctl -w fs.inotify.max_user_instances=256
#    echo "Updated inotify limits:"
#    rdctl shell -- sysctl fs.inotify.max_user_watches fs.inotify.max_user_instances
#  else
#    echo "Inotify limits are sufficient, no changes needed."
#  fi
#fi

# Info:
# --addons=metrics-server       # is needed for the metrics server to be installed in the cluster, which is required by the linkerd control plane.
# --nodes=3                     # is needed to have enough nodes for rook/ceph to be installed and distribute/replicate storage, which is required by the CNPG operator.
# --ha                          # makes sure all nodes are contol-plane nodes. Makes it more similar to a production setup, where we have multiple control-plane nodes for high availability.
# --cpus=4                      # if we have 3 nodes. With 1 node, use 8 or more.
# --memory=4096                 # if we have 3 nodes. With 1 node, use 8GB or more.
# --disk-size=100g              # not sure yet why we need this much disk space. But I remember that this was on purpose, even wayy before we touched rook/ceph. Re-visit this later.
# --delete-on-failure=true      # is needed to delete the minikube cluster if it fails to start, so that we can re-try without having to manually delete the cluster.
# --driver=docker               # vfkit doesn't work with multi-node clusters (which require vmnet-helper and --network=vmnet-shared to allow nodes to talk to each other but prevent pods from egressing)
# --kubernetes-version=v1.33.1  # find supported k8s version here: https://github.com/kubernetes/minikube/releases or `minikube config defaults kubernetes-version | head -n 10`
# --network="k8s-full-native"   # creates a custom docker network for the minikube cluster, so that we can use the custom cidr block defined in the subnet.
# --subnet=172.30.0.0/16        # docker operates by deafult in the 172.16.0.0/12 range, but reserves 172.17.0.0/16 for the default bridge network. We use a different subnet in the same network to avoid conflicts with the default bridge network.
# --docker-opt="default-ulimit=nofile=65536:65536" # kube-proxy borks out sometimes, no clue why, but this seems to help.
# --ports=30080:30080           # nginx ingress controller: node-port 30080 -> nginx-port: 80, so that we can access the services running in the cluster via localhost:30080. (todo: how to do this with multiple nodes?)
# --ports=30443:30443           # nginx ingress controller: node-port 30443 -> nginx-port: 443, so that we can access the services running in the cluster via localhost:30443. (todo: how to do this with multiple nodes?)

# start minikube (addons csi-hostpath-driver, volumesnapshots are needed for CNPG)
# todo: When trying this on a raspi cluster, need to isntall csi-hostpath-driver and volumesnapshots manually
set -x
docker network rm k8s-full-native || true # remove the network if it exists, so that we can create it again with the same name and the correct subnet
minikube unpause || minikube start \
--addons=metrics-server \
--cpus=4 \
--memory=5000 \
--disk-size=100g \
--delete-on-failure=true \
--driver=docker \
--kubernetes-version=v1.33.1 \
--network="k8s-full-native" \
--subnet=172.30.0.0/16

#--ports=30080:30080 \ # todo: how to do this with multiple nodes?
#--ports=30443:30443 \ # todo: how to do this with multiple nodes?
#--addons=csi-hostpath-driver \ (probably don't need this, since we use rook/ceph for storage)
#--addons=volumesnapshots \ (probably don't need this, since we use rook/ceph for storage)

# rook/ceph requires a directory to store data
# probably not needed? Keep commecnted out for noe and see if it works anyways.
#for node in minikube minikube-m02 minikube-m03; do
#  minikube ssh -n "$node" -- "sudo mkdir -p /var/lib/rook && sudo chown root:root /var/lib/rook && sudo chmod 755 /var/lib/rook"
#done
