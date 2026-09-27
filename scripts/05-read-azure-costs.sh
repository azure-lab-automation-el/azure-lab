#!/usr/bin/env bash
set -Eeuo pipefail
# Read-only. Run after OIDC/SP login. Never triggers interactive login or touches billing/payment settings.
: "${AZURE_SUBSCRIPTION_ID:=bb3344d8-d9bf-4e96-923b-473b2da17459}"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
az account show --query '{subscription:id,name:name,tenantId:tenantId,state:state,user:user}' -o json
from=$(date -u -d '30 days ago' +%Y-%m-%d)
to=$(date -u -d 'tomorrow' +%Y-%m-%d)
body=$(jq -nc --arg from "$from" --arg to "$to" '{type:"ActualCost",timeframe:"Custom",timePeriod:{from:($from+"T00:00:00Z"),to:($to+"T00:00:00Z")},dataset:{granularity:"Daily",aggregation:{cost:{name:"Cost",function:"Sum"}},grouping:[{type:"Dimension",name:"ResourceGroupName"},{type:"Dimension",name:"ServiceName"}]}}')
url="https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.CostManagement/query?api-version=2025-03-01"
ok=0
for i in 1 2 3 4 5 6; do
  if az rest --method POST --url "$url" --body "$body" > azure-cost-30d.json 2> cost-err.txt; then ok=1; break; fi
  if grep -q '429' cost-err.txt; then echo "cost API throttled (429), retry $i in $((i*20))s"; sleep $((i*20)); continue; fi
  cat cost-err.txt; break
done
[ $ok = 1 ] || { echo "COST QUERY FAILED"; echo "{}" > azure-cost-30d.json; }
jq "{columns:[.properties.columns[]?.name],rows:.properties.rows}" azure-cost-30d.json || true
# Resource inventory and current power states support burn interpretation.
az resource list --query '[].{name:name,type:type,group:resourceGroup,location:location}' -o json > azure-resource-inventory.json
az vm list -d --query '[].{name:name,group:resourceGroup,power:powerState,size:hardwareProfile.vmSize,publicIps:publicIps}' -o json > azure-vm-state.json
jq . azure-vm-state.json
printf 'NOTE: Cost Management ActualCost is not the Azure Free credit balance. Remaining promotional credit may only be exposed at the billing-account scope/portal for this offer. Do not calculate “remaining” as 200 minus this output unless the grant start, adjustments, taxes, and all charges are confirmed.\n'
# Meter-level breakdown (compute vs disk vs network), daily, with quantity.
mbody=$(jq -nc --arg from "$from" --arg to "$to" '{type:"ActualCost",timeframe:"Custom",timePeriod:{from:($from+"T00:00:00Z"),to:($to+"T00:00:00Z")},dataset:{granularity:"Daily",aggregation:{cost:{name:"Cost",function:"Sum"},qty:{name:"UsageQuantity",function:"Sum"}},grouping:[{type:"Dimension",name:"MeterCategory"},{type:"Dimension",name:"MeterSubCategory"},{type:"Dimension",name:"Meter"},{type:"Dimension",name:"ResourceId"}]}}')
for i in 1 2 3 4 5 6; do
  if az rest --method POST --url "$url" --body "$mbody" > azure-cost-meters.json 2> cost-err.txt; then break; fi
  if grep -q '429' cost-err.txt; then echo "meter query throttled, retry $i"; sleep $((i*20)); continue; fi
  cat cost-err.txt; echo '{}' > azure-cost-meters.json; break
done
jq -r '.properties.columns as $c | .properties.rows[]? | [ .[] ] | @tsv' azure-cost-meters.json || true
