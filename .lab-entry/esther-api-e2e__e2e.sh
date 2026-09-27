#!/usr/bin/env bash
set -euo pipefail
export GH_TOKEN="${GH_TOKEN}"
export ESTHER_REQUEST_TOKEN="${ESTHER_REQUEST_TOKEN}"
ENTRY_FAILED=0
echo "== Inventory + config like the deploy =="
export GH_TOKEN="${GH_TOKEN}"
id=$(gh run list -R ${GITHUB_REPOSITORY} --workflow esther-apply.yml --status success -L 1 --json databaseId -q '.[0].databaseId')
gh run download "$id" -R ${GITHUB_REPOSITORY} -n inventory -D /tmp/inv && cp /tmp/inv/inventory.json api/inventory.json
mkdir -p api/config && cp config/portal-roles.json config/approval-policy.json config/templates.json config/portal-app.json api/config/
echo "== E2E against GitHub with the real request token =="
export GH_REQUEST_TOKEN="${ESTHER_REQUEST_TOKEN}"
node tests/e2e/api-e2e.js
