#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
ENTRY_FAILED=0
echo "== step =="
S=/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/rg-learning-monitoring
a=$(az rest --method get --url "https://management.azure.com$S/providers/Microsoft.Authorization/policyAssignments/lab-vm-images?api-version=2025-03-01")
echo "$a" | jq -c '.properties.parameters'
d=$(echo "$a" | jq -r .properties.policyDefinitionId); echo "DEF=${d##*/}"
az rest --method get --url "https://management.azure.com$d?api-version=2025-03-01" | jq -c '.properties.policyRule'
echo "== ALL ASSIGNMENTS AFFECTING RG"
az policy assignment list -g rg-learning-monitoring --disable-scope-strict-match --query "[].{n:name,scope:scope,def:policyDefinitionId,params:parameters}" -o json | jq -c '.[]|{n,scope:(.scope|sub("/subscriptions/[^/]+";"/sub")),def:(.def|split("/")[-1]),params}' | grep -iE 'image|publisher|offer' 
echo "== SKU/DISK/TYPE/LOCATION ASSIGNMENTS"
for n in lab-vm-skus lab-disks lab-types lab-locations; do echo "-- $n"; az rest --method get --url "https://management.azure.com$S/providers/Microsoft.Authorization/policyAssignments/$n?api-version=2025-03-01" | jq -c '.properties.parameters'; done
