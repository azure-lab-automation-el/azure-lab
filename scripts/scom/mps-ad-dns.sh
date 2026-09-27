#!/usr/bin/env bash
# AD DS + DNS management packs for the lab DC. Runner downloads from download.microsoft.com only, extracts the .mp/.mpb files,
# stages them in lab storage, and the SCOM server imports them. Rollback: Remove-SCOMManagementPack for the imported names (printed).
# Sourced from esther-scom-phase5.sh (needs RG, VM, MEDIA_ACCOUNT, KEY, exp).
set +e
sudo apt-get install -y msitools >/dev/null 2>&1
mkdir -p /tmp/mp && cd /tmp/mp
for id in 54525 54524; do
  u=$(curl -sL "https://www.microsoft.com/en-us/download/details.aspx?id=$id" | grep -oE 'https://download\.microsoft\.com/[^"]+\.msi' | sort -u | grep -viE '[ .](ENU|CHS|CHT|DEU|ESN|FRA|ITA|JPN|KOR|PTB|RUS|CSY|HUN|NLD|PLK|PTG|SVE|TRK)\.msi$' | head -1)
  echo "mp id=$id url=$u"; [[ $u == https://download.microsoft.com/* ]] || { echo "STAGE_FAIL mps no official url for $id"; exit 1; }
  curl -sfL -o "$id.msi" "${u// /%20}" || echo "download failed $id"; ls -l "$id.msi"; msiextract -C "x$id" "$id.msi" >/dev/null
done
find /tmp/mp -iname '*.mp' -o -iname '*.mpb' | grep -viE '2008|2012' | tee /tmp/mp/list.txt
[ -s /tmp/mp/list.txt ] || { echo "STAGE_FAIL mps nothing extracted"; exit 1; }
tar -C / -czf /tmp/mp/mps.tgz $(sed 's#^/##' /tmp/mp/list.txt); zip -j -q /tmp/mp/mps.zip $(cat /tmp/mp/list.txt)
az storage blob upload --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c media -n mps.zip -f /tmp/mp/mps.zip --overwrite -o none
R=$(az storage blob generate-sas --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c media -n mps.zip --permissions r --expiry "$exp" --https-only --full-uri -o tsv); echo "::add-mask::$R"
cd - >/dev/null
out=$(az vm run-command invoke -g "$RG" -n "$VM" --command-id RunPowerShellScript --scripts "\$ErrorActionPreference='Continue'; Import-Module OperationsManager; New-SCOMManagementGroupConnection -ComputerName localhost; \$d='C:\scomlab\mps'; Remove-Item \$d -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force \$d | Out-Null; Invoke-WebRequest '$R' -OutFile C:\scomlab\mps.zip -UseBasicParsing; Expand-Archive C:\scomlab\mps.zip \$d -Force; \$f = Get-ChildItem \$d -File | % FullName; 'files=' + \$f.Count; \$before = @(Get-SCOMManagementPack | % Name); Import-SCOMManagementPack -Fullname \$f -ErrorAction Continue; \$new = @(Get-SCOMManagementPack | % Name | ? { \$before -notcontains \$_ }); 'IMPORTED ' + (\$new -join ','); 'MP_COUNT_NEW=' + \$new.Count; Get-SCOMManagementPack | ? { \$_.Name -match 'AD|DNS' } | % { 'MP ' + \$_.Name + ' ' + \$_.Version }; 'MPS_DONE'" -o json | jq -r '.value[]?.message' | grep -v '^\s*$')
echo "$out" | tail -40
az storage blob delete --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c media -n mps.zip -o none
grep -q MPS_DONE <<<"$out" && grep -qE 'MP_COUNT_NEW=[1-9]|MP Microsoft.Windows.Server.AD' <<<"$out" || { echo "STAGE_FAIL mps import"; exit 1; }
set -e
