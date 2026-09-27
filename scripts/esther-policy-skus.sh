#!/usr/bin/env bash
# Add B4as_v2 + B8as_v2 to the lab-vm-skus allowlist (build-time bump, resize-down after).
# User-approved edit (approved 12:09:57, reply to the SKU policy question). Nothing else changes.
set -Eeuo pipefail

: "${AZURE_SUBSCRIPTION_ID:?AZURE_SUBSCRIPTION_ID is required}"
RG='rg-learning-monitoring'
SCOPE="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RG}"
API='2025-03-01'
ASSIGNMENT='lab-vm-skus'

get_assignment() {
  az rest --only-show-errors --method get \
    --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyAssignments/$1?api-version=${API}"
}
put_assignment() {
  az rest --only-show-errors --method put \
    --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyAssignments/$1?api-version=${API}" \
    --headers 'Content-Type=application/json' \
    --body "@${2}" >/dev/null
}

umask 077
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

get_assignment "$ASSIGNMENT" >"$workdir/before.json"

# Refuse a look-alike resource, changed scope, or malformed assignment.
jq -e --arg name "$ASSIGNMENT" --arg scope "${SCOPE}/providers/Microsoft.Authorization/policyAssignments/${ASSIGNMENT}" '
  (.name == $name) and
  ((.id | ascii_downcase) == ($scope | ascii_downcase)) and
  (.properties.policyDefinitionId | type == "string" and length > 0) and
  (.properties.parameters | type == "object")
' "$workdir/before.json" >/dev/null

sku_key="$(jq -r '.properties.parameters | keys[] | select(ascii_downcase | contains("sku"))' "$workdir/before.json")"
[[ -n "$sku_key" && "$(wc -l <<<"$sku_key")" -eq 1 ]]

# Existing allowlist must be exactly the known lab set (case-insensitive); fail closed otherwise.
jq -e --arg key "$sku_key" '
  (.properties.parameters[$key].value | map(ascii_downcase) | sort)
  == ["standard_b1s","standard_b2als_v2","standard_b2as_v2","standard_b2ats_v2","standard_b2pts_v2"]
' "$workdir/before.json" >/dev/null

# Derive the new values from the existing B2as_v2 entry so casing convention is preserved exactly.
b2="$(jq -r --arg key "$sku_key" '.properties.parameters[$key].value[] | select(ascii_downcase == "standard_b2as_v2")' "$workdir/before.json")"
[[ -n "$b2" ]]
add4="${b2/b2as/b4as}"; add8="${b2/b2as/b8as}"
[[ "$add4" != "$b2" && "$add8" != "$b2" ]]

# Full PUT (no parameter PATCH support), appending only the two approved values.
jq --arg key "$sku_key" --arg a4 "$add4" --arg a8 "$add8" '
  .properties.parameters[$key].value |= ((. + [$a4, $a8]) | unique)
  | ({properties:.properties}
     + (if .identity then {identity:.identity} else {} end)
     + (if .location then {location:.location} else {} end))
' "$workdir/before.json" >"$workdir/put.json"
put_assignment "$ASSIGNMENT" "$workdir/put.json"

get_assignment "$ASSIGNMENT" >"$workdir/after.json"

# Only the SKU array may differ.
jq -S --arg key "$sku_key" 'del(.properties.parameters[$key], .properties.metadata.systemData, .properties.metadata.updatedBy, .properties.metadata.updatedOn, .systemData, .etag)' "$workdir/before.json" >"$workdir/before-stable.json"
jq -S --arg key "$sku_key" 'del(.properties.parameters[$key], .properties.metadata.systemData, .properties.metadata.updatedBy, .properties.metadata.updatedOn, .systemData, .etag)' "$workdir/after.json"  >"$workdir/after-stable.json"
cmp "$workdir/before-stable.json" "$workdir/after-stable.json"

jq -e --arg key "$sku_key" --arg a4 "$add4" --arg a8 "$add8" '
  (.properties.parameters[$key].value | index($a4) != null) and
  (.properties.parameters[$key].value | index($a8) != null) and
  (.properties.parameters[$key].value | length == 7)
' "$workdir/after.json" >/dev/null

jq -n --arg a4 "$add4" --arg a8 "$add8" \
  '{verified:true,added:[$a4,$a8],other_fields_changed:false}'
