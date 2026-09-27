#!/usr/bin/env bash
# mivtza-eser secrets drop: per-VM secrets.json via one run-command + bootstrap scheduled task.
# CustomData carries no secrets; this drop is the only secret path. Table/blob SAS are short-lived (8h).
set -Eeuo pipefail; set +x
: "${AZURE_SUBSCRIPTION_ID:?}" "${ESTHER_VM_ADMIN_PASSWORD:?}" "${ESTHER_DSRM_PASSWORD:?}" "${ESTHER_SCOM_SVC_PASSWORD:?}" "${MEDIA_ACCOUNT:?}"
RG=rg-learning-monitoring; P=${LAB_PREFIX:-esther}; DC=$P-dc-01; VM=$P-adaxes-01
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
KEY=$(az storage account keys list -g "$RG" -n "$MEDIA_ACCOUNT" --query '[0].value' -o tsv); echo "::add-mask::$KEY"
EXP=$(date -u -d '+8 hours' +%Y-%m-%dT%H:%MZ)
az storage table create --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -n labstate -o none 2>/dev/null || true
TSAS=$(az storage table generate-sas --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -n labstate --permissions raud --expiry "$EXP" --https-only -o tsv); echo "::add-mask::$TSAS"
BSAS=$(az storage container generate-sas --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -n media --permissions r --expiry "$EXP" --https-only -o tsv); echo "::add-mask::$BSAS"
TB="https://$MEDIA_ACCOUNT.table.core.windows.net/labstate"
MB="https://$MEDIA_ACCOUNT.blob.core.windows.net/media"
SCOM_SHA=$(az storage blob show --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c media -n scom-tree.7z --query 'metadata.sha256' -o tsv)
SZR_SHA=$(az storage blob show --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c media -n 7zr.exe --query 'metadata.sha256' -o tsv)
[ -n "$SCOM_SHA" ] && [ -n "$SZR_SHA" ] || { echo "FAIL: media blobs not staged (run media stage first)"; exit 1; }
drop() { # $1=vm $2=json
  local b64; b64=$(base64 -w0 <<<"$2")
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunPowerShellScript --parameters "b64=$b64" --scripts '
    param($b64)
    New-Item -ItemType Directory -Force C:\lab-secrets, C:\lab | Out-Null
    [IO.File]::WriteAllBytes("C:\lab-secrets\secrets.json", [Convert]::FromBase64String($b64))
    Copy-Item C:\AzureData\CustomData.bin C:\lab\bootstrap.ps1 -Force
    $act = New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\lab\bootstrap.ps1"
    $trg = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName lab-bootstrap -Action $act -Trigger $trg -User SYSTEM -RunLevel Highest -Force | Out-Null
    Start-ScheduledTask lab-bootstrap
    "bootstrap started on $env:COMPUTERNAME"' -o json | jq -r '.value[]?.message'
}
drop "$DC" "$(jq -nc --arg a "$ESTHER_VM_ADMIN_PASSWORD" --arg d "$ESTHER_DSRM_PASSWORD" --arg s "$ESTHER_SCOM_SVC_PASSWORD" --arg tb "$TB" --arg ts "$TSAS" '{admin:$a,dsrm:$d,svc:$s,tableBase:$tb,tableSas:$ts}')"
drop "$VM" "$(jq -nc --arg a "$ESTHER_VM_ADMIN_PASSWORD" --arg s "$ESTHER_SCOM_SVC_PASSWORD" --arg tb "$TB" --arg ts "$TSAS" --arg mb "$MB" --arg bs "$BSAS" --arg sc "$SCOM_SHA" --arg sz "$SZR_SHA" '{admin:$a,svc:$s,tableBase:$tb,tableSas:$ts,mediaBase:$mb,mediaSas:$bs,scomSha:$sc,szrSha:$sz}')"
echo SECRETS_V2_OK
