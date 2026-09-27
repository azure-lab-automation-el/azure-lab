#!/usr/bin/env bash
set -euo pipefail
ENTRY_FAILED=0
echo "== step =="
T=$(az account get-access-token --resource-type ms-graph --query accessToken -o tsv 2>/dev/null) || { echo "no login"; exit 0; }
echo "::add-mask::$T"; echo "$T" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | jq -c '{app:.app_displayname,roles}' || echo "$T" | cut -d. -f2 | tr '_-' '/+' | { read p; echo "$p==" | base64 -d 2>/dev/null; } | jq -c '{app:.app_displayname,roles}'
