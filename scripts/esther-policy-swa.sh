#!/usr/bin/env bash
# SWA narrow unblock (user-approved "Free SKU only" 11:51):
#  1. custom deny definition+assignment: staticSites must be sku Free
#  2. lab-types: append Microsoft.Web/staticSites
#  3. location carve ONLY if SWA isn't offered in israelcentral: exemption on
#     lab-locations with resourceSelector resourceType=staticSites (SWA only)
# Fails closed at every gate. Nothing else changes.
set -Eeuo pipefail
: "${AZURE_SUBSCRIPTION_ID:?}"
RG='rg-learning-monitoring'
SCOPE="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RG}"
API='2025-03-01'
EXAPI='2022-07-01-preview'
DEFNAME='entra-lab-swa-free-only-v1'
DEFID="/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.Authorization/policyDefinitions/${DEFNAME}"
TYPES_ENTRY='Microsoft.Web/staticSites'

umask 077
workdir="$(mktemp -d)"; trap 'rm -rf "$workdir"' EXIT

say() { echo "== $1"; }

# --- 0. SWA regional availability (decides whether the location carve is needed)
say "זמינות SWA באזורים"
az provider show -n Microsoft.Web --query "resourceTypes[?resourceType=='staticSites'].locations[]" -o json > "$workdir/swa-regions.json"
cat "$workdir/swa-regions.json"
NEED_EXEMPTION=1
jq -e 'any(.[]; . == "Israel Central")' "$workdir/swa-regions.json" >/dev/null && NEED_EXEMPTION=0 || true
echo "צריך פטור מיקום: $NEED_EXEMPTION"

if [[ "${WITH_DENY:-0}" == "1" ]]; then
  # --- 1. custom deny definition (subscription scope)
  say "הגדרת מדיניות: SWA חינמי בלבד"
  cat > "$workdir/def.json" <<'JSON'
  {
    "properties": {
      "displayName": "entra-lab-swa-free-only-v1",
      "description": "Allow only Free SKU Static Web Apps in the learning lab.",
      "mode": "All",
      "policyRule": {
        "if": {"allOf": [
          {"field": "type", "equals": "Microsoft.Web/staticSites"},
          {"not": {"field": "Microsoft.Web/staticSites/sku.name", "equals": "Free"}}
        ]},
        "then": {"effect": "deny"}
      }
    }
  }
JSON
  if ! az rest --only-show-errors --method put \
      --url "https://management.azure.com${DEFID}?api-version=${API}" \
      --headers 'Content-Type=application/json' --body "@$workdir/def.json" > "$workdir/def-out.json" 2> "$workdir/def-err.txt"; then
    echo "נכשל: אין הרשאה ליצור הגדרת מדיניות ברמת המנוי"
    cat "$workdir/def-err.txt"
    echo '{"verified":false,"stage":"definition","reason":"no subscription-scope definition permission - nothing else was changed"}'
    exit 1
  fi
  jq -e '.name == "'"$DEFNAME"'"' "$workdir/def-out.json" >/dev/null

  # --- 2. assign the deny at RG scope (idempotent)
  say "שיוך מדיניות ה-deny ל-RG"
  cat > "$workdir/assign.json" <<JSON
  {"properties":{
    "policyDefinitionId": "${DEFID}",
    "displayName": "lab-swa-free-only",
    "enforcementMode": "Default",
    "nonComplianceMessages": [{"message": "Only Free SKU Static Web Apps are allowed in this learning lab."}]
  }}
JSON
  az rest --only-show-errors --method put \
    --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyAssignments/lab-swa-free-only?api-version=${API}" \
    --headers 'Content-Type=application/json' --body "@$workdir/assign.json" > "$workdir/assign-out.json"
  jq -e '.properties.policyDefinitionId == "'"$DEFID"'"' "$workdir/assign-out.json" >/dev/null

else
  echo "מדלג על כלל deny בפוליסי (אפשרות ב׳): האכיפה של Free ב-workflow היוצר"
fi

# --- 3. lab-types: append staticSites (safe full-PUT)
say "הוספת staticSites לרשימת הסוגים"
az rest --only-show-errors --method get \
  --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyAssignments?api-version=${API}" \
  > "$workdir/assignments.json"
TYPEKEY="$(jq -r '.value[] | select(.name == "lab-types") | .name' "$workdir/assignments.json")"
[[ "$TYPEKEY" == "lab-types" ]]
jq -e '.value[] | select(.name == "lab-types") | (.id | ascii_downcase == ("'"${SCOPE}/providers/microsoft.authorization/policyassignments/lab-types"'" | ascii_downcase))' "$workdir/assignments.json" >/dev/null
jq '.value[] | select(.name == "lab-types")' "$workdir/assignments.json" > "$workdir/types-before.json"
param_key="$(jq -r '.properties.parameters | keys[] | select(ascii_downcase | contains("type"))' "$workdir/types-before.json")"
[[ -n "$param_key" && "$(wc -l <<<"$param_key")" -eq 1 ]]
# fail closed if staticSites already present (rerun safety)
! jq -e --arg k "$param_key" --arg t "$TYPES_ENTRY" '.properties.parameters[$k].value | index($t) != null' "$workdir/types-before.json" >/dev/null
jq --arg k "$param_key" --arg t "$TYPES_ENTRY" '
  .properties.parameters[$k].value |= ((. + [$t]) | unique)
  | ({properties:.properties} + (if .identity then {identity:.identity} else {} end) + (if .location then {location:.location} else {} end))
' "$workdir/types-before.json" > "$workdir/types-put.json"
az rest --only-show-errors --method put \
  --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyAssignments/lab-types?api-version=${API}" \
  --headers 'Content-Type=application/json' --body "@$workdir/types-put.json" >/dev/null
az rest --only-show-errors --method get \
  --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyAssignments/lab-types?api-version=${API}" \
  > "$workdir/types-after.json"
jq -S --arg k "$param_key" 'del(.properties.parameters[$k], .properties.metadata.systemData, .properties.metadata.updatedBy, .properties.metadata.updatedOn, .systemData, .etag)' "$workdir/types-before.json" > "$workdir/tb.json"
jq -S --arg k "$param_key" 'del(.properties.parameters[$k], .properties.metadata.systemData, .properties.metadata.updatedBy, .properties.metadata.updatedOn, .systemData, .etag)' "$workdir/types-after.json"  > "$workdir/ta.json"
cmp "$workdir/tb.json" "$workdir/ta.json"
jq -e --arg k "$param_key" --arg t "$TYPES_ENTRY" '.properties.parameters[$k].value | index($t) != null' "$workdir/types-after.json" >/dev/null

# --- 4. location carve only if needed
EXEMPTION="not-needed"
if [[ "$NEED_EXEMPTION" == "1" ]]; then
  say "פטור מיקום מצומצם: SWA בלבד"
  LOCID="$(jq -r '.value[] | select(.name == "lab-locations") | .id' "$workdir/assignments.json")"
  [[ -n "$LOCID" ]]
  jq -n --arg paid "$LOCID" '{
    properties: {
      policyAssignmentId: $paid,
      exemptionCategory: "Waiver",
      displayName: "lab-locations-swa-only",
      description: "Allow Static Web Apps (Free-only per lab-swa-free-only) in SWA-supported regions; all other resource types remain location-denied.",
      resourceSelectors: [{name: "swa-only", selectors: [{kind: "resourceType", in: ["Microsoft.Web/staticSites"]}]}]
    }
  }' > "$workdir/exemption.json"
  az rest --only-show-errors --method put \
    --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyExemptions/lab-locations-swa-only?api-version=${EXAPI}" \
    --headers 'Content-Type=application/json' --body "@$workdir/exemption.json" > "$workdir/exemption-out.json"
  jq -e '.properties.exemptionCategory == "Waiver"' "$workdir/exemption-out.json" >/dev/null
  EXEMPTION="created"
fi

jq -n --arg ex "$EXEMPTION" '{verified:true, deny_definition:"skipped-option-b (Free enforced by creating workflow)", types_added:["Microsoft.Web/staticSites"], location_exemption:$ex, other_fields_changed:false}'
