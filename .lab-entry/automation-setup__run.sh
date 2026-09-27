#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export INPUT_STAGE="${INPUT_STAGE}"
export LAB_AGENT_PAT="${LAB_AGENT_PAT}"
ENTRY_FAILED=0
echo "== step =="
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export STAGE="${INPUT_STAGE}"
export GH_TOKEN_SECRETS="${LAB_AGENT_PAT}"
export GH_REPO="${GITHUB_REPOSITORY}"
bash scripts/automation/setup.sh
