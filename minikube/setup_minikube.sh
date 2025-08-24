#!/usr/bin/env bash

# bash strict mode
set -euo pipefail

CLUSTER_NAME="kfn"

# if using Rancher Desktop, ensure inotify limits are set correctly - the default values are too low for a multi-node minikube cluster.
if ! command -v rdctl >/dev/null 2>&1; then
  echo "⚠️  If you experience Kubernetes errors such as 'too many open files', please increase the inotify limits on your host system."
  echo "⚠️  Ref: https://00formicapunk00.wordpress.com/2024/12/10/too-many-open-files-in-minikube-pod/"
else
  if ! rdctl shell -- sysctl fs.inotify.max_user_watches | grep 524288 >/dev/null; then
    echo " ⏳ Increasing inotify.max_user_watches limits ..."
    rdctl shell -- sudo sysctl -w fs.inotify.max_user_watches=524288 > /dev/null
  fi
  if ! rdctl shell -- sysctl fs.inotify.max_user_instances | grep 512 >/dev/null; then
    echo " ⏳ Increasing inotify.max_user_instances limits ..."
    rdctl shell -- sudo sysctl -w fs.inotify.max_user_instances=512 > /dev/null
  fi
fi

## check if minikube profile 'kfn' already exists, offer to cleanup if it does
if minikube profile list 2>/dev/null | grep 'kfn' > /dev/null; then
  echo "⚠️  Minikube profile 'kfn' already exists"
  echo " ❓ Do you want to delete it and create a new one? (y/n)"
  read -r answer
  if [ "$answer" != "${answer#[Yy]}" ] ;then
    minikube delete --profile="${CLUSTER_NAME}"
  else
    echo " ❌ Exiting..."
    exit 1
  fi
fi


# Info:
# --addons=metrics-server       # is needed for the metrics server to be installed in the cluster, which is required by the linkerd control plane.
# --nodes=3                     # is needed to have enough nodes for rook/ceph to be installed and distribute/replicate storage, which is required by the CNPG operator.
# --cpus=3                      # if we have 3 nodes. With 1 node, use 8 or more.
# --memory=4096                 # if we have 3 nodes. With 1 node, use 8GB or more.
# --disk-size=100g              # not sure yet why we need this much disk space. But I remember that this was on purpose, even wayy before we touched rook/ceph. Re-visit this later.
# --delete-on-failure=true      # is needed to delete the minikube cluster if it fails to start, so that we can re-try without having to manually delete the cluster.
# --driver=docker               # using virtualization like vfkit caused problems with networking that I didn't want to debug right now. Only downside: need to port-forward the nginx port after setting up the cluster to enable local testing.
# --kubernetes-version=v1.33.1  # find supported k8s version here: https://github.com/kubernetes/minikube/releases or `minikube config defaults kubernetes-version | head -n 10`
# --subnet=172.17.128.0/17      # is used to avoid conflicts with docker's default subnet
# --wait=all                    # wait for all k8s control-plane components to be ready before exiting the start command
# --wait-timeout=5m             # wait up to 5 minutes for all k8s components to be ready

# start minikube
minikube unpause || minikube start \
--profile="${CLUSTER_NAME}" \
--nodes 3 \
--cpus=3 \
--memory=4096 \
--disk-size=100g \
--delete-on-failure=true \
--driver=docker \
--kubernetes-version=v1.33.1 \
--subnet=172.17.128.0/17 \
--wait=all \
--wait-timeout=5m

# cache required images on nodes (avoid re-downloading them saves traffic and time - minikube would pull them off the internet instead of using the local docker cache)
# See unnecessary pulls in events: kubectl get events --all-namespaces --field-selector reason=Pulling -o custom-columns=Message:.message --no-headers | grep -o '".*"' | grep -vE 'kindnetd|kube-vip' | sort -u
# Minikube pre-installs the metrics-server, kindnetd and kind-vip before we can warm up the Container-VM here, we can't prevent those to be pulled because it happens before we can run this script.
# Todo: renovate the versions below?
images=(
  "cr.l5d.io/linkerd/controller:edge-25.4.4"
  "cr.l5d.io/linkerd/policy-controller:edge-25.4.4"
  "cr.l5d.io/linkerd/proxy:edge-25.4.4"
  "docker.io/bitnami/sealed-secrets-controller:0.30.0"
  "docker.l5d.io/buoyantio/emojivoto-emoji-svc:v11"
  "docker.l5d.io/buoyantio/emojivoto-voting-svc:v11"
  "docker.l5d.io/buoyantio/emojivoto-web:v11"
  "ghcr.io/fluxcd/flux-cli:v2.6.2"
  "ghcr.io/fluxcd/helm-controller:v1.3.0"
  "ghcr.io/fluxcd/kustomize-controller:v1.6.0"
  "ghcr.io/fluxcd/source-controller:v1.6.1"
  "ghcr.io/gimlet-io/capacitor:v0.4.8"
  "ghcr.io/weaveworks/wego-app:v0.38.0"
  "quay.io/jetstack/cert-manager-cainjector:v1.18.1"
  "quay.io/jetstack/cert-manager-controller:v1.18.1"
  "quay.io/jetstack/cert-manager-startupapicheck:v1.18.1"
  "quay.io/jetstack/cert-manager-webhook:v1.18.1"
  "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.5.4@sha256:7a38cf0f8480775baaee71ab519c7465fd1dfeac66c421f28f087786e631456e"
  "registry.k8s.io/ingress-nginx/controller:v1.12.3@sha256:ac444cd9515af325ba577b596fe4f27a34be1aa330538e8b317ad9d6c8fb94ee"
  "registry.k8s.io/metrics-server/metrics-server:v0.7.2@sha256:ffcb2bf004d6aa0a17d90e0247cf94f2865c8901dcab4427034c341951c239f9"
  "registry.k8s.io/sig-storage/csi-attacher:v4.0.0@sha256:9a685020911e2725ad019dbce6e4a5ab93d51e3d4557f115e64343345e05781b"
  "registry.k8s.io/sig-storage/csi-external-health-monitor-controller:v0.7.0@sha256:80b9ba94aa2afe24553d69bd165a6a51552d1582d68618ec00d3b804a7d9193c"
  "registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.6.0@sha256:f1c25991bac2fbb7f5fcf91ed9438df31e30edee6bed5a780464238aa09ad24c"
  "registry.k8s.io/sig-storage/csi-provisioner:v3.3.0@sha256:ee3b525d5b89db99da3b8eb521d9cd90cb6e9ef0fbb651e98bb37be78d36b5b8"
  "registry.k8s.io/sig-storage/csi-resizer:v1.6.0@sha256:425d8f1b769398127767b06ed97ce62578a3179bcb99809ce93a1649e025ffe7"
  "registry.k8s.io/sig-storage/csi-snapshotter:v6.1.0@sha256:291334908ddf71a4661fd7f6d9d97274de8a5378a2b6fdfeb2ce73414a34f82f"
  "registry.k8s.io/sig-storage/hostpathplugin:v1.9.0@sha256:92257881c1d6493cf18299a24af42330f891166560047902b8d431fb66b01af5"
  "registry.k8s.io/sig-storage/livenessprobe:v2.8.0@sha256:cacee2b5c36dd59d4c7e8469c05c9e4ef53ecb2df9025fa8c10cdaf61bce62f0"
)
# pull images
for img in "${images[@]}"; do
  (
    echo "Pulling $img"
    docker image inspect "$img" > /dev/null 2>&1 || docker pull "$img" > /dev/null
  ) &
done
wait

# load images into minikube
for img in "${images[@]}"; do
  (
    echo "Loading image into minikube: $img"
    minikube -p kfn image load "$img" > /dev/null 2>&1
  ) &
done
wait


# now that all images are available on all nodes, enable the required minikube addons
minikube -p kfn addons enable metrics-server
minikube -p kfn addons enable csi-hostpath-driver

kubectl apply -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/storageClass.yaml"
