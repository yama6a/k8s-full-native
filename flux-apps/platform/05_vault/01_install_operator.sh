#!/usr/bin/env bash

# bash strict mode
set -euxo pipefail

kubectl apply -f 01_operator/manifests/01_namespace.yaml
kubectl apply -f 01_operator/manifests/02_storageclass_minikube.yaml

# Bank Vault Operator
helm install \
--wait \
vault-operator \
oci://ghcr.io/bank-vaults/helm-charts/vault-operator \
-f 01_operator/bank-vault-op-values.yaml \
--namespace sys-vault

# Hashicorp Vault Secrets Operator
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update hashicorp
helm install vault-secrets-operator hashicorp/vault-secrets-operator \
--version 0.9.0 \
-f 01_operator/vault-secrets-op-values.yaml \
--namespace sys-vault
