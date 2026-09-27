#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
ENTRY_FAILED=0
echo "== Read =="
RG=rg-learning-monitoring
echo "== DISKS"; az disk list -g $RG --query "[].{n:name,gb:diskSizeGb,sku:sku.name,tier:tier,created:timeCreated,state:diskState}" -o table; echo; az disk list --query "[].{n:name,rg:resourceGroup,gb:diskSizeGb,sku:sku.name,tier:tier,state:diskState}" -o table || true
echo "== VMS"; az vm list -d --query "[].{n:name,size:hardwareProfile.vmSize,power:powerState,os:storageProfile.osDisk.osType,pip:publicIps,priv:privateIps}" -o table || true
echo "== PUBLIC IPS"; az network public-ip list --query "[].{n:name,sku:sku.name,ip:ipAddress}" -o table || true
echo "== SUBNETS"; for v in $(az network vnet list -g $RG --query "[].name" -o tsv); do az network vnet subnet list -g $RG --vnet-name $v --query "[].{vnet:'$v',n:name,prefix:addressPrefix,defaultOutbound:defaultOutboundAccess,nat:natGateway.id}" -o table; done || true
echo "== SKU CAPS"; for s in Standard_B2ats_v2 Standard_B2pts_v2 Standard_B1s Standard_B1ls; do echo "-- $s"; az vm list-skus -l israelcentral --size $s --all --query "[?name=='$s'].{name:name,restr:restrictions[].reasonCode,caps:capabilities[?contains('EphemeralOSDiskSupported MaxResourceVolumeMB vCPUs MemoryGB HyperVGenerations CpuArchitectureType PremiumIO',name)].[name,value]}" -o json; done
echo "== DISK SKU CHANGES (activity log)"; az monitor activity-log list -g $RG --offset 30d --query "[?operationName.value=='Microsoft.Compute/disks/write' && status.value=='Succeeded'].{t:eventTimestamp,disk:resourceId}" -o tsv | sed "s#/subscriptions/.*/disks/##" | sort | head -80
echo "== VM power events"; az monitor activity-log list -g $RG --offset 30d --query "[?(operationName.value=='Microsoft.Compute/virtualMachines/start/action' || operationName.value=='Microsoft.Compute/virtualMachines/deallocate/action') && status.value=='Succeeded'].{t:eventTimestamp,op:operationName.value,vm:resourceId}" -o tsv | sed "s#/subscriptions/.*/virtualMachines/##" | sort | head -80
echo "== COST QUERY (disk meters, month to date)"; az rest --method post --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.CostManagement/query?api-version=2023-11-01" --body '{"type":"Usage","timeframe":"MonthToDate","dataset":{"granularity":"None","aggregation":{"q":{"name":"UsageQuantity","function":"Sum"},"c":{"name":"PreTaxCost","function":"Sum"}},"grouping":[{"type":"Dimension","name":"Meter"}]}}' --query "properties.rows" -o tsv 2>&1 | head -40
echo "== USAGE THIS MONTH"; az consumption usage list --start-date $(date -u +%Y-%m-01) --end-date $(date -u +%Y-%m-%d) --query "[].{meter:meterDetails.meterName,cat:meterDetails.meterCategory,qty:usageQuantity,cost:pretaxCost}" -o table 2>&1 | head -60 || true
