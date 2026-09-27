#!/usr/bin/env bash
# Read-only: dump lab-vm-images + lab-vm-skus assignments for diff diagnosis.
set -uo pipefail
: "${AZURE_SUBSCRIPTION_ID:?}"
SCOPE="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/rg-learning-monitoring"
API='2025-03-01'
for A in lab-vm-images lab-vm-skus lab-types lab-locations; do
  echo "== $A =="
  az rest --only-show-errors --method get \
    --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyAssignments/${A}?api-version=${API}" \
    | jq '{name, id, identity, location, properties: (.properties | del(.description))}'
done
