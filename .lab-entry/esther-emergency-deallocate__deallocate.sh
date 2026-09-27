#!/usr/bin/env bash
set -euo pipefail
ENTRY_FAILED=0
echo "== Deallocate and verify =="
set -Eeuo pipefail
az vm deallocate -g rg-learning-monitoring -n esther-adaxes-01 --only-show-errors
power="$(az vm get-instance-view -g rg-learning-monitoring -n esther-adaxes-01 --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus | [0]" -o tsv)"
[[ "$power" == 'VM deallocated' ]]
printf 'POWER_STATE=%s\n' "$power"
az resource list -g rg-learning-monitoring --query '[].{name:name,type:type}' -o table
