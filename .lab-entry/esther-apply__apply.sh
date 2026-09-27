#!/usr/bin/env bash
set -euo pipefail
ENTRY_FAILED=0
echo "== step =="
node tools/merge-requests.mjs
echo "== Plan, apply, readback =="
export GRAPH_TOKEN=$(az account get-access-token --resource-type ms-graph --query accessToken -o tsv)
echo "::add-mask::$GRAPH_TOKEN"
node tools/plan.mjs --desired desired-state/state.json --out plan.json
node tools/apply.mjs --plan plan.json --desired desired-state/state.json --reviewed desired-state/reviewed-plan.json
echo "== Export inventory for the portal (read) =="
export GRAPH_TOKEN=$(az account get-access-token --resource-type ms-graph --query accessToken -o tsv)
echo "::add-mask::$GRAPH_TOKEN"
node tools/export-current.mjs && cp current.json inventory.json
echo "== Fold applied requests into desired state =="
git fetch -q origin main && git reset -q --hard origin/main
if ls requests/*.json >/dev/null 2>&1; then
  node tools/merge-requests.mjs
  mkdir -p audit/requests && git mv requests/*.json audit/requests/
  git add desired-state/state.json
  git -c user.name='esther-apply' -c user.email='esther-apply@users.noreply.github.com' commit -m "Fold applied requests (run ${GITHUB_RUN_ID}) [skip ci]"
  git push origin HEAD:main
fi
