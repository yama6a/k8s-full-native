#!/usr/bin/env bash

# Bash strict mode
set -euxo pipefail

# Install Linkerd CLI
brew install linkerd step openssl

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

# Install Linkerd
