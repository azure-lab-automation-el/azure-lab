#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
ENTRY_FAILED=0
echo "== Inventory + cost (read-only) =="
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
set -euo pipefail
echo '## rg-learning-monitoring resources'
az resource list -g rg-learning-monitoring --query '[].{name:name,type:type,location:location}' -o table
echo '## VM power states'
az vm list -g rg-learning-monitoring -d --query '[].{vm:name,size:hardwareProfile.vmSize,power:powerState}' -o table || true
echo '## Disks'
az disk list -g rg-learning-monitoring --query '[].{disk:name,sku:sku.name,gb:diskSizeGb}' -o table || true
echo '## 30-day cost (Cost Management, read-only)'
bash scripts/05-read-azure-costs.sh | tail -30 || true
