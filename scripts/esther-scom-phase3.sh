#!/usr/bin/env bash
# Phase 3 of the SCOM lab: SQL Server 2022 Developer + Full-Text + SSRS (native mode) on esther-adaxes-01, all through run-command.
# Esther has no internet (private subnet). The runner downloads the media and stages it in a same-region Storage blob;
# Esther pulls it with short-lived read-only SAS URLs. The storage account is created only if missing (owner-approved item).
set -Eeuo pipefail; set +x
step=startup; trap 'printf "ERROR step=%s line=%s\n" "$step" "${BASH_LINENO[0]:-?}" >&2' ERR
: "${AZURE_SUBSCRIPTION_ID:?}" "${ESTHER_SCOM_SVC_PASSWORD:?}" "${MEDIA_ACCOUNT:?set MEDIA_ACCOUNT}"
RG=rg-learning-monitoring; P=${LAB_PREFIX:-esther}; VM=$P-adaxes-01; DC=$P-dc-01; LOC=${LAB_LOCATION:-israelcentral}; C=media
ISO_URL='https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLServer2022-x64-ENU-Dev.iso'
SSRS_URL='https://download.microsoft.com/download/8/3/2/832616ff-af64-42b5-a0b1-5eb07f71dec9/SQLServerReportingServices.exe'
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
step=storage
if ! az storage account show -g "$RG" -n "$MEDIA_ACCOUNT" -o none 2>/dev/null; then
  az storage account create -g "$RG" -n "$MEDIA_ACCOUNT" -l "$LOC" --sku Standard_LRS --kind StorageV2 --access-tier Hot \
    --allow-blob-public-access false --min-tls-version TLS1_2 --https-only true -o none
fi
KEY=$(az storage account keys list -g "$RG" -n "$MEDIA_ACCOUNT" --query '[0].value' -o tsv); echo "::add-mask::$KEY"
az storage container create --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -n "$C" -o none
step=stage
stage() { local name=$1 url=$2
  if [[ "$(az storage blob exists --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c "$C" -n "$name" --query exists -o tsv)" != true ]]; then
    curl -fsSL "$url" -o "/tmp/$name"; az storage blob upload --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c "$C" -n "$name" -f "/tmp/$name" --overwrite -o none; rm -f "/tmp/$name"; fi
  echo "staged $name"; }
stage SQL2022-Dev.iso "$ISO_URL"; stage SQLServerReportingServices.exe "$SSRS_URL"
exp=$(date -u -d '+3 hours' +%Y-%m-%dT%H:%MZ)
sas() { az storage blob generate-sas --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c "$C" -n "$1" --permissions r --expiry "$exp" --https-only --full-uri -o tsv; }
ISO_SAS=$(sas SQL2022-Dev.iso); SSRS_SAS=$(sas SQLServerReportingServices.exe); echo "::add-mask::$ISO_SAS"; echo "::add-mask::$SSRS_SAS"
step=vmstart
az vm start -g "$RG" -n "$DC" -o none 2>/dev/null || echo "DC not up yet (preload)" &
az vm start -g "$RG" -n "$VM" -o none &
wait
run() { step=$1; echo "== $1"; local out
  out=$(az vm run-command invoke -g "$RG" -n "$VM" --command-id RunPowerShellScript --scripts @scripts/scom/sql-install.ps1 \
    --parameters "stage=$1" "p=$ESTHER_SCOM_SVC_PASSWORD" "iso=$(printf %s "$ISO_SAS" | base64 -w0)" "ssrs=$(printf %s "$SSRS_SAS" | base64 -w0)" -o json | jq -r '.value[]?.message' | grep -v '^\s*$' || true)
  echo "$out" | tail -20
  if grep -qE 'STAGE_FAIL|Exception|is not recognized' <<<"$out"; then echo "PHASE3_FAILED at $1"; exit 1; fi; }
step=dnsfix
# Known-fix: a freshly promoted DC has no DNS forwarder, so the VM cannot resolve external names (blob storage).
# Force the DC forwarder to Azure DNS (168.63.129.16, reachable from every Azure vnet), then run ONE in-VM
# diagnostic+retry loop (separate run-command invocations race and fail with Conflict).
FQDN="$MEDIA_ACCOUNT.blob.core.windows.net"
az vm run-command invoke -g "$RG" -n "$DC" --command-id RunPowerShellScript --scripts "\$f = @(Get-DnsServerForwarder).IPAddress.IPAddressToString; if (\$f -notcontains '168.63.129.16') { Set-DnsServerForwarder -IPAddress 168.63.129.16 -Confirm:\$false | Out-Null; 'FWD_SET (was: ' + (\$f -join ',' ) + ')' } else { 'FWD_OK ' + (\$f -join ',') }; Clear-DnsServerCache -Confirm:\$false" --query "value[0].message" -o tsv || true
cat > /tmp/dnsprobe.ps1 <<PS1
Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { \$_.ServerAddresses } | ForEach-Object { 'DNS ' + \$_.InterfaceAlias + ' -> ' + (\$_.ServerAddresses -join ',') }
ipconfig /flushdns | Out-Null
\$ok = \$false
for (\$i = 1; \$i -le 12; \$i++) {
  \$r = Resolve-DnsName $FQDN -ErrorAction SilentlyContinue | Select-Object -First 1
  if (\$r) { 'RESOLVED try ' + \$i + ': ' + \$r.NameHost; \$ok = \$true; break }
  'probe ' + \$i + ' fail'; Start-Sleep -Seconds 10
}
if (-not \$ok) { 'STAGE_FAIL dnsfix - cannot resolve $FQDN' }
PS1
out=$(az vm run-command invoke -g "$RG" -n "$VM" --command-id RunPowerShellScript --scripts @/tmp/dnsprobe.ps1 --query "value[0].message" -o tsv 2>&1 || true)
echo "$out" | grep -v '^\s*$'
grep -q 'RESOLVED' <<<"$out" || { echo "PHASE3_FAILED at dnsfix - VM still cannot resolve $FQDN"; exit 1; }
for s in ${STAGES:-download install ssrs ssrsconfig verify cleanup}; do run "$s"; done
echo PHASE3_OK
