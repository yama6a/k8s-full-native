#!/usr/bin/env bash

# Bash strict mode
set -euxo pipefail

# Install Linkerd CLI
brew install linkerd step openssl

# Certs: https://linkerd.io/2-edge/tasks/generate-certificates/
# Generate a certificate authority (valid for 30y)
step certificate create root.linkerd.cluster.local linkerd_ca.crt linkerd_ca.key \
--profile root-ca \
--no-password \
--insecure \
--not-after 262800h

# Generate Linkerd Issuer certificate and key
step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
--profile intermediate-ca \
--not-after 262800h \
--ca linkerd_ca.crt \
--ca-key linkerd_ca.key


# Preflight Check
linkerd check --pre

# Set up Linkerd Helm repo
helm repo add linkerd-edge https://helm.linkerd.io/edge

# Install Linkerd CRDs
helm install linkerd-crds linkerd-edge/linkerd-crds -n sys-linkerd

# Install Linkerd Control Plane
helm install linkerd-control-plane \
  -n sys-linkerd \
  --set-file identityTrustAnchorsPEM=ca.crt \
  --set-file identity.issuer.tls.crtPEM=issuer.crt \
  --set-file identity.issuer.tls.keyPEM=issuer.key \
  --set proxy.nativeSidecar=true \
  linkerd-edge/linkerd-control-plane

# Todo: figure out how to push the ca.crt and issuer.crt and issuer.key into secrets and load them in the helm chart
# Exmaple: https://chatgpt.com/c/67a8fc2d-2b54-8000-8009-3429c5173810
