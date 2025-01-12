#!/usr/bin/env bash

# bash strict mode
set -euxo pipefail

# https://artifacthub.io/packages/helm/bitnami-labs/sealed-secrets
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update sealed-secrets
helm install sealed-secrets-controller sealed-secrets/sealed-secrets \
--namespace sys-sealed-secrets --create-namespace \
--values resources/helm-values.yaml \
--version 2.17.0
