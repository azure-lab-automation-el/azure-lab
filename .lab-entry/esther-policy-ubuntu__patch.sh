#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
ENTRY_FAILED=0
echo "== step =="
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
bash scripts/esther-policy-ubuntu.sh
