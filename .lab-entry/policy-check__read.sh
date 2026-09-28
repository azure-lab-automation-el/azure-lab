#!/usr/bin/env bash
set -uo pipefail
echo "== def show raw =="
az policy definition show -n lab-types 2>&1 | head -5
echo "== def list =="
az policy definition list --query "[?contains(name,'lab')].{n:name,scope:id}" -o json 2>&1 | head -20
echo "== assign list RG =="
az policy assignment list --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-learning-monitoring" --query "[].{n:name,def:properties.policyDefinitionId}" -o json 2>&1 | head -40
