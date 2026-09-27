#!/usr/bin/env bash
# ONE-TIME, run by the tenant OWNER in Azure Cloud Shell (Bash, "No storage account required").
# Creates two separate app identities for the Esther portal with GitHub OIDC (no secrets):
#   esther-graph-read  : User.Read.All, Group.Read.All         -> federated to pull_request runs (plan only)
#   esther-graph-write : User.ReadWrite.All, Group.ReadWrite.All -> federated ONLY to GitHub environment esther-apply
# Does NOT: change security defaults/Conditional Access, create secrets, touch RBAC/subscriptions/billing,
#           grant Directory.ReadWrite.All, password or MFA-method permissions.
# Idempotent: re-running reuses existing apps/credentials/grants.
set -Eeuo pipefail
TENANT=f80b4063-5bc4-47e4-9ea6-a2a19ed79fa3
REPO_SUBJECT_PREFIX='repo:azure-lab-automation-el@332180512/azure-lab-automation@1380347379'
GRAPH_APPID=00000003-0000-0000-c000-000000000000

[[ "$(az account show --query tenantId -o tsv)" == "$TENANT" ]] || { echo "Wrong tenant"; exit 2; }
graph_sp=$(az ad sp show --id "$GRAPH_APPID" --query id -o tsv)

role_id() { az ad sp show --id "$GRAPH_APPID" --query "appRoles[?value=='$1' && contains(allowedMemberTypes,'Application')].id | [0]" -o tsv; }

ensure_app() { # name subject perms...
  local name=$1 subject=$2; shift 2
  local app_id; app_id=$(az ad app list --display-name "$name" --query '[0].appId' -o tsv)
  [[ -n "$app_id" ]] || app_id=$(az ad app create --display-name "$name" --sign-in-audience AzureADMyOrg --query appId -o tsv)
  az ad sp show --id "$app_id" >/dev/null 2>&1 || az ad sp create --id "$app_id" >/dev/null
  local sp; sp=$(az ad sp show --id "$app_id" --query id -o tsv)
  if [[ -z "$(az ad app federated-credential list --id "$app_id" --query "[?subject=='$subject'].name | [0]" -o tsv)" ]]; then
    az ad app federated-credential create --id "$app_id" --parameters "{\"name\":\"github-${name}\",\"issuer\":\"https://token.actions.githubusercontent.com\",\"subject\":\"${subject}\",\"audiences\":[\"api://AzureADTokenExchange\"]}" >/dev/null
  fi
  local existing; existing=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$sp/appRoleAssignments" --query 'value[].appRoleId' -o tsv)
  for perm in "$@"; do
    local rid; rid=$(role_id "$perm"); [[ -n "$rid" ]] || { echo "Unknown Graph role $perm"; exit 3; }
    grep -q "$rid" <<<"$existing" || az rest --method POST --url "https://graph.microsoft.com/v1.0/servicePrincipals/$sp/appRoleAssignments" \
      --body "{\"principalId\":\"$sp\",\"resourceId\":\"$graph_sp\",\"appRoleId\":\"$rid\"}" >/dev/null
  done
  echo "== $name  clientId=$app_id"
  az ad app federated-credential list --id "$app_id" --query '[].{name:name,subject:subject}' -o table
  az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$sp/appRoleAssignments" --query 'value[].appRoleId' -o tsv \
    | while read -r r; do az ad sp show --id "$GRAPH_APPID" --query "appRoles[?id=='$r'].value | [0]" -o tsv; done
}

ensure_app esther-graph-read  "${REPO_SUBJECT_PREFIX}:pull_request"            User.Read.All Group.Read.All
ensure_app esther-graph-write "${REPO_SUBJECT_PREFIX}:environment:esther-apply" User.ReadWrite.All Group.ReadWrite.All
echo "Done. Send back only the two clientId values (not secret). Then sign out of Cloud Shell."
