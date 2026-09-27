#!/usr/bin/env bash
# mivtza-eser monitor: poll table rows, print Hebrew per-stage status with elapsed, exit on ready/failed.
set -Eeuo pipefail
: "${AZURE_SUBSCRIPTION_ID:?}" "${MEDIA_ACCOUNT:?}"
RG=rg-learning-monitoring; T0=$(date +%s); LIMIT=$(( ${MON_TIMEOUT_MIN:-60} * 60 ))
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
KEY=$(az storage account keys list -g "$RG" -n "$MEDIA_ACCOUNT" --query '[0].value' -o tsv)
row() { az storage entity show --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" --table-name labstate --partition-key "$1" --row-key "$2" --query data -o tsv 2>/dev/null || true; }
declare -A last
while :; do
  for m in dc vm; do
    j=$(row "$m" state); [ -z "$j" ] && s="ממתין" || s=$(jq -r '"\(.phase)"' <<<"$j" 2>/dev/null || echo "?")
    if [ "${last[$m]:-}" != "$s" ]; then
      e=$(( ($(date +%s) - T0) / 60 )); printf '%s: %s (%d דק׳)\n' "$m" "$s" "$e"; last[$m]=$s
      if [ "$s" = failed ]; then jq -r .error <<<"$j"; echo "MONITOR_FAIL $m"; exit 1; fi
    fi
  done
  if [ "${last[dc]:-}" = ready ] && [ "${last[vm]:-}" = ready ]; then echo "MONITOR_READY total_min=$(( ($(date +%s) - T0) / 60 ))"; exit 0; fi
  if [ $(( $(date +%s) - T0 )) -gt $LIMIT ]; then echo "MONITOR_TIMEOUT"; exit 1; fi
  sleep 20
done
