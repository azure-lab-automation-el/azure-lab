#!/usr/bin/env bash
# Add MicrosoftSQLServer publisher + sql2022-ws2022 offer to the lab-vm-images allowlist.
# User-approved edit (approved 11:33, reply to the SQL marketplace proposal). Nothing else changes.
set -Eeuo pipefail

: "${AZURE_SUBSCRIPTION_ID:?AZURE_SUBSCRIPTION_ID is required}"
RG='rg-learning-monitoring'
SCOPE="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RG}"
API='2025-03-01'
ASSIGNMENT='lab-vm-images'
ADD_PUBLISHER='MicrosoftSQLServer'
ADD_OFFER='sql2022-ws2022'

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

# Refuse to touch a look-alike resource, changed scope, changed definition, or malformed assignment.
jq -e --arg name "$ASSIGNMENT" --arg scope "${SCOPE}/providers/Microsoft.Authorization/policyAssignments/${ASSIGNMENT}" '
  (.name == $name) and
  ((.id | ascii_downcase) == ($scope | ascii_downcase)) and
  (.properties.policyDefinitionId | type == "string" and length > 0) and
  (.properties.parameters | type == "object")
' "$workdir/before.json" >/dev/null

publisher_key="$(jq -r '.properties.parameters | keys[] | select(ascii_downcase | contains("publisher"))' "$workdir/before.json")"
offer_key="$(jq -r '.properties.parameters | keys[] | select(ascii_downcase | contains("offer"))' "$workdir/before.json")"
[[ -n "$publisher_key" && "$(wc -l <<<"$publisher_key")" -eq 1 ]]
[[ -n "$offer_key" && "$(wc -l <<<"$offer_key")" -eq 1 ]]

# Existing allowlist must still be exactly the known lab set; fail closed otherwise.
jq -e --arg pkey "$publisher_key" --arg okey "$offer_key" '
  (.properties.parameters[$pkey].value | sort == ["Canonical","Debian","MicrosoftWindowsServer"]) and
  (.properties.parameters[$okey].value | sort == ["0001-com-ubuntu-server-jammy","0001-com-ubuntu-server-noble","WindowsServer","debian-12","ubuntu-24_04-lts"])
' "$workdir/before.json" >/dev/null

# Azure Policy assignments do not support parameter PATCH. Full PUT, appending only the two approved values.
jq --arg pkey "$publisher_key" --arg okey "$offer_key" --arg publisher "$ADD_PUBLISHER" --arg offer "$ADD_OFFER" '
  .properties.parameters[$pkey].value |= ((. + [$publisher]) | unique)
  | .properties.parameters[$okey].value |= ((. + [$offer]) | unique)
  | ({properties:.properties}
     + (if .identity then {identity:.identity} else {} end)
     + (if .location then {location:.location} else {} end))
' "$workdir/before.json" >"$workdir/put.json"
put_assignment "$ASSIGNMENT" "$workdir/put.json"

get_assignment "$ASSIGNMENT" >"$workdir/after.json"

# Full-object preservation check: only the two parameter arrays may differ.
jq -S --arg pkey "$publisher_key" --arg okey "$offer_key" 'del(.properties.parameters[$pkey], .properties.parameters[$okey], .properties.metadata.systemData, .properties.metadata.updatedBy, .properties.metadata.updatedOn, .systemData, .etag)' "$workdir/before.json" >"$workdir/before-stable.json"
jq -S --arg pkey "$publisher_key" --arg okey "$offer_key" 'del(.properties.parameters[$pkey], .properties.parameters[$okey], .properties.metadata.systemData, .properties.metadata.updatedBy, .properties.metadata.updatedOn, .systemData, .etag)' "$workdir/after.json"  >"$workdir/after-stable.json"
cmp "$workdir/before-stable.json" "$workdir/after-stable.json"

jq -e --arg pkey "$publisher_key" --arg okey "$offer_key" --arg publisher "$ADD_PUBLISHER" --arg offer "$ADD_OFFER" '
  (.properties.parameters[$pkey].value | index($publisher) != null) and
  (.properties.parameters[$okey].value | index($offer) != null)
' "$workdir/after.json" >/dev/null

jq -n --arg publisher "$ADD_PUBLISHER" --arg offer "$ADD_OFFER" \
  '{verified:true,added:{publisher:$publisher,offer:$offer},other_fields_changed:false}'
