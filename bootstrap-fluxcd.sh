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

# give all three nodes time to start up properly
sleep 30

# Bash strict mode (second half)
set -ux

# cache required images on host (avoid re-downloading them in minikube saves traffic and time)
# See unnecessary pulls in events: kubectl get events --all-namespaces --field-selector reason=Pulling -o custom-columns=Message:.message --no-headers | grep -o '".*"' | grep -vE 'metrics-server|kindnetd|kube-vip' | sort -u
# Minikube pre-installs the metrics-server, kindnetd and kind-vip before we can warm up the Container-VM here, we can't prevent those to be pulled because it happens before we can run this script.
# Todo: renovate the versions below?
images=(
  "cr.l5d.io/linkerd/controller:edge-25.4.4"
  "cr.l5d.io/linkerd/policy-controller:edge-25.4.4"
  "cr.l5d.io/linkerd/proxy:edge-25.4.4"
  "docker.io/bitnami/sealed-secrets-controller:0.30.0"
  "docker.io/rook/ceph:v1.17.7"
  "docker.l5d.io/buoyantio/emojivoto-emoji-svc:v11"
  "docker.l5d.io/buoyantio/emojivoto-voting-svc:v11"
  "docker.l5d.io/buoyantio/emojivoto-web:v11"
  "ghcr.io/fluxcd/flux-cli:v2.6.2"
  "ghcr.io/fluxcd/helm-controller:v1.3.0"
  "ghcr.io/fluxcd/kustomize-controller:v1.6.0"
  "ghcr.io/fluxcd/source-controller:v1.6.1"
  "ghcr.io/gimlet-io/capacitor:v0.4.8"
  "ghcr.io/weaveworks/wego-app:v0.38.0"
  "quay.io/ceph/ceph:v18.2.4"
  "quay.io/cephcsi/cephcsi:v3.14.2"
  "quay.io/jetstack/cert-manager-cainjector:v1.18.1"
  "quay.io/jetstack/cert-manager-controller:v1.18.1"
  "quay.io/jetstack/cert-manager-startupapicheck:v1.18.1"
  "quay.io/jetstack/cert-manager-webhook:v1.18.1"
  "rancher/local-path-provisioner:v0.0.32"
  "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.5.4@sha256:7a38cf0f8480775baaee71ab519c7465fd1dfeac66c421f28f087786e631456e"
  "registry.k8s.io/ingress-nginx/controller:v1.12.3@sha256:ac444cd9515af325ba577b596fe4f27a34be1aa330538e8b317ad9d6c8fb94ee"
  "registry.k8s.io/sig-storage/csi-attacher:v4.8.1"
  "registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.13.0"
  "registry.k8s.io/sig-storage/csi-provisioner:v5.2.0"
  "registry.k8s.io/sig-storage/csi-resizer:v1.13.2"
  "registry.k8s.io/sig-storage/csi-snapshotter:v8.2.1"
)
# pull images
for img in "${images[@]}"; do
  (
    docker image inspect "$img" > /dev/null 2>&1 || docker pull "$img" > /dev/null
  ) &
done
wait

# load images into minikube
for img in "${images[@]}"; do
  (
    minikube image load "$img" > /dev/null 2>&1
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
--version 2.17.3  > /dev/null

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
    > k8s/platform-charts/05_weave/templates/admin-sealedsecret.yaml



# https://artifacthub.io/packages/helm/fluxcd-community/flux2
# More sophisticated config will be applied automatically, once FluxCD takes over (see flux-apps/platform/01_fluxcd/helm-release.yaml)
# Todo: renovate the versions below as well as the ones in the helm-release.yaml
helm repo add fluxcd https://fluxcd-community.github.io/helm-charts > /dev/null
helm repo update fluxcd > /dev/null
# "fluxcd" must match the spec.releaseName in k8s/platform-charts/01_fluxcd/helm-release.yaml
# to ensure that the Flux helm-chart is overridden by the flux-managed one and flux is thus managed by itself in the end.
helm install fluxcd fluxcd/flux2 \
--namespace flux-system --create-namespace \
--version 2.16.1 \
--set imageReflectionController.create=false \
--set imageAutomationController.create=false \
--set notificationController.create=false > /dev/null

kubectl apply -f ./k8s/platform-charts/01_fluxcd/templates/gh-api-key-sealedsecret.yaml > /dev/null
kubectl apply -f ./k8s/platform-charts/01_fluxcd/templates/git-repo.yaml > /dev/null

set +x

echo "Now you need to git-commit and push all changes (including the sealed secrets) to your git repository."
echo "CAUTION: the branch you want to work on must be specified in /k8s/platform-charts/01_fluxcd/templates/git-repo.yaml"
echo "Configured branch in /k8s/platform-charts/01_fluxcd/templates/git-repo.yaml:"
BRANCH=$(cat ./k8s/platform-charts/01_fluxcd/templates/git-repo.yaml | grep branch: | sed 's/.*: //')

if [ "$BRANCH" = "main" ]; then
  echo -e "Error: cannot commit to branch 'main'.\nPlease change the branch in ./k8s/platform-charts/01_fluxcd/templates/git-repo.yaml to a different branch."
fi

echo -e "Branch to commit to: \033[32m$BRANCH\033[0m"

read -p "Do you want to continue? (y/n): " answer
case "$answer" in
    [Yy]) echo "Continuing...";;
    [Nn]) echo "Exiting..."; exit 1;;
    *) echo "Invalid input"; exit 2;;
esac

git checkout "$BRANCH" || git checkout -b "$BRANCH"
git add ./k8s/platform-charts/01_fluxcd/templates/gh-api-key-sealedsecret.yaml
git add ./k8s/platform-charts/05_weave/templates/admin-sealedsecret.yaml
git commit -m 'wip'
git push -u origin "$BRANCH"

echo -e "Waiting for git changes to propagate..."
# Otherwise, we might pick up old changes from git from the same branch, and Flux won't reconcile because we didn't bump the chart versions.
# This can result in Flux not re-fetching the sealed secrets and trying to apply the old ones, which will fail because they were generated with a different key.
# If you get still problems with sealed secrets not being able to decrypt, increase the sleep time below.
sleep 5;

echo -e "applying flux-apps..."
kubectl apply -f ./k8s/HelmRelease-prod.yaml

echo -e "checking hosts file..."
if ! grep -qF -- '127.0.0.1 web.app-demo.local' /etc/hosts; then
  echo "hosts file needs updating, adding web.app-demo.local -> 127.0.0.1"
  {
    grep -vF -- 'web.app-demo.local' /etc/hosts || true
    printf '%s\n' '127.0.0.1 web.app-demo.local'
  } | sudo tee /etc/hosts >/dev/null
fi

echo -e "Waiting for helmreleases to be ready..."
sleep 10
i=0
while [ $i -lt 300 ]; do
  output=$(kubectl get helmrelease -A --no-headers)
  total=$(printf '%s\n' "$output" | wc -l)
  ready=$(printf '%s\n' "$output" | grep -c True)
  printf "\r\033[KHelmreleases ready: %d/%d (elapsed %ds)" "$ready" "$total" "$i"
  [ "$ready" -eq "$total" ] && { printf "\n"; break; }
  sleep 1
  i=$((i+1))
done
if [ $i -eq 300 ]; then
  echo -e "\nError: Not all HelmReleases are ready after 5 minutes."
  exit 1
fi

echo "Replacing pods that are not meshed with Linkerd..."
for ns in flux-system sys-cert-manager sys-sealed-secrets; do
  kubectl delete pods --all -n $ns
done

echo "Port-Forwarding the nginx ingress controller to localhost:8080..."
kubectl port-forward -n sys-nginx svc/nginx-ingress-nginx-controller 8080:80
