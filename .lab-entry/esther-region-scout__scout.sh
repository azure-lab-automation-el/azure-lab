#!/usr/bin/env bash
set -euo pipefail
ENTRY_FAILED=0
echo "== step =="
for L in israelcentral polandcentral spaincentral austriaeast switzerlandnorth germanywestcentral francecentral swedencentral northeurope westeurope; do echo "== $L"
  az vm list-skus -l $L --size Standard_B --all -o json | jq -r '.[]|select(.name=="Standard_B1s" or .name=="Standard_B2ats_v2" or .name=="Standard_B1ls" or .name=="Standard_B2pts_v2" or .name=="Standard_B2als_v2" or .name=="Standard_B2s")|"\(.name) restr=\([.restrictions[]?.reasonCode]|join(","))"'
done
echo "== policy"; az policy assignment list --disable-scope-strict-match --query "[].{n:name,d:displayName,scope:scope,p:parameters}" -o json | head -c 3000
az network vnet list -g rg-learning-monitoring --query "[].{n:name,l:location,a:addressSpace.addressPrefixes}" -o json
