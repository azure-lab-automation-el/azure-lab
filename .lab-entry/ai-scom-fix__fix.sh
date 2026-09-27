#!/usr/bin/env bash
set -euo pipefail
export LAB_AGENT_PAT="${LAB_AGENT_PAT}"
export GROQ_API_KEY="${GROQ_API_KEY}"
export CF_API_TOKEN="${CF_API_TOKEN}"
export CF_ACCOUNT_ID="${CF_ACCOUNT_ID}"
export COPILOT_GITHUB_TOKEN="${COPILOT_GITHUB_TOKEN}"
export INPUT_RESTORE_TAG="${INPUT_RESTORE_TAG}"
ENTRY_FAILED=0
echo "== Run =="
export GH_TOKEN="${LAB_AGENT_PAT}"
export GROQ_API_KEY="${GROQ_API_KEY}"
export CF_API_TOKEN="${CF_API_TOKEN}"
export CF_ACCOUNT_ID="${CF_ACCOUNT_ID}"
export COPILOT_GITHUB_TOKEN="${COPILOT_GITHUB_TOKEN}"
export RUN_ID="${INPUT_RUN_ID:-$WR_RUN_ID}"
export MODE="${INPUT_MODE:-fix}"
export TAG="${INPUT_RESTORE_TAG}"
git config user.name "lab-ai"; git config user.email "azure-lab-automation-el@users.noreply.github.com"
if [ "$MODE" = rollback ]; then git checkout -qb rollback-$GITHUB_RUN_ID; git checkout "$TAG" -- scripts/scom; git commit -qm "rollback scripts/scom to $TAG"; git push -q origin HEAD HEAD:main && echo ROLLBACK_OK; exit 0; fi
npm install -g @github/copilot >/dev/null 2>&1 || true
bash scripts/ai/scom-fix.sh "$RUN_ID" 2>&1 | tee ai.log
