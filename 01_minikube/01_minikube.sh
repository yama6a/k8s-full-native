#!/usr/bin/env bash

# bash strict mode
set -euxo pipefail

# install minikube via brew if not installed
brew install minikube || true

# start minikube
minikube unpause || minikube start \
--addons=csi-hostpath-driver \
--addons=volumesnapshots \
--addons=metrics-server \
--cpus=8 \
--disk-size=350g \
--delete-on-failure=true \
--driver=docker \
--kubernetes-version=v1.31.0 \
--memory=8192 \
--subnet=172.17.128.0/17
