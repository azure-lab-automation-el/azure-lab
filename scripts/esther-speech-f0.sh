#!/usr/bin/env bash
set -Eeuo pipefail
RG='rg-learning-monitoring'; REGION='swedencentral'; NAME='esther-lesson-speech-f0'; TYPE='Microsoft.CognitiveServices/accounts'
S="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RG}"; U="https://management.azure.com${S}/providers/Microsoft.Authorization/policyAssignments/lab-types?api-version=2025-03-01"
umask 077; w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
# Validate source subscription, location, identity and policy before any writes.
az account show --query '{id:id,tenantId:tenantId,state:state}' -o json
az rest --method get --url "$U" > "$w/before.json"
jq -e --arg id "${S}/providers/Microsoft.Authorization/policyAssignments/lab-types" '
  (.id|ascii_downcase)==($id|ascii_downcase) and
  (.properties.parameters.listOfAllowedResourceTypes.value|type)=="array" and
  (.properties.policyDefinitionId|type)=="string"
' "$w/before.json" >/dev/null
az rest --method get --url "https://management.azure.com${S}/providers/Microsoft.Authorization/policyAssignments/lab-locations?api-version=2025-03-01" > "$w/loc.json"
jq -e --arg r "$REGION" '.properties.parameters.listOfAllowedLocations.value|index($r)!=null' "$w/loc.json" >/dev/null
existing=$(az resource show -g "$RG" -n "$NAME" --resource-type "$TYPE" --api-version 2023-05-01 --query '{id:id,kind:kind,sku:sku.name,location:location}' -o json 2>/dev/null || true)
if [[ -n "$existing" ]]; then echo "$existing" | jq -e --arg r "$REGION" '.kind=="SpeechServices" and .sku=="F0" and .location==$r' >/dev/null; fi
# Change only one exact allowed type. Preserve the assignment's other writable fields and parameters.
if ! jq -e --arg type "$TYPE" '.properties.parameters.listOfAllowedResourceTypes.value|index($type)!=null' "$w/before.json" >/dev/null; then
  jq --arg type "$TYPE" '.properties.parameters.listOfAllowedResourceTypes.value += [$type] | ({properties:.properties} + (if .identity then {identity:.identity} else {} end) + (if .location then {location:.location} else {} end))' "$w/before.json" > "$w/put.json"
  az rest --method put --url "$U" --headers 'Content-Type=application/json' --body "@$w/put.json" >/dev/null
fi
az rest --method get --url "$U" > "$w/after.json"
jq -e --arg type "$TYPE" '.properties.parameters.listOfAllowedResourceTypes.value|index($type)!=null' "$w/after.json" >/dev/null
# Compare the action-bearing policy fields; Azure may normalize display metadata, assignment IDs or provider defaults on PUT.
jq -S --arg type "$TYPE" '.properties | {policyDefinitionId,parameters,effect,notScopes,enforcementMode} | .parameters.listOfAllowedResourceTypes.value -= [$type]' "$w/before.json" > "$w/normalized-before.json"
jq -S --arg type "$TYPE" '.properties | {policyDefinitionId,parameters,effect,notScopes,enforcementMode} | .parameters.listOfAllowedResourceTypes.value -= [$type]' "$w/after.json" > "$w/normalized-after.json"
if ! cmp -s "$w/normalized-before.json" "$w/normalized-after.json"; then
  echo 'POLICY_ACTION_FIELDS_CHANGED; halting before resource creation'
  diff -u "$w/normalized-before.json" "$w/normalized-after.json" | sed -n '1,100p'
  exit 1
fi
echo 'POLICY_ONLY_SPEECH_TYPE_ADDED'
# Provider registration is a subscription prerequisite and does not create a billable service.
registration=$(az provider show -n Microsoft.CognitiveServices --query registrationState -o tsv)
if [[ "$registration" != Registered ]]; then
  az provider register -n Microsoft.CognitiveServices --wait --only-show-errors >/dev/null
fi
[[ "$(az provider show -n Microsoft.CognitiveServices --query registrationState -o tsv)" == Registered ]]
echo 'COGNITIVE_PROVIDER_REGISTERED'
if [[ -z "$existing" ]]; then
  # Explicit F0 ARM body; never allow S0 fallback. A failed F0 request stops the workflow.
  jq -n --arg loc "$REGION" '{location:$loc,kind:"SpeechServices",sku:{name:"F0"},properties:{publicNetworkAccess:"Enabled"},tags:{purpose:"lesson-voice-sample",pricing:"F0-only"}}' > "$w/resource.json"
  az rest --method put --url "https://management.azure.com${S}/providers/${TYPE}/${NAME}?api-version=2023-05-01" --headers 'Content-Type=application/json' --body "@$w/resource.json" > "$w/create.json"
fi
for i in {1..30}; do
  az rest --method get --url "https://management.azure.com${S}/providers/${TYPE}/${NAME}?api-version=2023-05-01" > "$w/readback.json"
  jq -e --arg r "$REGION" '.kind=="SpeechServices" and .sku.name=="F0" and .location==$r' "$w/readback.json" >/dev/null
  state=$(jq -r '.properties.provisioningState' "$w/readback.json")
  [[ "$state" == Succeeded ]] && break
  [[ "$state" == Failed ]] && { echo 'F0 provisioning failed'; exit 1; }
  sleep 6
done
[[ "$(jq -r '.properties.provisioningState' "$w/readback.json")" == Succeeded ]]
jq '{name,kind,location,sku:.sku.name,provisioningState:.properties.provisioningState}' "$w/readback.json"
# Fetch key into a private temp file, never print. Speech REST returns RIFF WAV at 16kHz.
az cognitiveservices account keys list -g "$RG" -n "$NAME" --query key1 -o tsv > "$w/key"
cat > "$w/sample.xml" <<'SSML'
<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="he-IL"><voice name="he-IL-HilaNeural"><prosody rate="+4%" pitch="+1%">עכשיו גילינו משהו מפתיע. העלינו קובץ זהה לשני נתיבים. האם צריך לשמור אותו פעמיים? לא. ארטיפקטורי מחשב מזהה של תוכן הקובץ, שנקרא צ'קסום. הוא שומר עותק בינארי אחד, ולשני הנתיבים יש הפניות במסד הנתונים.</prosody></voice></speak>
SSML
# The resource hostname avoids ambiguity about which regional endpoint owns a just-created key.
# Azure may need a few minutes to propagate a new key. Do not print response bodies or keys.
endpoint=$(jq -r '.properties.endpoint // empty' "$w/readback.json")
# Some Speech resources expose a different first-party endpoint or none. The
# regional endpoint is documented and remains the safe fallback.
if [[ "$endpoint" != https://*.cognitiveservices.azure.com* ]]; then
  endpoint="https://${REGION}.tts.speech.microsoft.com"
  path='/cognitiveservices/v1'
else
  path='/tts/cognitiveservices/v1'
fi
status=''
for i in {1..4}; do
  status=$(curl -sS -o "$w/response" -w '%{http_code}' -X POST "${endpoint%/}${path}" \
    -H "Ocp-Apim-Subscription-Key: $(cat "$w/key")" -H 'Content-Type: application/ssml+xml' -H 'X-Microsoft-OutputFormat: riff-16khz-16bit-mono-pcm' -H 'User-Agent: EstherLessonSample' --data-binary "@$w/sample.xml")
  [[ "$status" == 200 ]] && { mv "$w/response" esther-hila-sample.wav; break; }
  [[ "$status" == 401 ]] || { echo "TTS HTTP $status (response hidden)"; exit 1; }
  echo "TTS key not ready, retry $i/4 after 30s"
  sleep 30
done
[[ "$status" == 200 ]] || { echo 'TTS HTTP 401 after 4 attempts (response hidden)'; exit 1; }
file esther-hila-sample.wav | grep -q 'WAVE audio'; echo 'F0_HILA_WAV_OK'
