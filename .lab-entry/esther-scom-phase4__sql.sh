#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export ESTHER_SCOM_SVC_PASSWORD="${ESTHER_SCOM_SVC_PASSWORD}"
export MEDIA_ACCOUNT="${MEDIA_ACCOUNT}"
export STAGES="${STAGES}"
export GH_TOKEN="${GH_TOKEN}"
export RESTART="${RESTART}"
ENTRY_FAILED=0
echo "== Phase 4 - SSRS finish, cleanup, SCOM prerequisites + media =="
source scripts/lib/watchdog.sh 25 phase4
bash scripts/esther-scom-phase4.sh
