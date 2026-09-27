#!/usr/bin/env bash
set -euo pipefail
export AZURE_CLIENT_ID="${AZURE_CLIENT_ID}"
ENTRY_FAILED=0
echo "== step =="
az role assignment list --assignee ${AZURE_CLIENT_ID} --all --query '[].{role:roleDefinitionName,scope:scope}' -o table
az role definition list --custom-role-only true --query '[].{name:roleName,actions:permissions[0].actions}' -o json
az staticwebapp hostname list -n esther-cloud-admin -g rg-learning-monitoring -o table || true
