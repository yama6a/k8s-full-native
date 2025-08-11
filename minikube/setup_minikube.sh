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
--driver=docker \
--kubernetes-version=v1.33.1 \
--subnet=172.17.128.0/17
#--addons=csi-hostpath-driver \
#--addons=volumesnapshots \
