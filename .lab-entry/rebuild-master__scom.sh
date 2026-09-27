#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export ESTHER_VM_ADMIN_PASSWORD="${ESTHER_VM_ADMIN_PASSWORD}"
export ESTHER_DSRM_PASSWORD="${ESTHER_DSRM_PASSWORD}"
export ESTHER_SCOM_SVC_PASSWORD="${ESTHER_SCOM_SVC_PASSWORD}"
export GH_TOKEN="${GH_TOKEN}"
export MEDIA_ACCOUNT="${MEDIA_ACCOUNT}"
export STAGES="${STAGES}"
ENTRY_FAILED=0
echo "== SCOM 2025 install + console shot + AD MP + DC agent =="
bash scripts/esther-scom-phase5.sh
