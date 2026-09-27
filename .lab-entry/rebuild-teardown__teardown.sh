#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export INPUT_CONFIRM="${INPUT_CONFIRM}"
ENTRY_FAILED=0
echo "== Teardown (dry-run unless DELETE) =="
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export CONFIRM="${INPUT_CONFIRM}"
bash rebuild/teardown.sh
