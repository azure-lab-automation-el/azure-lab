#!/usr/bin/env bash
# שלב 1: גיבוי — snapshot לכל 3 דיסקי מערכת ההפעלה + וידוא תקינות. לא הורס כלום.
set -euo pipefail
RG=rg-learning-monitoring
ok=0
for spec in "esther-dc-01-osdisk|mig-dc|israelcentral" "esther-adaxes-01-osdisk|mig-adaxes|israelcentral" "esther-linux-01-osdisk|mig-linux|swedencentral"; do
  d=${spec%%|*}; rest=${spec#*|}; s=${rest%%|*}; loc=${rest##*|}
  if az snapshot show -g $RG -n $s -o none 2>/dev/null; then echo "כבר קיים: $s"; else
    az snapshot create -g $RG -n $s -l $loc --source "$d" --only-show-errors -o none && echo "נוצר snapshot: $s <- $d"
  fi
  st=$(az snapshot show -g $RG -n $s --query "{ps:provisioningState,size:diskSizeGb}" -o json)
  echo "$s $st"
  ps=$(python3 -c 'import sys,json;print(json.load(sys.stdin)["ps"])' <<<"$st")
  [ "$ps" = "Succeeded" ] && ok=$((ok+1))
done
[ $ok -eq 3 ] && echo "✅ 3/3 snapshots תקינים — אפשר למחוק מכונות" || { echo "❌ רק $ok/3 תקינים — עוצר"; exit 1; }
