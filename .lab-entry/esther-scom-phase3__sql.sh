#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export ESTHER_SCOM_SVC_PASSWORD="${ESTHER_SCOM_SVC_PASSWORD}"
export MEDIA_ACCOUNT="${MEDIA_ACCOUNT}"
export STAGES="${STAGES}"
ENTRY_FAILED=0
echo "== Phase 3 - SQL 2022 Developer + FTS + SSRS =="
source scripts/lib/watchdog.sh 95 phase3
bash scripts/esther-scom-phase3.sh
