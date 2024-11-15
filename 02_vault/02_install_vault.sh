#!/usr/bin/env bash

# bash strict mode
set -euxo pipefail

kubectl apply -f 02_vault/
