#!/usr/bin/env bash
set -euo pipefail
ENTRY_FAILED=0
echo "== Safe readback diagnostics =="
set -Eeuo pipefail
az vm show -d -g rg-learning-monitoring -n esther-adaxes-01 -o json >/tmp/vm.json
jq -r '
  "READBACK_SCHEMA keys=" + (keys|sort|join(",")),
  "CHECK location=" + (((.location|ascii_downcase)=="israelcentral")|tostring),
  "CHECK size=" + ((.hardwareProfile.vmSize=="Standard_B2als_v2")|tostring),
  "CHECK publisher=" + ((.storageProfile.imageReference.publisher=="MicrosoftWindowsServer")|tostring),
  "CHECK offer=" + ((.storageProfile.imageReference.offer=="WindowsServer")|tostring),
  "CHECK sku=" + ((.storageProfile.imageReference.sku=="2022-datacenter-azure-edition-smalldisk")|tostring),
  "CHECK disk64=" + ((.storageProfile.osDisk.diskSizeGb==64)|tostring),
  "CHECK premium=" + ((.storageProfile.osDisk.managedDisk.storageAccountType=="Premium_LRS")|tostring),
  "CHECK no_public_ips=" + (((.publicIps==null) or (.publicIps==""))|tostring)
' /tmp/vm.json
az vm get-instance-view -g rg-learning-monitoring -n esther-adaxes-01 --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus | [0]" -o tsv | sed 's/^/POWER_STATE=/'
printf 'PUBLIC_IP_COUNT=%s\n' "$(az network public-ip list -g rg-learning-monitoring --query 'length(@)' -o tsv)"
printf 'CUSTOM_NSG_RULE_COUNT=%s\n' "$(az network nsg rule list -g rg-learning-monitoring --nsg-name esther-lab-nsg --query 'length(@)' -o tsv)"
