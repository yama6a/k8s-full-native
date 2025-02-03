#!/usr/bin/env bash

# Bash strict mode (first half)
set -eo pipefail

# If env variable GITHUB_API_KEY is not set, error and exit
if [ -z "${GITHUB_API_KEY}" ]; then
  echo "environment variable GITHUB_API_KEY is not set. Please call this script like:"
  echo "    GITHUB_API_KEY=yourkey ./bootstrap-fluxcd.sh"
  echo "(with a leading space to avoid storing the key in bash history)"
  exit 1
fi

# Bash strict mode (second half)
set -ux

# Install sealed secrets controller (needed for FluxCD's secret containing the github API key)
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update sealed-secrets
helm install sealed-secrets-controller sealed-secrets/sealed-secrets \
--namespace sys-sealed-secrets --create-namespace \
--values platform/02_sealed-secrets/helm-values.yaml \
--version 2.17.0

# Create Sealed Secret (replace GITHUB token with yours from the environment)
sed "s/GITHUB_API_KEY/$GITHUB_API_KEY/g" ./bootstrap-github-api-secret-template.yaml | kubeseal --format yaml > platform/01_fluxcd/sealedsecret.yaml

# https://artifacthub.io/packages/helm/fluxcd-community/flux2
helm repo add fluxcd https://charts.fluxcd.io
helm repo update
helm install fluxcd fluxcd/flux2 --namespace sys-flux
