#!/usr/bin/env bash

# bash strict mode
set -euxo pipefail

# if using rancher desktop, increase inotify limits which are too low by default
# Ref: https://00formicapunk00.wordpress.com/2024/12/10/too-many-open-files-in-minikube-pod/
if command -v rdctl >/dev/null 2>&1; then
  rdctl shell -- sudo sysctl -w fs.inotify.max_user_watches=524288
  rdctl shell -- sudo sysctl -w fs.inotify.max_user_instances=512
  rdctl shell -- sysctl fs.inotify.max_user_watches fs.inotify.max_user_instances
else
  echo "Error: rdctl CLI not found" >&2
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


# start minikube
minikube unpause || minikube start \
--addons=metrics-server \
--nodes 3 \
--ha \
--cpus=3 \
--memory=4096 \
--disk-size=100g \
--delete-on-failure=true \
--driver=docker \
--kubernetes-version=v1.33.1 \
--subnet=172.17.128.0/17
