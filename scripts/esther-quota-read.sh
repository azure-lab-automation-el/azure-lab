#!/usr/bin/env bash
# Read-only: vCPU quota ahead of build-SKU (b4as/b8as) policy edit. No changes.
set -uo pipefail
for L in israelcentral swedencentral; do
  echo "== אזור: $L =="
  az vm list-usage --location "$L" -o json 2>/tmp/usage-err-$L.txt > /tmp/usage-$L.json || { echo "שגיאה: $(head -3 /tmp/usage-err-$L.txt)"; continue; }
  jq -r '.[] | select(.name.value=="standardBSFamily" or .name.value=="cores") | .name.value + " (" + .name.localizedValue + "): בשימוש " + (.currentValue|tostring) + " מתוך " + (.limit|tostring)' /tmp/usage-$L.json
done
echo "== דרישה צפויה בשיא הבנייה =="
echo "b4as_v2 = 4 vCPU ל-VM, b8as_v2 = 8 vCPU ל-VM (משפחת BS)"
