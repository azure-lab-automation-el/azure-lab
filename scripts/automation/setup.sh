#!/usr/bin/env bash
set -uo pipefail
RG=rg-learning-monitoring
SUB=$AZURE_SUBSCRIPTION_ID
case "$STAGE" in
read)
  echo "== VMs"; az vm list -g $RG -d --query "[].{n:name,loc:location,power:powerState,ip:privateIps,pub:publicIps}" -o table
  echo "== VNets/subnets outbound"; az network vnet list -g $RG --query "[].{vnet:name,loc:location,subnets:subnets[].{n:name,p:addressPrefix,defOut:defaultOutboundAccess,nat:natGateway.id,deleg:delegations[0].serviceName}}" -o json
  echo "== NAT gateways"; az network nat gateway list -g $RG -o table
  echo "== lab-types allow-list"; az rest --method get --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Authorization/policyAssignments/lab-types?api-version=2025-03-01" --query "{def:properties.policyDefinitionId,params:properties.parameters}" -o json
  echo "== providers"; for p in Microsoft.Automation Microsoft.HybridCompute; do echo "$p $(az provider show -n $p --query registrationState -o tsv)"; done
  echo "== adaxes extensions"; az vm extension list -g $RG --vm-name esther-adaxes-01 --query "[].{n:name,t:typePropertiesType,pub:publisher,state:provisioningState}" -o table
  echo "== egress test from esther-adaxes-01"
  timeout 300 az vm run-command invoke -g $RG -n esther-adaxes-01 --command-id RunPowerShellScript --scripts '
foreach($u in "https://management.azure.com","https://login.microsoftonline.com","https://github.com","https://ilc-jobruntimedata-prod-su1.azure-automation.net"){ $sw=[Diagnostics.Stopwatch]::StartNew(); try{ $r=Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 15 -Method Head; $c=$r.StatusCode }catch{ $c=$_.Exception.Message.Substring(0,[Math]::Min(90,$_.Exception.Message.Length)) }; "egress $u -> $c ms=$($sw.ElapsedMilliseconds)" }
"ps=" + $PSVersionTable.PSVersion; "os=" + (Get-CimInstance Win32_OperatingSystem).Caption
' --query "value[].message" -o tsv
  ;;
aca-subnet-delete)
  # Unused, empty, free; recreatable any time with the same prefix/delegation.
  az network vnet subnet show -g $RG --vnet-name esther-se-vnet -n esther-aca-subnet --query "{p:addressPrefix,deleg:delegations[0].serviceName,ipconf:length(ipConfigurations||\`[]\`),sal:length(serviceAssociationLinks||\`[]\`)}" -o json
  az network vnet subnet delete -g $RG --vnet-name esther-se-vnet -n esther-aca-subnet && echo ACA_SUBNET_DELETED
  az network vnet subnet list -g $RG --vnet-name esther-se-vnet --query "[].{n:name,p:addressPrefix}" -o table ;;
*) echo "unknown stage $STAGE"; exit 1;;
esac
