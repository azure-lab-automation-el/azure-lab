#!/usr/bin/env bash
set -euo pipefail
export INPUT_HOSTNAME="${INPUT_HOSTNAME}"
export INPUT_REMOVE="${INPUT_REMOVE}"
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
ENTRY_FAILED=0
echo "== Roles, bind and read back =="
export HOST="${INPUT_HOSTNAME}"
export OLD="${INPUT_REMOVE}"
# CID provided by launcher env (vars[matrix.id])
export SUB="${AZURE_SUBSCRIPTION_ID}"
RG=rg-esther-portal; N=esther-cloud-admin
az account set -s "$SUB" 2>/dev/null || echo "no subscription access for $CID"
echo "== roles for $CID"; az role assignment list --assignee "$CID" --all --query '[].{role:roleDefinitionName,scope:scope}' -o table || true
az staticwebapp show -n $N -g $RG --query '{sku:sku.name,url:defaultHostname}' -o json || { echo "cannot read SWA"; exit 1; }
[ -n "$OLD" ] && { az staticwebapp hostname delete -n $N -g $RG --hostname "$OLD" --yes && echo "removed $OLD"; }
az staticwebapp hostname set -n $N -g $RG --hostname "$HOST" --no-wait || exit 1
for i in $(seq 1 30); do s=$(az staticwebapp hostname show -n $N -g $RG --hostname "$HOST" --query status -o tsv 2>/dev/null); echo "status: $s"; [ "$s" = Ready ] && break; [ "$s" = Failed ] && exit 1; sleep 20; done
az staticwebapp hostname list -n $N -g $RG -o table
