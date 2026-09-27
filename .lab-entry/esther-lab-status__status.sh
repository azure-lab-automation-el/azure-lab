#!/usr/bin/env bash
set -euo pipefail
export RG="${RG}"
export GH_TOKEN="${GH_TOKEN}"
export A="${A}"
ENTRY_FAILED=0
echo "== Lab status =="
set -uo pipefail; R=${GITHUB_REPOSITORY}
echo "== VMs"; az vm list -d -g $RG --query "[].{vm:name,power:powerState,size:hardwareProfile.vmSize,region:location,ip:privateIps}" -o table
echo "== Heartbeat (SCOM server scheduled task -> Table Storage)"
K=$(az storage account keys list -g $RG -n "$A" --query '[0].value' -o tsv 2>/dev/null)
hb=$(az storage entity show --account-name "$A" --account-key "$K" -t heartbeat --partition-key esther --row-key hb -o json 2>/dev/null || true)
if [ -n "$hb" ]; then ts=$(jq -r '.Timestamp // .timestamp // empty' <<<"$hb"); echo "last beat: $ts ($(( ($(date +%s) - $(date -d "$ts" +%s)) / 60 )) min ago)"
  jq -r '.data // . | tostring' <<<"$hb" | head -c 1500; echo; else echo "no heartbeat row"; fi
echo "== Peerings"; for v in $(az network vnet list -g $RG --query "[].name" -o tsv); do az network vnet peering list -g $RG --vnet-name $v --query "[].{vnet:'$v',peering:name,state:peeringState}" -o tsv; done
echo "== Linux NSG rule"; az network nsg rule show -g $RG --nsg-name esther-se-nsg -n allow-scom-22-1270 --query "{rule:name,ports:destinationPortRanges,src:sourceAddressPrefixes}" -o json 2>/dev/null || echo "missing"
echo "== Latest run per lab workflow"
gh api "repos/$R/actions/runs?per_page=100" --jq '.workflow_runs | group_by(.name) | map(max_by(.created_at)) | map(select(.name|test("esther|scom|lesson|jfrog|mega|backup";"i"))) | sort_by(.created_at) | reverse | .[] | "\(.created_at[0:16])  \(.status)/\(.conclusion // "-")  \(.name)  run \(.id)"'
echo LAB_STATUS_OK
