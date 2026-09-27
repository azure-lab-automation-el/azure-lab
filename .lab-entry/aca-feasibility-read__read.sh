#!/usr/bin/env bash
set -euo pipefail
export RG="${RG}"
ENTRY_FAILED=0
echo "== step =="
set -uo pipefail
echo "== subscription"; az account show --query "{name:name,state:state,offer:subscriptionPolicies.quotaId,spendingLimit:subscriptionPolicies.spendingLimit}" -o json
echo "== provider registration"; for p in Microsoft.App Microsoft.OperationalInsights Microsoft.ContainerRegistry; do echo "$p $(az provider show -n $p --query registrationState -o tsv)"; done
echo "== Container Apps managedEnvironments/jobs regions (israel/sweden)"; az provider show -n Microsoft.App --query "resourceTypes[?resourceType=='managedEnvironments' || resourceType=='jobs'].{t:resourceType,loc:locations}" -o json | jq -c '.[]|{t, il:(.loc|map(select(test("Israel";"i")))), se:(.loc|map(select(test("Sweden";"i"))))}'
echo "== VNets + subnets"; az network vnet list -g $RG --query "[].{vnet:name,loc:location,space:addressSpace.addressPrefixes,subnets:subnets[].{n:name,p:addressPrefix,deleg:delegations[0].serviceName}}" -o json
echo "== existing container apps envs/jobs"; az resource list --resource-type Microsoft.App/managedEnvironments -o table; az resource list --resource-type Microsoft.App/jobs -o table
echo "== policy assignments (effects that could block)"; az policy assignment list --query "[].{name:displayName,scope:scope,params:parameters}" -o json | head -c 4000; echo
echo "== usage this month (Container Apps meters)"; s=$(date -u +%Y-%m-01); e=$(date -u +%F)
az consumption usage list --start-date $s --end-date $e --query "[?contains(meterDetails.meterCategory || '', 'Container Apps') || contains(consumedService || '', 'Microsoft.App')].{m:meterDetails.meterName,q:quantity,c:pretaxCost}" -o table 2>&1 | head -20
echo ACA_READ_OK
