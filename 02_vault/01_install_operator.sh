#!/usr/bin/env bash

# bash strict mode
set -euxo pipefail

kubectl apply -f 01_operator/manifests/01_namespace.yaml
kubectl apply -f 01_operator/manifests/02_storageclass_minikube.yaml

helm install \
--wait \
vault-operator \
oci://ghcr.io/bank-vaults/helm-charts/vault-operator \
-f 01_operator/helm-values.yaml \
--namespace sys-vault
