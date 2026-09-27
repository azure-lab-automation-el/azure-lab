#!/usr/bin/env bash
set -euo pipefail
ENTRY_FAILED=0
echo "== Offer type (read-only) =="
set -uo pipefail
sid=$(az account show --query id -o tsv)
echo "== subscription policies"
az rest --method get --url "https://management.azure.com/subscriptions/$sid?api-version=2022-12-01" --query "{name:displayName,state:state,quotaId:subscriptionPolicies.quotaId,spendingLimit:subscriptionPolicies.spendingLimit,locationPlacementId:subscriptionPolicies.locationPlacementId}" -o json
echo "== existing automation accounts"
az resource list --resource-type Microsoft.Automation/automationAccounts -o table || true
echo "== existing log analytics workspaces"
az resource list --resource-type Microsoft.OperationalInsights/workspaces -o table || true
