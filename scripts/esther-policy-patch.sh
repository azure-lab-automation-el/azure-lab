#!/usr/bin/env bash
set -Eeuo pipefail

: "${AZURE_SUBSCRIPTION_ID:?AZURE_SUBSCRIPTION_ID is required}"
RG='rg-learning-monitoring'
SCOPE="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RG}"
API='2025-03-01'
SKU_ASSIGNMENT='lab-vm-skus'
IMAGE_ASSIGNMENT='lab-vm-images'
TARGET_SKU='standard_b2als_v2'
TARGET_PUBLISHER='MicrosoftWindowsServer'
TARGET_OFFER='WindowsServer'

get_assignment() {
  local name="$1"
  az rest --only-show-errors --method get \
    --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyAssignments/${name}?api-version=${API}"
}

put_assignment() {
  local name="$1" body="$2"
  az rest --only-show-errors --method put \
    --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyAssignments/${name}?api-version=${API}" \
    --headers 'Content-Type=application/json' \
    --body "@${body}" >/dev/null
}

umask 077
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

get_assignment "$SKU_ASSIGNMENT" >"$workdir/sku-before.json"
get_assignment "$IMAGE_ASSIGNMENT" >"$workdir/image-before.json"

# Refuse to touch a look-alike resource, changed scope, changed definition, or malformed assignment.
for pair in \
  "$SKU_ASSIGNMENT:$workdir/sku-before.json" \
  "$IMAGE_ASSIGNMENT:$workdir/image-before.json"
do
  name="${pair%%:*}"; file="${pair#*:}"
  jq -e --arg name "$name" --arg scope "${SCOPE}/providers/Microsoft.Authorization/policyAssignments/${name}" '
    (.name == $name) and
    ((.id | ascii_downcase) == ($scope | ascii_downcase)) and
    (.properties.policyDefinitionId | type == "string" and length > 0) and
    (.properties.parameters | type == "object")
  ' "$file" >/dev/null
 done

sku_key="$(jq -r '.properties.parameters | keys[] | select(ascii_downcase | contains("sku"))' "$workdir/sku-before.json")"
[[ -n "$sku_key" && "$(wc -l <<<"$sku_key")" -eq 1 ]]

# Azure Policy assignments do not support parameter PATCH. Build a full PUT body from
# the live object, changing only the exact SKU value while preserving every writable field.
if jq -e --arg key "$sku_key" --arg target "$TARGET_SKU" '
  .properties.parameters[$key].value | map(ascii_downcase) | index($target) != null
' "$workdir/sku-before.json" >/dev/null; then
  sku_write_performed=false
else
  jq --arg key "$sku_key" --arg target "$TARGET_SKU" '
    .properties.parameters[$key].value |=
      ((map(ascii_downcase) + [$target]) | unique)
    | ({properties:.properties}
       + (if .identity then {identity:.identity} else {} end)
       + (if .location then {location:.location} else {} end))
  ' "$workdir/sku-before.json" >"$workdir/sku-put.json"
  put_assignment "$SKU_ASSIGNMENT" "$workdir/sku-put.json"
  sku_write_performed=true
fi

# The selected official image resolves to the existing MicrosoftWindowsServer / WindowsServer
# allowlist. Do not widen it. Fail closed if those exact values are absent.
publisher_key="$(jq -r '.properties.parameters | keys[] | select(ascii_downcase | contains("publisher"))' "$workdir/image-before.json")"
offer_key="$(jq -r '.properties.parameters | keys[] | select(ascii_downcase | contains("offer"))' "$workdir/image-before.json")"
[[ -n "$publisher_key" && "$(wc -l <<<"$publisher_key")" -eq 1 ]]
[[ -n "$offer_key" && "$(wc -l <<<"$offer_key")" -eq 1 ]]
jq -e --arg pkey "$publisher_key" --arg okey "$offer_key" --arg publisher "$TARGET_PUBLISHER" --arg offer "$TARGET_OFFER" '
  (.properties.parameters[$pkey].value | index($publisher) != null) and
  (.properties.parameters[$okey].value | index($offer) != null)
' "$workdir/image-before.json" >/dev/null

get_assignment "$SKU_ASSIGNMENT" >"$workdir/sku-after.json"
get_assignment "$IMAGE_ASSIGNMENT" >"$workdir/image-after.json"

# Full-object preservation check: only the SKU parameter object may differ.
jq -S --arg key "$sku_key" 'del(.properties.parameters[$key], .properties.metadata.systemData, .systemData, .etag)' "$workdir/sku-before.json" >"$workdir/sku-before-stable.json"
jq -S --arg key "$sku_key" 'del(.properties.parameters[$key], .properties.metadata.systemData, .systemData, .etag)' "$workdir/sku-after.json" >"$workdir/sku-after-stable.json"
cmp "$workdir/sku-before-stable.json" "$workdir/sku-after-stable.json"

jq -e --arg key "$sku_key" --arg target "$TARGET_SKU" '
  .properties.parameters[$key].value | map(ascii_downcase) | index($target) != null
' "$workdir/sku-after.json" >/dev/null

# Image assignment must be byte-for-byte semantically unchanged apart from service systemData.
jq -S 'del(.properties.metadata.systemData, .systemData, .etag)' "$workdir/image-before.json" >"$workdir/image-before-stable.json"
jq -S 'del(.properties.metadata.systemData, .systemData, .etag)' "$workdir/image-after.json" >"$workdir/image-after-stable.json"
cmp "$workdir/image-before-stable.json" "$workdir/image-after-stable.json"

jq -n --arg sku "$TARGET_SKU" --arg publisher "$TARGET_PUBLISHER" --arg offer "$TARGET_OFFER" --argjson sku_write_performed "$sku_write_performed" \
  '{verified:true,sku:$sku,sku_write_performed:$sku_write_performed,image:{publisher:$publisher,offer:$offer},image_assignment_changed:false}'
