#!/usr/bin/env bash
set -euo pipefail
export INPUT_STAGE="${INPUT_STAGE}"
ENTRY_FAILED=0
echo "== Run =="
export STAGE="${INPUT_STAGE}"
set -euo pipefail
RG=rg-learning-monitoring; LOC=${LAB_LOCATION:-israelcentral}; DC=esther-dc-01
az vm list -g $RG -d --query "[].{vm:name,size:hardwareProfile.vmSize,power:powerState}" -o table
az vm list-usage -l $LOC --query "[?contains(name.value,'ores')].{n:name.value,cur:currentValue,lim:limit}" -o table
az vm list-skus -l $LOC --size Standard_B1s --query "[].{name:name,restr:restrictions,caps:capabilities[?name=='HyperVGenerations'||name=='TrustedLaunchDisabled'||name=='MemoryGB'||name=='vCPUs']}" -o json
echo "BEFORE_SIZE=$(az vm show -g $RG -n $DC --query hardwareProfile.vmSize -o tsv)"
az vm list-vm-resize-options -g $RG -n $DC --query "[?name=='Standard_B1s'].name" -o tsv || true
if [ "$STAGE" = resize-dc ]; then
  az vm resize -g $RG -n $DC --size Standard_B1s -o none
  echo "AFTER_SIZE=$(az vm show -g $RG -n $DC --query hardwareProfile.vmSize -o tsv)"
  pw=$(az vm get-instance-view -g $RG -n $DC --query "instanceView.statuses[?starts_with(code,'PowerState')].code" -o tsv); echo "POWER=$pw"
  if [ "$pw" = PowerState/running ]; then
    sleep 90
    az vm run-command invoke -g $RG -n $DC --command-id RunPowerShellScript --scripts "Get-Service NTDS,DNS,Netlogon,HealthService | ft Name,Status -auto | Out-String; (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors; dcdiag /test:services /q; 'DCDIAG_EXIT=' + \$LASTEXITCODE" --query "value[0].message" -o tsv
  fi
  echo DC_RESIZE_OK
fi
