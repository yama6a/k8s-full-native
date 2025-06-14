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

# If env variable WEAVE_ADMIN_PASSWORD is not set, error and exit
if [ -z "${WEAVE_ADMIN_PASSWORD}" ]; then
  echo "environment variable WEAVE_ADMIN_PASSWORD is not set. Please call this script like:"
  echo "    WEAVE_ADMIN_PASSWORD=yourpassword; ./bootstrap-fluxcd.sh"
  echo "(with a leading space to avoid storing the password in bash history)"
  exit 1
fi

# Bash strict mode (second half)
set -ux

# cache required images on host (avoid re-downloading them in minikube saves traffic and time)
# See unnecessary pulls in events: kubectl get events --all-namespaces --field-selector reason=Pulling -o wide
# Minikube pre-installs the metrics-server before we can warm up the Container-VM here, so no need to list it here; it's small so, whatever ¯\_(ツ)_/¯
# Todo: renovate the versions below?
images=(
  "cr.l5d.io/linkerd/proxy:edge-24.11.8"
  "cr.l5d.io/linkerd/controller:edge-24.11.8"
  "cr.l5d.io/linkerd/policy-controller:edge-24.11.8"
  "cr.l5d.io/linkerd/proxy-init:v2.4.2"
  "quay.io/jetstack/cert-manager-controller:v1.17.1"
  "quay.io/jetstack/cert-manager-webhook:v1.17.1"
  "quay.io/jetstack/cert-manager-cainjector:v1.17.1"
  "quay.io/jetstack/cert-manager-startupapicheck:v1.17.1"
  "ghcr.io/fluxcd/source-controller:v1.4.1"
  "ghcr.io/fluxcd/helm-controller:v1.1.0"
  "ghcr.io/fluxcd/flux-cli:v2.4.0"
  "ghcr.io/fluxcd/kustomize-controller:v1.4.0"
  "docker.io/bitnami/sealed-secrets-controller:0.28.0"
  "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.4.0@sha256:44d1d0e9f19c63f58b380c5fddaca7cf22c7cee564adeff365225a5df5ef3334"
  "registry.k8s.io/ingress-nginx/controller:1.12.0@sha256:42b3f0e5d0846876b1791cd3afeb5f1cbbe4259d6f35651dcc1b5c980925379c"
  "docker.l5d.io/buoyantio/emojivoto-web:v11"
  "docker.l5d.io/buoyantio/emojivoto-voting-svc:v11"
  "ghcr.io/gimlet-io/capacitor:v0.4.8"
  "ghcr.io/weaveworks/wego-app:v0.38.0"
)
for img in "${images[@]}"; do
  (
    if ! docker image inspect "$img" > /dev/null 2>&1; then
      docker pull "$img"
    fi
    minikube image load "$img"
  ) &
done
wait

# Install sealed secrets controller (needed for FluxCD's secret containing the github API key)
# More sophisticated config will be applied once FluxCD takes over (see flux-apps/platform/02_sealed_secrets/helm-release.yaml)
# Todo: renovate the versions below as well as the ones in the helm-release.yaml
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets > /dev/null
helm repo update sealed-secrets > /dev/null
# "sealed-secrets" must match the metadata.name in k8s/platform-charts/02_sealed_secrets/helm-release.yaml
# to ensure that the Sealed Secrets helm-chart is overridden by the flux-managed one and sealed-secrets is thus managed by flux in the end.
helm install sealed-secrets sealed-secrets/sealed-secrets \
--namespace sys-sealed-secrets --create-namespace \
--version 2.17.1  > /dev/null

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

sleep 10;


# Todo: backup the sealed-secrets-controller's private key and public key on disk,
#       and find a way for it to never delete it in the cluster no matter what, even if the HelmRelease is deleted.
#       And research and document how to recover the cluster's private key from a backup.


echo "Preparing Sealed Secrets for FluxCD and Weave GitOps..."
# Create Sealed Secret (replace GITHUB token with yours from the environment)
sed "s/GITHUB_API_KEY/$GITHUB_API_KEY/g" ./bootstrap-github-api-secret-template.yaml \
    | kubeseal --controller-namespace sys-sealed-secrets --controller-name sealed-secrets --format yaml \
    > k8s/platform-charts/01_fluxcd/templates/gh-api-key-sealedsecret.yaml

export HASH=$(echo -n "$WEAVE_ADMIN_PASSWORD" | gitops get bcrypt-hash)
export ESCAPED_HASH=$(printf '%s' "$HASH" | sed 's/[\/&$]/\\&/g')

set -x

sed "s/WEAVE_ADMIN_PASSWORD/$ESCAPED_HASH/g" ./bootstrap-weave-admin-secret-template.yaml \
    | kubeseal --controller-namespace sys-sealed-secrets --controller-name sealed-secrets --format yaml \
    > k8s/platform-charts/03_weave/templates/admin-sealedsecret.yaml



# https://artifacthub.io/packages/helm/fluxcd-community/flux2
# More sophisticated config will be applied automatically, once FluxCD takes over (see flux-apps/platform/01_fluxcd/helm-release.yaml)
# Todo: renovate the versions below as well as the ones in the helm-release.yaml
helm repo add fluxcd https://fluxcd-community.github.io/helm-charts > /dev/null
helm repo update fluxcd > /dev/null
# "fluxcd" must match the spec.releaseName in k8s/platform-charts/01_fluxcd/helm-release.yaml
# to ensure that the Flux helm-chart is overridden by the flux-managed one and flux is thus managed by itself in the end.
helm install fluxcd fluxcd/flux2 \
--namespace flux-system --create-namespace \
--version 2.14.1 \
--set imageReflectionController.create=false \
--set imageAutomationController.create=false \
--set notificationController.create=false > /dev/null

kubectl apply -f ./k8s/platform-charts/01_fluxcd/templates/gh-api-key-sealedsecret.yaml > /dev/null
kubectl apply -f ./k8s/platform-charts/01_fluxcd/templates/git-repo.yaml > /dev/null

set +x

echo "Now you need to git-commit and push all changes (including the sealed secrets) to your git repository."
echo "CAUTION: the branch you want to work on must be specified in /k8s/platform-charts/01_fluxcd/templates/git-repo.yaml"
echo "Configured branch in /k8s/platform-charts/01_fluxcd/templates/git-repo.yaml:"
cat ./k8s/platform-charts/01_fluxcd/templates/git-repo.yaml | grep branch:

echo
echo "After pushing your changes, you can apply the ROOT HelmRelease manifestm to allow FluxCD to manage the rest of the cluster:"
echo kubectl apply -f ./k8s/HelmRelease-prod.yaml
