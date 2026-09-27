#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
ENTRY_FAILED=0
echo "== Patch and verify exact RG allowlists =="
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
bash scripts/esther-policy-patch.sh
