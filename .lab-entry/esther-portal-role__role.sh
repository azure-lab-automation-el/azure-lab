#!/usr/bin/env bash
set -euo pipefail
export INPUT_UPN="${INPUT_UPN}"
export INPUT_GROUPS="${INPUT_GROUPS}"
export ESTHER_PORTAL_CLIENT_ID="${ESTHER_PORTAL_CLIENT_ID}"
ENTRY_FAILED=0
echo "== Add and read back =="
export UPN="${INPUT_UPN}"
export GROUPS="${INPUT_GROUPS}"
export APP="${ESTHER_PORTAL_CLIENT_ID}"
T=$(az account get-access-token --resource-type ms-graph --query accessToken -o tsv); echo "::add-mask::$T"
g(){ curl -sS -X "$1" "https://graph.microsoft.com/v1.0$2" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' ${3:+-d "$3"}; }
uid=$(g GET "/users/$UPN?\$select=id" | jq -r .id); echo "user id: $uid"
IFS=','; for n in $GROUPS; do
  gid=$(g GET "/groups?\$filter=displayName%20eq%20'$(echo $n | sed 's/ /%20/g')'&\$select=id" | jq -r '.value[0].id')
  echo "== $n ($gid)"; g POST "/groups/$gid/members/\$ref" "{\"@odata.id\":\"https://graph.microsoft.com/v1.0/directoryObjects/$uid\"}" | jq -c '.error // "added"' || true
done; unset IFS; sleep 5
echo "== memberOf"; g GET "/users/$uid/memberOf?\$select=displayName" | jq -r '.value[].displayName'
sp=$(g GET "/servicePrincipals?\$filter=appId%20eq%20'$APP'&\$select=id,appRoles" ); spid=$(echo "$sp" | jq -r '.value[0].id')
echo "== app roles via groups"; for gid in $(g GET "/users/$uid/memberOf?\$select=id" | jq -r '.value[].id'); do g GET "/groups/$gid/appRoleAssignments" | jq -r --argjson sp "$sp" '.value[]|select(.resourceId==$sp.value[0].id)|.principalDisplayName+" -> "+(.appRoleId as $r|($sp.value[0].appRoles[]|select(.id==$r)|.value))'; done
