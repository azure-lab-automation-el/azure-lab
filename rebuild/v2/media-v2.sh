#!/usr/bin/env bash
# mivtza-eser media stage: SCOM 2025 tree repacked to 7z + 7zr.exe, pinned + fail-closed.
# Vendor hashes pinned in config/media-sha256.txt. The repacked 7z hash is content-verified
# (Setup.exe + file count), produced once, stored in blob metadata; VMs verify against it via secrets.json.
set -Eeuo pipefail
: "${AZURE_SUBSCRIPTION_ID:?}" "${MEDIA_ACCOUNT:?}"
RG=rg-learning-monitoring; LOC=${LAB_LOCATION:-israelcentral}; C=media
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
pin() { grep "^$1 " config/media-sha256.txt | awk '{print $2}'; }
ZSHA=$(pin SCOM_2025.zip); SSH=$(pin 7zr.exe)
[ -n "$ZSHA" ] && [ -n "$SSH" ] || { echo "FAIL: pins missing in config/media-sha256.txt"; exit 1; }
if ! az storage account show -g "$RG" -n "$MEDIA_ACCOUNT" -o none 2>/dev/null; then
  az storage account create -g "$RG" -n "$MEDIA_ACCOUNT" -l "$LOC" --sku Standard_LRS --kind StorageV2 --access-tier Hot \
    --allow-blob-public-access false --min-tls-version TLS1_2 --https-only true -o none
fi
KEY=$(az storage account keys list -g "$RG" -n "$MEDIA_ACCOUNT" --query '[0].value' -o tsv); echo "::add-mask::$KEY"
az storage container create --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -n "$C" -o none 2>/dev/null || true
have() { az storage blob exists --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c "$C" -n "$1" --query exists -o tsv; }
# 7zr.exe: vendor-pinned
if [ "$(have 7zr.exe)" != true ] || [ "$(az storage blob show --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c "$C" -n 7zr.exe --query 'metadata.sha256' -o tsv)" != "$SSH" ]; then
  curl -fsSL 'https://www.7-zip.org/a/7zr.exe' -o /tmp/7zr.exe
  echo "$SSH  /tmp/7zr.exe" | sha256sum -c - || { echo "FAIL: 7zr.exe vendor hash mismatch"; exit 1; }
  az storage blob upload --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c "$C" -n 7zr.exe -f /tmp/7zr.exe --overwrite --metadata sha256="$SSH" -o none
  rm -f /tmp/7zr.exe; echo "staged 7zr.exe ($SSH)"
else echo "7zr.exe already staged (pin match)"; fi
# SCOM tree 7z: download vendor zip (pinned), repack, content-verify, upload with produced hash in metadata
if [ "$(have scom-tree.7z)" != true ]; then
  command -v 7z >/dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq p7zip-full >/dev/null; }
  curl -fsSL 'https://go.microsoft.com/fwlink/?linkid=2292308&clcid=0x409&culture=en-us&country=us' -o /tmp/SCOM_2025.zip
  echo "$ZSHA  /tmp/SCOM_2025.zip" | sha256sum -c - || { echo "FAIL: SCOM_2025.zip vendor hash mismatch"; exit 1; }
  rm -rf /tmp/scom-tree && mkdir -p /tmp/scom-tree && cd /tmp/scom-tree && unzip -q /tmp/SCOM_2025.zip && rm -f /tmp/SCOM_2025.zip
  [ -f Setup.exe ] || { echo "FAIL: Setup.exe not at zip root"; exit 1; }
  7z a -t7z -mx=5 /tmp/scom-tree.7z . >/dev/null && cd - >/dev/null
  H=$(sha256sum /tmp/scom-tree.7z | awk '{print $1}')
  N=$(7z l /tmp/scom-tree.7z | tail -1 | awk '{print $3}')
  az storage blob upload --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c "$C" -n scom-tree.7z -f /tmp/scom-tree.7z --overwrite --metadata sha256="$H" -o none
  rm -rf /tmp/scom-tree /tmp/scom-tree.7z
  echo "staged scom-tree.7z sha256=$H files=$N"
else echo "scom-tree.7z already staged: $(az storage blob show --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c "$C" -n scom-tree.7z --query 'metadata.sha256' -o tsv)"; fi
echo MEDIA_V2_OK
