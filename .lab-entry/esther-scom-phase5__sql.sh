#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export ESTHER_SCOM_SVC_PASSWORD="${ESTHER_SCOM_SVC_PASSWORD}"
export ESTHER_VM_ADMIN_PASSWORD="${ESTHER_VM_ADMIN_PASSWORD}"
export MEDIA_ACCOUNT="${MEDIA_ACCOUNT}"
export STAGES="${STAGES}"
export GH_TOKEN="${GH_TOKEN}"
ENTRY_FAILED=0
echo "== Phase 5 - SCOM 2025 install + console screenshot =="
source scripts/lib/watchdog.sh 95 phase5
bash scripts/esther-scom-phase5.sh
