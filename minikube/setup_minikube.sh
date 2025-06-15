#!/usr/bin/env bash

# bash strict mode
set -euxo pipefail

# install minikube + vfit via brew if not installed
brew install minikube vfkit || true
minikube config set driver vfkit

# start minikube
minikube unpause || minikube start \
--addons=metrics-server \
--cpus=8 \
--memory=8192 \
--disk-size=150g \
--delete-on-failure=true \
--driver=vfkit \
--kubernetes-version=v1.31.4 \
--ports=30080:30080 \
--ports=30443:30443 \
--subnet=172.17.128.0/17
#--addons=csi-hostpath-driver \
#--addons=volumesnapshots \
