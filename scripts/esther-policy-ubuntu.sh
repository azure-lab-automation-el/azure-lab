#!/usr/bin/env bash
# User-approved 2026-09-24 08:33 ("מאושר"): add exactly Canonical / ubuntu-24_04-lts to the lab image allowlist. Nothing else changes.
set -Eeuo pipefail
: "${AZURE_SUBSCRIPTION_ID:?}"
SCOPE="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/rg-learning-monitoring"; API='2025-03-01'; A='lab-vm-images'
U="https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyAssignments/${A}?api-version=${API}"
umask 077; w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
az rest --only-show-errors --method get --url "$U" > $w/before.json
pk=$(jq -r '.properties.parameters|keys[]|select(ascii_downcase|contains("publisher"))' $w/before.json); ok=$(jq -r '.properties.parameters|keys[]|select(ascii_downcase|contains("offer"))' $w/before.json)
[[ $(wc -l <<<"$pk") == 1 && $(wc -l <<<"$ok") == 1 ]]
echo "BEFORE publishers=$(jq -c --arg k "$pk" '.properties.parameters[$k].value' $w/before.json) offers=$(jq -c --arg k "$ok" '.properties.parameters[$k].value' $w/before.json)"
jq --arg pk "$pk" --arg ok "$ok" '.properties.parameters[$pk].value |= ((. + ["Canonical"])|unique) | .properties.parameters[$ok].value |= ((. + ["ubuntu-24_04-lts"])|unique)
  | ({properties:.properties} + (if .identity then {identity:.identity} else {} end) + (if .location then {location:.location} else {} end))' $w/before.json > $w/put.json
az rest --only-show-errors --method put --url "$U" --headers 'Content-Type=application/json' --body "@$w/put.json" >/dev/null
az rest --only-show-errors --method get --url "$U" > $w/after.json
echo "AFTER publishers=$(jq -c --arg k "$pk" '.properties.parameters[$k].value' $w/after.json) offers=$(jq -c --arg k "$ok" '.properties.parameters[$k].value' $w/after.json)"
# Everything except those two lists must be unchanged.
f='del(.properties.metadata, .systemData, .etag) | .properties.parameters |= with_entries(.value.value |= (if type=="array" then (. - ["Canonical","ubuntu-24_04-lts"]) else . end))'
cmp <(jq -S "$f" $w/before.json) <(jq -S "$f" $w/after.json) && echo POLICY_UBUNTU_OK
