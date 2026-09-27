#!/usr/bin/env bash
# Path A (mivtza-eser, needs his explicit word): allow a 128 GB Premium_LRS OS disk alongside the 64 GB P6 rule,
# so the SQL marketplace image (sqldev-gen2, ~128 GB OS disk) can provision. Nothing else changes.
# Fail-closed: refuses to touch a look-alike assignment or an unknown existing set.
set -Eeuo pipefail
: "${AZURE_SUBSCRIPTION_ID:?}"
RG='rg-learning-monitoring'
SCOPE="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RG}"
API='2025-03-01'
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
umask 077; workdir="$(mktemp -d)"; trap 'rm -rf "$workdir"' EXIT
# find the disk policy assignment by display name; fail closed if not exactly one
az rest --only-show-errors --method get \
  --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyAssignments?api-version=${API}" \
  > "$workdir/all.json"
ASSIGNMENT=$(jq -r '[.value[] | select(.properties.displayName // "" | test("disk"; "i")) | .name] | unique | if length == 1 then .[0] else "" end' "$workdir/all.json")
[ -n "$ASSIGNMENT" ] || { echo "FAIL: expected exactly one disk policy assignment at RG scope"; jq -r '.value[].properties.displayName' "$workdir/all.json"; exit 1; }
echo "assignment: $ASSIGNMENT"
az rest --only-show-errors --method get \
  --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyAssignments/${ASSIGNMENT}?api-version=${API}" \
  > "$workdir/before.json"
jq -e --arg name "$ASSIGNMENT" '.name == $name and (.properties.parameters | type == "object")' "$workdir/before.json" >/dev/null
jq -r '.properties.parameters | keys[]' "$workdir/before.json"
jq '.properties.parameters | map_values(.value)' "$workdir/before.json"
# append 128 to every size-like numeric array parameter; append nothing else
jq '(.properties.parameters | to_entries
      | map(select(.value.value | type == "array" and all(.[]; type == "number")))
      | map(.key)) as $ks
    | if ($ks | length) == 0 then error("no numeric array parameter found") else . end
    | reduce $ks[] as $k (. ; .properties.parameters[$k].value |= ((. + [128]) | unique))
    | {properties:.properties} + (if .identity then {identity:.identity} else {} end) + (if .location then {location:.location} else {} end)' \
    "$workdir/before.json" > "$workdir/after.json"
az rest --only-show-errors --method put \
  --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyAssignments/${ASSIGNMENT}?api-version=${API}" \
  --headers 'Content-Type=application/json' --body "@$workdir/after.json" >/dev/null
az rest --only-show-errors --method get \
  --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyAssignments/${ASSIGNMENT}?api-version=${API}" \
  | jq '.properties.parameters | map_values(.value)'
echo POLICY_DISKS_128_OK
