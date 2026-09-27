#!/usr/bin/env bash
set -euo pipefail
export INPUT_URL="${INPUT_URL}"
export INPUT_NAME="${INPUT_NAME}"
export INPUT_MEDIA_ACCOUNT="${INPUT_MEDIA_ACCOUNT}"
ENTRY_FAILED=0
echo "== Stage =="
export URL="${INPUT_URL}"
export NAME="${INPUT_NAME}"
export ACC="${INPUT_MEDIA_ACCOUNT}"
set -euo pipefail
case "$URL" in https://go.microsoft.com/*|https://download.microsoft.com/*) ;; *) echo "only Microsoft URLs"; exit 1;; esac
KEY=$(az storage account keys list -g rg-learning-monitoring -n "$ACC" --query '[0].value' -o tsv); echo "::add-mask::$KEY"
curl -fsSL "$URL" -o "/tmp/$NAME"; ls -l "/tmp/$NAME"; sha256sum "/tmp/$NAME"
az storage blob upload --account-name "$ACC" --account-key "$KEY" -c media -n "$NAME" -f "/tmp/$NAME" --overwrite -o none
az storage blob list --account-name "$ACC" --account-key "$KEY" -c media --query '[].{n:name,size:properties.contentLength}' -o table
