#!/usr/bin/env bash
set -euo pipefail
ENTRY_FAILED=0
echo "== Schema-only disk inspection =="
set -Eeuo pipefail
az disk show -g rg-learning-monitoring -n esther-adaxes-01-osdisk -o json >/tmp/disk.json
jq -r '"DISK_KEYS=" + (keys|sort|join(",")), "SIZE_KEYS=" + ([keys[]|select(ascii_downcase|contains("size"))]|sort|join(","))' /tmp/disk.json
jq -r 'to_entries[] | select(.key|ascii_downcase|contains("size")) | "SIZE_FIELD " + .key + "=" + (.value|tostring)' /tmp/disk.json
az vm get-instance-view -g rg-learning-monitoring -n esther-adaxes-01 --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus | [0]" -o tsv | sed 's/^/POWER_STATE=/'
