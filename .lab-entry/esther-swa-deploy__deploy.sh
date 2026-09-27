#!/usr/bin/env bash
set -euo pipefail
export GH_TOKEN="${GH_TOKEN}"
export ESTHER_METRICS_KEY="${ESTHER_METRICS_KEY}"
export ESTHER_REQUEST_TOKEN="${ESTHER_REQUEST_TOKEN}"
ENTRY_FAILED=0
echo "== Latest inventory from the last successful esther-apply =="
export GH_TOKEN="${GH_TOKEN}"
id=$(gh run list -R ${GITHUB_REPOSITORY} --workflow esther-apply.yml --status success -L 1 --json databaseId -q '.[0].databaseId')
gh run download "$id" -R ${GITHUB_REPOSITORY} -n inventory -D /tmp/inv && cp /tmp/inv/inventory.json api/inventory.json || echo '{"users":[],"groups":[]}' > api/inventory.json
mkdir -p api/config && cp config/portal-roles.json config/approval-policy.json config/templates.json config/portal-app.json api/config/ && cp staticwebapp.config.json frontend/ && printf '{"sha":"%s","builtAt":"%s"}\n' "${GITHUB_SHA}" "$(date -u +%FT%TZ)" > frontend/version.json
jq -c '{users:(.users|length),groups:(.groups|length),generatedAt}' api/inventory.json
echo "== Latest scheduled-task report (dry-run) =="
export GH_TOKEN="${GH_TOKEN}"
id=$(gh run list -R ${GITHUB_REPOSITORY} --workflow esther-scheduled.yml --status success -L 1 --json databaseId -q '.[0].databaseId')
if [ -n "$id" ] && gh run download "$id" -R ${GITHUB_REPOSITORY} -n rules-report -D /tmp/sched 2>/dev/null && [ -f /tmp/sched/scheduled-report.json ]; then cp /tmp/sched/scheduled-report.json api/scheduled-report.json; fi
[ -f api/scheduled-report.json ] || node tools/scheduled-tasks.mjs --snapshot api/inventory.json --out api/scheduled-report.json
cp config/schedules.json config/group-rules.json api/config/
echo "== Activity log for the admin console (read-only) =="
export GH_TOKEN="${GH_TOKEN}"
node tools/build-audit-log.mjs api/audit-log.json || echo '{"events":[],"workflows":[]}' > api/audit-log.json
echo "== Metrics feed for SquaredUp (cost + workflows, read-only) =="
export GH_TOKEN="${GH_TOKEN}"
export MK="${ESTHER_METRICS_KEY}"
id=$(gh run list -R ${GITHUB_REPOSITORY} --workflow esther-costs-read.yml --status success -L 1 --json databaseId -q '.[0].databaseId')
[ -n "$id" ] && gh run download "$id" -R ${GITHUB_REPOSITORY} -D /tmp/dl && mkdir -p /tmp/costs && cp /tmp/dl/*/azure-*.json /tmp/costs/ || echo 'no cost artifact'
node tools/build-metrics.mjs api/metrics.json
if [ -n "$MK" ]; then printf '%s' "$MK" > api/.metrics-key; fi
echo "== Request token for the API (repo-scoped, contents + pull requests only) =="
export T="${ESTHER_REQUEST_TOKEN}"
if [ -n "$T" ]; then printf '%s' "$T" > api/.request-token; else echo 'ESTHER_REQUEST_TOKEN not set: portal requests will be preview-only'; fi
