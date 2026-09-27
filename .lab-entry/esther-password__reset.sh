#!/usr/bin/env bash
set -euo pipefail
export GH_TOKEN="${GH_TOKEN}"
ENTRY_FAILED=0
echo "== Find new password reset requests =="
files=$(git diff --name-only --diff-filter=A HEAD^1 HEAD -- 'requests/*.json' | xargs -r grep -l '"action": "resetPassword"' || true)
FILES="$files"; echo "found: ${FILES:-none}"
echo "== Reset and hand over encrypted =="
export GH_TOKEN="${GH_TOKEN}"
export GRAPH_TOKEN=$(az account get-access-token --resource-type ms-graph --query accessToken -o tsv)
echo "::add-mask::$GRAPH_TOKEN"
if [ -n "$FILES" ]; then node tools/reset-password.mjs $FILES; else echo "no reset requests"; fi
