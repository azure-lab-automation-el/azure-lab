#!/usr/bin/env bash
set -euo pipefail
export INPUT_UPN="${INPUT_UPN}"
export ESTHER_INIT_PW="${ESTHER_INIT_PW}"
export AZURE_TENANT_ID="${AZURE_TENANT_ID}"
ENTRY_FAILED=0
echo "== Set password =="
export UPN="${INPUT_UPN}"
export PW="${ESTHER_INIT_PW}"
[ -n "$PW" ] || { echo 'no ESTHER_INIT_PW secret'; exit 1; }
T=$(az account get-access-token --resource-type ms-graph --query accessToken -o tsv); echo "::add-mask::$T"
body=$(jq -n --arg p "$PW" '{passwordProfile:{forceChangePasswordNextSignIn:false,password:$p}}')
code=$(curl -s -o /tmp/r -w '%{http_code}' -X PATCH "https://graph.microsoft.com/v1.0/users/$UPN" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -d "$body")
echo "Graph PATCH: $code"; [ "$code" = 204 ] || { jq -c '.error|{code,message}' /tmp/r; exit 1; }
echo "== Verify the password non-interactively (prints only the Entra result code) =="
export UPN="${INPUT_UPN}"
export PW="${ESTHER_INIT_PW}"
export TID="${AZURE_TENANT_ID}"
# ROPC with the public Azure CLI client. AADSTS50126 = wrong password; 50053 = locked; 50076/50079/50072 = password OK but MFA/registration needed.
sleep 30
r=$(curl -s -X POST "https://login.microsoftonline.com/$TID/oauth2/v2.0/token" --data-urlencode client_id=04b07795-8ddb-461a-bbee-02f9e1bf7b46 \
  --data-urlencode grant_type=password --data-urlencode scope=openid --data-urlencode "username=$UPN" --data-urlencode "password=$PW")
if echo "$r" | jq -e .access_token >/dev/null 2>&1 || echo "$r" | jq -e .id_token >/dev/null 2>&1; then echo "VERIFY: password OK, token issued (no MFA prompt)"
else echo "VERIFY: $(echo "$r" | jq -r '.error_codes // [] | map(tostring) | join(",")') $(echo "$r" | jq -r .error_description | head -c 160)"; fi
echo "== tenant domains"; T=$(az account get-access-token --resource-type ms-graph --query accessToken -o tsv); echo "::add-mask::$T"
curl -s "https://graph.microsoft.com/v1.0/policies/identitySecurityDefaultsEnforcementPolicy" -H "Authorization: Bearer $T" | jq -c '{securityDefaults: (.isEnabled // .error.code)}'
