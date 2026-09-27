#!/usr/bin/env bash
set -euo pipefail
export INPUT_UPN="${INPUT_UPN}"
export ESTHER_PORTAL_CLIENT_ID="${ESTHER_PORTAL_CLIENT_ID}"
ENTRY_FAILED=0
echo "== Read =="
export UPN="${INPUT_UPN}"
export APP="${ESTHER_PORTAL_CLIENT_ID}"
T=$(az account get-access-token --resource-type ms-graph --query accessToken -o tsv); echo "::add-mask::$T"
g(){ curl -sS "https://graph.microsoft.com/v1.0$1" -H "Authorization: Bearer $T"; }
echo "== matches"; g "/users?\$filter=startswith(userPrincipalName,'${UPN%%@*}')&\$select=id,userPrincipalName,displayName,accountEnabled,lastPasswordChangeDateTime,createdDateTime,userType" | jq -c '.value[] // .error'
uid=$(g "/users?\$filter=startswith(userPrincipalName,'${UPN%%@*}')&\$select=id" | jq -r '.value[0].id')
echo "== memberOf"; g "/users/$uid/memberOf?\$select=displayName" | jq -r '.value[] | "\(."@odata.type") \(.displayName)"'
echo "== appRoleAssignments"; g "/users/$uid/appRoleAssignments" | jq -c '.value[] | {resourceDisplayName, appRoleId}'
echo "== signIn (may need AuditLog permission)"; g "/users/$uid?\$select=signInActivity" | jq -c '.signInActivity // .error.code'
echo "== audit (who changed this user today)"; g "/auditLogs/directoryAudits?\$filter=targetResources/any(t:t/id%20eq%20'$uid')&\$top=15" | jq -c '(.value // [])[] | {activityDateTime, activityDisplayName, by: (.initiatedBy.user.userPrincipalName // .initiatedBy.app.displayName), result}' || true
echo "== portal app roles"; g "/servicePrincipals?\$filter=appId%20eq%20'$APP'&\$select=displayName,appRoles" | jq -c '.value[0] // "not visible to this identity"' || true
