#!/usr/bin/env bash
set -euo pipefail
ENTRY_FAILED=0
echo "== Inspect disk and VM power =="
set -Eeuo pipefail
az disk show -g rg-learning-monitoring -n esther-adaxes-01-osdisk --query '{diskSizeGb:diskSizeGb,sku:sku.name,diskState:diskState,osType:osType,hyperVGeneration:hyperVGeneration,location:location}' -o json
az vm get-instance-view -g rg-learning-monitoring -n esther-adaxes-01 --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus | [0]" -o tsv | sed 's/^/POWER_STATE=/'
