#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export ESTHER_VM_ADMIN_PASSWORD="${ESTHER_VM_ADMIN_PASSWORD}"
export MODE="${MODE}"
ENTRY_FAILED=0
echo "== Plan or create missing SCOM VM pieces (idempotent) =="
bash scripts/esther-vm-create.sh
