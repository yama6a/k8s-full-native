#!/usr/bin/env bash

# bash strict mode
set -euxo pipefail

# install minikube + vfit via brew if not installed
brew install minikube vfkit || true
minikube config set driver vfkit

# start minikube (addons csi-hostpath-driver, volumesnapshots are needed for CNPG)
# todo: When trying this on a raspi cluster, need to isntall csi-hostpath-driver and volumesnapshots manually
minikube unpause || minikube start \
--addons=metrics-server \
--nodes=3 \
--cpus=8 \
--memory=8192 \
--disk-size=150g \
--delete-on-failure=true \
--driver=vfkit \
--kubernetes-version=v1.33.2 \
--ports=30080:30080 \
--ports=30443:30443 \
--subnet=172.17.128.0/17
#--addons=csi-hostpath-driver \
#--addons=volumesnapshots \

# rook/ceph requires a directory to store data
# probably not needed? Keep commecnted out for noe and see if it works anyways.
#for node in minikube minikube-m02 minikube-m03; do
#  minikube ssh -n "$node" -- "sudo mkdir -p /var/lib/rook && sudo chown root:root /var/lib/rook && sudo chmod 755 /var/lib/rook"
#done
