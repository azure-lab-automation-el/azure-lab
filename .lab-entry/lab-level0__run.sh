#!/usr/bin/env bash
# Level-0 lab teardown. MODE=inventory (read-only) | delete (requires precondition gates).
# SCOPE=full (delete RG last) | spare-lessons (delete lab resources individually, keep esther-lesson-speech-f0 + linux remnants? NO: spare keeps lesson-speech only, linux remnants still die with... they are in the RG - spare mode deletes everything EXCEPT esther-lesson-speech-f0, individually, and KEEPS the RG).
set -Eeuo pipefail
MODE=${MODE:-inventory}; SCOPE=${SCOPE:-spare-lessons}; RG=rg-learning-monitoring
echo "== LEVEL0 $MODE scope=$SCOPE $(date -u +%FT%TZ) =="
if [ "$MODE" = inventory ] || [ "$MODE" = delete ]; then
  echo "== PRECONDITION GATES =="
  gh release view scom-prereqs --json assets --jq '.assets[].name' | sort || { echo "GATE FAIL: release"; exit 1; }
  for a in scom-tree.7z scom-dbs.7z SQLSysClrTypes.msi ReportViewer.msi 7zr.exe SQLServerReportingServices.exe; do
    gh release view scom-prereqs --json assets --jq '.assets[].name' | grep -qx "$a" || { echo "GATE FAIL: missing $a"; exit 1; }
  done
  for d in entra-lab-allowed-types-v1 entra-lab-vm-images-v1 entra-lab-disk-shape-v1; do
    [ -s "policy/$d.def.json" ] || { echo "GATE FAIL: policy/$d.def.json"; exit 1; }
  done
  ls policy/*.assign.json >/dev/null || { echo "GATE FAIL: assigns"; exit 1; }
  echo "GATES_OK"
  echo "== INVENTORY $(date -u +%FT%TZ) =="
  az resource list -g "$RG" --query '[].{name:name,type:type}' -o table || echo "RG GONE"
  echo "-- disks (all) --"; az disk list --query '[].{n:name,g:resourceGroup,size:diskSizeGb}' -o table
  echo "-- storage (all) --"; az storage account list --query '[].{n:name,g:resourceGroup}' -o table
  echo "-- policy defs (lab) --"; az policy definition list --query "[?contains(name,'lab')].name" -o tsv
  echo "-- policy assigns (RG) --"; az policy assignment list --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG" --query '[].name' -o tsv 2>/dev/null || echo "RG scope gone"
fi
if [ "$MODE" = delete ]; then
  echo "== DELETE $(date -u +%FT%TZ) =="
  if [ "$SCOPE" = full ]; then
    # everything else first, RG last (RG delete severs SP perms mid-run)
    for sa in $(az storage account list -g "$RG" --query '[].name' -o tsv); do echo "del storage $sa"; az storage account delete -g "$RG" -n "$sa" --yes -o none; done
    echo "del RG $RG (last call; SP perms die with it)"; az group delete -n "$RG" --yes --no-wait
    echo "DELETE_DISPATCHED - post-RG verification impossible from SP; confirm externally"
  else
    # spare-lessons: delete every RG resource except esther-lesson-speech-f0, keep RG
    for id in $(az resource list -g "$RG" --query "[?name!='esther-lesson-speech-f0'].id" -o tsv); do
      echo "del $id"; az resource delete --ids "$id" --verbose -o none 2>&1 | tail -1 || echo "FAILED $id"
    done
    # stray disks/storage outside RG
    for d in $(az disk list --query "[?resourceGroup!='$RG'].id" -o tsv); do echo "del disk $d"; az disk delete --ids "$d" --yes -o none || echo "FAILED $d"; done
    echo "== POST-VERIFY =="
    az resource list -g "$RG" --query '[].name' -o tsv
    az disk list --query '[].name' -o tsv
    echo "DELETE_DONE"
  fi
fi
