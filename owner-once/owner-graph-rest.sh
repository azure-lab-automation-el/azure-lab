#!/usr/bin/env bash
# Same as create-esther-graph-apps.sh but via Graph REST with an Owner Graph token in $GRAPH_TOKEN (no az needed).
set -Eeuo pipefail
: "${GRAPH_TOKEN:?}"; G=https://graph.microsoft.com/v1.0
SUBJ='repo:azure-lab-automation-el@332180512/azure-lab-automation@1380347379'
api(){ local m=$1 u=$2; shift 2; curl -sS -f -X "$m" "$G$u" -H "Authorization: Bearer $GRAPH_TOKEN" -H 'Content-Type: application/json' "$@"; }
graph_sp=$(api GET "/servicePrincipals(appId='00000003-0000-0000-c000-000000000000')?\$select=id,appRoles")
gsp_id=$(jq -r .id <<<"$graph_sp")
rid(){ jq -r --arg v "$1" '.appRoles[]|select(.value==$v and (.allowedMemberTypes|index("Application")))|.id' <<<"$graph_sp"; }
ensure(){ local name=$1 subject=$2; shift 2
  local app; app=$(api GET "/applications?\$filter=displayName%20eq%20'$name'&\$select=id,appId" | jq -c '.value[0] // empty')
  [[ -n "$app" ]] || app=$(api POST /applications -d "{\"displayName\":\"$name\",\"signInAudience\":\"AzureADMyOrg\"}" | jq -c '{id,appId}')
  local oid appid; oid=$(jq -r .id <<<"$app"); appid=$(jq -r .appId <<<"$app")
  local sp; sp=$(api GET "/servicePrincipals?\$filter=appId%20eq%20'$appid'&\$select=id" | jq -r '.value[0].id // empty')
  [[ -n "$sp" ]] || sp=$(api POST /servicePrincipals -d "{\"appId\":\"$appid\"}" | jq -r .id)
  api GET "/applications/$oid/federatedIdentityCredentials" | jq -e --arg s "$subject" '.value[]|select(.subject==$s)' >/dev/null || \
    api POST "/applications/$oid/federatedIdentityCredentials" -d "{\"name\":\"github-$name\",\"issuer\":\"https://token.actions.githubusercontent.com\",\"subject\":\"$subject\",\"audiences\":[\"api://AzureADTokenExchange\"]}" >/dev/null
  local have; have=$(api GET "/servicePrincipals/$sp/appRoleAssignments" | jq -r '.value[].appRoleId')
  for p in "$@"; do local r; r=$(rid "$p"); [[ -n "$r" ]] || { echo "unknown $p"; exit 3; }
    grep -q "$r" <<<"$have" || api POST "/servicePrincipals/$sp/appRoleAssignments" -d "{\"principalId\":\"$sp\",\"resourceId\":\"$gsp_id\",\"appRoleId\":\"$r\"}" >/dev/null; done
  # readback
  echo "{\"name\":\"$name\",\"clientId\":\"$appid\",\"spId\":\"$sp\",\"fic\":$(api GET "/applications/$oid/federatedIdentityCredentials" | jq -c '[.value[]|{name,subject}]'),\"graphRoles\":$(api GET "/servicePrincipals/$sp/appRoleAssignments" | jq -c --slurpfile g <(echo "$graph_sp") '[.value[].appRoleId as $i | $g[0].appRoles[]|select(.id==$i)|.value]')}"
}
ensure esther-graph-read  "$SUBJ:pull_request"            User.Read.All Group.Read.All
ensure esther-graph-write "$SUBJ:environment:esther-apply" User.ReadWrite.All Group.ReadWrite.All
