#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export ESTHER_VM_ADMIN_PASSWORD="${ESTHER_VM_ADMIN_PASSWORD}"
export ESTHER_DSRM_PASSWORD="${ESTHER_DSRM_PASSWORD}"
export ESTHER_SCOM_SVC_PASSWORD="${ESTHER_SCOM_SVC_PASSWORD}"
export GH_TOKEN="${GH_TOKEN}"
ENTRY_FAILED=0
echo "== SCOM VM only (idempotent; network job owns VNet/NSG) =="
MODE=vm bash scripts/esther-vm-create.sh
