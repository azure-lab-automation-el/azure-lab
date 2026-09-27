#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export AZURE_CLIENT_ID="${AZURE_CLIENT_ID}"
ENTRY_FAILED=0
echo "== Verify constrained read access =="
set -euo pipefail
az account show --query '{name:name,state:state,tenantId:tenantId}' --output json
az group show --name rg-learning-monitoring --query '{name:name,location:location,provisioningState:properties.provisioningState}' --output json
az resource list --resource-group rg-learning-monitoring --query '[].{name:name,type:type,location:location}' --output json
az role assignment list --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/rg-learning-monitoring" --assignee "${AZURE_CLIENT_ID}" --query '[].{role:roleDefinitionName,scope:scope}' --output json
