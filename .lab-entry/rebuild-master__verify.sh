#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export ESTHER_VM_ADMIN_PASSWORD="${ESTHER_VM_ADMIN_PASSWORD}"
export ESTHER_DSRM_PASSWORD="${ESTHER_DSRM_PASSWORD}"
export ESTHER_SCOM_SVC_PASSWORD="${ESTHER_SCOM_SVC_PASSWORD}"
export GH_TOKEN="${GH_TOKEN}"
ENTRY_FAILED=0
echo "== Verify lab end state =="
set -euo pipefail
RG=rg-learning-monitoring
az vm list -g $RG -d --query '[].{vm:name,size:hardwareProfile.vmSize,power:powerState}' -o table
az disk list -g $RG --query '[].{disk:name,sku:sku.name}' -o table
P=${LAB_PREFIX:-esther}
az vm run-command invoke -g $RG -n $P-adaxes-01 --command-id RunPowerShellScript \
  --scripts 'try { $r = Invoke-WebRequest http://localhost/OperationsManager -UseBasicParsing -TimeoutSec 20; "WEBCONSOLE_HTTP $($r.StatusCode)" } catch { "WEBCONSOLE_FAIL $($_.Exception.Message)" }; (Get-Service OM* | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join " "' \
  -o json | jq -r '.value[]?.message' || true
echo REBUILD_VERIFY_DONE
