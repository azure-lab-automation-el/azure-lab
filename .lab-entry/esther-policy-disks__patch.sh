#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID GH_TOKEN
echo "== מדיניות דיסקים: אישור 128GB (מסלול A, בגיבוי מילתו) =="
bash scripts/esther-policy-disks.sh
