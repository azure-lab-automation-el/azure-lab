#!/usr/bin/env bash
set -euo pipefail
export AZURE_CLIENT_ID="${AZURE_CLIENT_ID}"
ENTRY_FAILED=0
echo "== Preflight (read-only) =="
set -e
RG=rg-learning-monitoring
echo "provider Microsoft.Web: $(az provider show -n Microsoft.Web --query registrationState -o tsv)"
az policy assignment list -g $RG --query '[].{name:displayName,params:parameters}' -o json
az role assignment list --assignee ${AZURE_CLIENT_ID} --all --query '[].{role:roleDefinitionName,scope:scope}' -o table
az role definition list --name 'Azure Lab Builder' --query '[0].permissions[0].actions' -o json || true
az staticwebapp list -g $RG -o table || true
echo "== Create Free SWA =="
if [ "${INPUT_MODE}" = "create" ]; then
set -e
RG=rg-learning-monitoring
az staticwebapp create -n esther-cloud-admin -g $RG --location "${SWA_LOCATION:-eastus2}" --sku Free -o none
az staticwebapp show -n esther-cloud-admin -g $RG --query '{name:name,sku:sku.name,tier:sku.tier,location:location,url:defaultHostname}' -o json
fi
