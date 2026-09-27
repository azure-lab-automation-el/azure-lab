#!/usr/bin/env bash
set -euo pipefail
ENTRY_FAILED=0
echo "== Snapshot, drift plan, rules (read-only) =="
export GRAPH_TOKEN=$(az account get-access-token --resource-type ms-graph --query accessToken -o tsv)
echo "::add-mask::$GRAPH_TOKEN"
node tools/export-current.mjs
node tools/plan.mjs --desired desired-state/state.json --out plan.json || true
node tools/rules-check.mjs --snapshot current.json --plan plan.json
node tools/scheduled-tasks.mjs --snapshot current.json --plan plan.json --rules rules-report.json
