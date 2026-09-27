#!/usr/bin/env bash
# Stage install media (SQL 2022 Dev ISO, SSRS installer, SCOM 2025 zip) into the lab media blob.
# Idempotent: skips blobs that already exist. Runs in parallel with the VM build stages.
set -Eeuo pipefail
: "${AZURE_SUBSCRIPTION_ID:?}" "${MEDIA_ACCOUNT:?}"
RG=rg-learning-monitoring; LOC=${LAB_LOCATION:-israelcentral}; C=media
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
if ! az storage account show -g "$RG" -n "$MEDIA_ACCOUNT" -o none 2>/dev/null; then
  az storage account create -g "$RG" -n "$MEDIA_ACCOUNT" -l "$LOC" --sku Standard_LRS --kind StorageV2 --access-tier Hot \
    --allow-blob-public-access false --min-tls-version TLS1_2 --https-only true -o none
fi
KEY=$(az storage account keys list -g "$RG" -n "$MEDIA_ACCOUNT" --query '[0].value' -o tsv); echo "::add-mask::$KEY"
az storage container create --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -n "$C" -o none
stage() { local name=$1 url=$2
  if [ "$(az storage blob exists --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c "$C" -n "$name" --query exists -o tsv)" != true ]; then
    curl -fsSL "$url" -o "/tmp/$name"
    az storage blob upload --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c "$C" -n "$name" -f "/tmp/$name" --overwrite -o none
    rm -f "/tmp/$name"
  fi; echo "staged $name"; }
stage SQL2022-Dev.iso 'https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLServer2022-x64-ENU-Dev.iso' &
stage SQLServerReportingServices.exe 'https://download.microsoft.com/download/8/3/2/832616ff-af64-42b5-a0b1-5eb07f71dec9/SQLServerReportingServices.exe' &
stage SCOM_2025.zip 'https://go.microsoft.com/fwlink/?linkid=2292308&clcid=0x409&culture=en-us&country=us' &
wait
az storage blob list --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c "$C" --query '[].{n:name,bytes:properties.contentLength}' -o table
echo MEDIA_OK
