#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export ESTHER_VM_ADMIN_PASSWORD="${ESTHER_VM_ADMIN_PASSWORD}"
export ESTHER_DSRM_PASSWORD="${ESTHER_DSRM_PASSWORD}"
export ESTHER_SCOM_SVC_PASSWORD="${ESTHER_SCOM_SVC_PASSWORD}"
ENTRY_FAILED=0
echo "== Phase 1 - DC esther-dc-01 (free B2ats_v2, Core, no public IP) =="
bash scripts/esther-dc-create.sh
