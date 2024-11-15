#!/usr/bin/env bash

# bash strict mode
set -euxo pipefail

kubectl apply -f 02_vault/01_serviceaccount.yaml
kubectl apply -f 02_vault/02_clusterrolebinding.yaml
kubectl apply -f 02_vault/03_rbac.yaml
kubectl apply -f 02_vault/04_vault.yaml
