#!/usr/bin/env bash
set -euo pipefail
export GH_TOKEN="${GH_TOKEN}"
export PR_NUMBER="${PR_NUMBER}"
ENTRY_FAILED=0
echo "== Merge change requests into desired state =="
node tools/merge-requests.mjs
echo "== Plan (read-only Graph) =="
export GRAPH_TOKEN=$(az account get-access-token --resource-type ms-graph --query accessToken -o tsv)
echo "::add-mask::$GRAPH_TOKEN"
node tools/export-current.mjs
node tools/plan.mjs --desired desired-state/state.json --out plan.json || echo "plan exit $?"
echo "== Comment plan on PR =="
export GH_TOKEN="${GH_TOKEN}"
{ echo '### Esther plan'; echo '```json'; jq '{errors,summary,opCount,ops:(.ops[:50])}' plan.json; echo '```'; } > body.md
gh pr comment ${PR_NUMBER} --body-file body.md
