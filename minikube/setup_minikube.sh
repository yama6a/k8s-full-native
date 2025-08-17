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
# start minikube
minikube unpause || minikube start \
--addons=metrics-server \
--cpus=3 \
--memory=4096 \
--disk-size=100g \
--nodes 3 \
--ha \
--delete-on-failure=true \
--driver=docker \
--kubernetes-version=v1.33.1 \
--subnet=172.17.128.0/17
#--addons=csi-hostpath-driver \
#--addons=volumesnapshots \
