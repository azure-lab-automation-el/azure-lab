#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export ESTHER_VM_ADMIN_PASSWORD="${ESTHER_VM_ADMIN_PASSWORD}"
ENTRY_FAILED=0
echo "== Phase 2 - Esther normal pricing, B2as_v2, join esther.lab =="
bash scripts/esther-scom-phase2.sh
