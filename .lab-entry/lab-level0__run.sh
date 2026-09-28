#!/usr/bin/env bash
# Billable-only teardown. User decision 2026-09-28 20:19: keep everything free (RG, VNets/NSGs, NICs,
# policies, SP role assignments, esther-lesson-speech-f0). Delete ONLY billable: managed disks,
# snapshots, public IPs, billable storage accounts (except esther-lesson-speech-f0).
# NEVER touch: SWAs (estherdax/megila/esther-cloud-admin), rg-esther-portal, policies, the RG itself.
set -Eeuo pipefail
MODE=${MODE:-inventory}; RG=rg-learning-monitoring
echo "== LEVEL0 $MODE billable-only $(date -u +%FT%TZ) =="
echo "== PRECONDITION GATES =="
for a in scom-tree.7z scom-dbs.7z SQLSysClrTypes.msi ReportViewer.msi 7zr.exe SQLServerReportingServices.exe; do
  gh release view scom-prereqs --json assets --jq '.assets[].name' | grep -qx "$a" || { echo "GATE FAIL: missing $a"; exit 1; }
done
for d in entra-lab-allowed-types-v1 entra-lab-vm-images-v1 entra-lab-disk-shape-v1; do
  [ -s "policy/$d.def.json" ] || { echo "GATE FAIL: policy/$d.def.json"; exit 1; }
done
ls policy/*.assign.json >/dev/null || { echo "GATE FAIL: assigns"; exit 1; }
echo "GATES_OK"
echo "== INVENTORY $(date -u +%FT%TZ) =="
echo "-- RGs --"; az group list --query '[].name' -o tsv
echo "-- RG $RG resources --"; az resource list -g "$RG" --query '[].{name:name,type:type}' -o table || echo "RG GONE"
for g in $(az group list --query '[].name' -o tsv); do
  echo "-- disks in $g --"; az disk list -g "$g" --query '[].{n:name,size:diskSizeGb,state:diskState}' -o table
  echo "-- snapshots in $g --"; az snapshot list -g "$g" --query '[].{n:name,size:diskSizeGb}' -o table
done
echo "-- public IPs (all) --"; az network public-ip list --query '[].{n:name,g:resourceGroup,sku:sku.name,alloc:publicIPAllocationMethod}' -o table
echo "-- storage (all) --"; az storage account list --query '[].{n:name,g:resourceGroup,sku:sku.name}' -o table
echo "-- SWAs (all) --"; az staticwebapp list --query '[].{n:name,g:resourceGroup,sku:sku.name}' -o table 2>/dev/null || echo "swa list failed"
if [ "$MODE" = delete ]; then
  echo "== DELETE billable-only $(date -u +%FT%TZ) =="
  for g in $(az group list --query '[].name' -o tsv); do
    for d in $(az disk list -g "$g" --query '[].id' -o tsv); do echo "del disk $d"; az disk delete --ids "$d" --yes -o none && echo OK || echo "FAILED $d"; done
    for s in $(az snapshot list -g "$g" --query '[].id' -o tsv); do echo "del snapshot $s"; az snapshot delete --ids "$s" -o none && echo OK || echo "FAILED $s"; done
  done
  for p in $(az network public-ip list --query "[?contains(name,'esther')].id" -o tsv); do echo "del pip $p"; az network public-ip delete --ids "$p" -o none && echo OK || echo "FAILED $p"; done
  for sa in $(az storage account list --query "[?resourceGroup=='$RG' && name!='esther-lesson-speech-f0'].id" -o tsv); do echo "del storage $sa"; az storage account delete --ids "$sa" --yes -o none && echo OK || echo "FAILED $sa"; done
  # estherlabmedia outside RG (if any) - billable, rebuildable from release
  for sa in $(az storage account list --query "[?contains(name,'estherlabmedia') && resourceGroup!='$RG'].id" -o tsv); do echo "del storage $sa"; az storage account delete --ids "$sa" --yes -o none && echo OK || echo "FAILED $sa"; done
  echo "== POST-VERIFY $(date -u +%FT%TZ) =="
  for g in $(az group list --query '[].name' -o tsv); do az disk list -g "$g" --query '[].name' -o tsv; az snapshot list -g "$g" --query '[].name' -o tsv; done
  az storage account list --query '[].{n:name,g:resourceGroup}' -o table
  az network public-ip list --query '[].name' -o tsv
  echo "DELETE_DONE"
fi
