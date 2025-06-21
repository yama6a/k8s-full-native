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
--addons=csi-hostpath-driver \
--addons=volumesnapshots \
--cpus=8 \
--memory=8192 \
--disk-size=150g \
--delete-on-failure=true \
--driver=vfkit \
--kubernetes-version=v1.31.4 \
--ports=30080:30080 \
--ports=30443:30443 \
--subnet=172.17.128.0/17
