#!/usr/bin/env bash

# Bash strict mode (first half)
set -eo pipefail

# If env variable GITHUB_API_KEY is not set, error and exit
if [ -z "${GITHUB_API_KEY}" ]; then
  echo "environment variable GITHUB_API_KEY is not set. Please call this script like:"
  echo "    GITHUB_API_KEY=yourkey; ./bootstrap-fluxcd.sh"
  echo "(with a leading space to avoid storing the key in bash history)"
  exit 1
fi

# Bash strict mode (second half)
set -ux

# Install sealed secrets controller (needed for FluxCD's secret containing the github API key)
# More sophisticated config will be applied once FluxCD takes over (see flux-apps/platform/02_sealed_secrets/helm-release.yaml)
# Todo: renovate the versions below as well as the ones in the helm-release.yaml
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update sealed-secrets
# "sealed-secrets" must match the metadata.name in k8s/platform-charts/02_sealed_secrets/helm-release.yaml
# to ensure that the Sealed Secrets helm-chart is overridden by the flux-managed one and sealed-secrets is thus managed by flux in the end.
helm install sealed-secrets sealed-secrets/sealed-secrets \
--namespace sys-sealed-secrets --create-namespace \
--version 2.17.1 \
--set-string "image.registry=docker.io" \
--set-string image.repository="bitnami/sealed-secrets-controller" \
--set-string image.tag="0.28.0"

# Wait for sealed-secrets-controller to be ready (we need the CRDs to be installed at least)
set +x
echo "Waiting for sealed-secrets-controller to be ready..."
i=0; while [ $i -lt 60 ] && [ -z "$(kubectl get endpoints sealed-secrets -n sys-sealed-secrets -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)" ]; do
  sleep 2;
  i=$((i+1));
done;
if [ $i -eq 60 ]; then
  echo "Error: sealed-secrets-controller not ready after 2 minutes";
  exit 1;
fi;
set -x

# Todo: backup the sealed-secrets-controller's private key and public key on disk,
#       and find a way for it to never delete it in the cluster no matter what, even if the HelmRelease is deleted.
#       And research and document how to recover the cluster's private key from a backup.


# Create Sealed Secret (replace GITHUB token with yours from the environment)
sed "s/GITHUB_API_KEY/$GITHUB_API_KEY/g" ./bootstrap-github-api-secret-template.yaml \
    | kubeseal --controller-namespace sys-sealed-secrets --controller-name sealed-secrets --format yaml \
    > k8s/platform-charts/01_fluxcd/templates/gh-api-key-sealedsecret.yaml

# https://artifacthub.io/packages/helm/fluxcd-community/flux2
# More sophisticated config will be applied once FluxCD takes over (see flux-apps/platform/01_fluxcd/helm-release.yaml)
# Todo: renovate the versions below as well as the ones in the helm-release.yaml
helm repo add fluxcd https://fluxcd-community.github.io/helm-charts
helm repo update fluxcd
# "fluxcd" must match the spec.releaseName in k8s/platform-charts/01_fluxcd/helm-release.yaml
# to ensure that the Flux helm-chart is overridden by the flux-managed one and flux is thus managed by itself in the end.
helm install fluxcd fluxcd/flux2 \
--namespace flux-system --create-namespace \
--version 2.14.1 \
--set-string cli.tag="v2.4.0" \
--set-string helmController.tag="v1.1.0" \
--set-string AutomationController.tag="v0.39.0" \
--set-string ReflectionController.tag="v0.33.0" \
--set-string kustomizeController.tag="v1.4.0" \
--set-string notificationController.tag="v1.4.0" \
--set-string sourceController.tag="v1.4.1"

kubectl apply -f ./k8s/platform-charts/01_fluxcd/templates/gh-api-key-sealedsecret.yaml
sleep 5; # wait for sealed secret to be created
kubectl apply -f ./k8s/platform-charts/01_fluxcd/templates/git-repo.yaml
kubectl apply -f ./k8s/HelmRelease-prod.yaml
