#!/usr/bin/env bash
set -euo pipefail
export RG="${RG}"
export LOC="${LOC}"
export VNET="${VNET}"
export SUB="${SUB}"
export ENVN="${ENVN}"
export JOB="${JOB}"
export INPUT_STAGE="${INPUT_STAGE}"
ENTRY_FAILED=0
echo "== Setup =="
export STAGE="${INPUT_STAGE}"
set -euo pipefail
az extension add -n containerapp --upgrade -y --only-show-errors >/dev/null 2>&1 || true
show() {
  echo "== state"; echo "provider Microsoft.App: $(az provider show -n Microsoft.App --query registrationState -o tsv)"
  az network vnet subnet show -g $RG --vnet-name $VNET -n $SUB --query "{subnet:name,prefix:addressPrefix,delegation:delegations[0].serviceName}" -o json 2>/dev/null || echo "subnet: none"
  az containerapp env show -g $RG -n $ENVN --query "{env:name,state:properties.provisioningState,internal:properties.vnetConfiguration.internal,logs:properties.appLogsConfiguration.destination,profiles:properties.workloadProfiles[].{n:name,t:workloadProfileType}}" -o json 2>/dev/null || echo "env: none"
  az containerapp job show -g $RG -n $JOB --query "{job:name,trigger:properties.configuration.triggerType,cpu:properties.template.containers[0].resources.cpu,mem:properties.template.containers[0].resources.memory,max:properties.configuration.eventTriggerConfig.scale.maxExecutions,image:properties.template.containers[0].image}" -o json 2>/dev/null || echo "job: none"
}
if [ "$STAGE" = infra ]; then
  echo "== 1 register Microsoft.App"; az provider register -n Microsoft.App --wait && echo REGISTER_OK
  echo "== 2 subnet"; az network vnet subnet show -g $RG --vnet-name $VNET -n $SUB -o none 2>/dev/null || az network vnet subnet create -g $RG --vnet-name $VNET -n $SUB --address-prefixes 10.78.2.0/27 --delegations Microsoft.App/environments -o none; echo SUBNET_OK
  SID=$(az network vnet subnet show -g $RG --vnet-name $VNET -n $SUB --query id -o tsv)
  echo "== 3 environment (internal, Consumption only, logs none)"
  az containerapp env show -g $RG -n $ENVN -o none 2>/dev/null || az containerapp env create -g $RG -n $ENVN -l $LOC --infrastructure-subnet-resource-id "$SID" --internal-only true --logs-destination none --enable-workload-profiles -o none
  echo ENV_OK
fi
show
# Guard: the environment must hold only the free Consumption profile (no Dedicated base charge).
n=$(az containerapp env show -g $RG -n $ENVN --query "length(properties.workloadProfiles[?workloadProfileType!='Consumption'])" -o tsv 2>/dev/null || echo 0); [ "${n:-0}" = 0 ] && echo "COST_GUARD_OK (no Dedicated profiles)" || { echo "COST_GUARD_FAIL: dedicated profiles present"; exit 1; }
