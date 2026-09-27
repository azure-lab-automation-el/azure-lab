#!/usr/bin/env bash
set -euo pipefail
export LAB_AGENT_PAT="${LAB_AGENT_PAT}"
export GROQ_API_KEY="${GROQ_API_KEY}"
export CF_API_TOKEN="${CF_API_TOKEN}"
export CF_ACCOUNT_ID="${CF_ACCOUNT_ID}"
export COPILOT_GITHUB_TOKEN="${COPILOT_GITHUB_TOKEN}"
export INPUT_SOURCE_RUN="${INPUT_SOURCE_RUN}"
ENTRY_FAILED=0
echo "== Calc =="
export GH_TOKEN="${LAB_AGENT_PAT}"
export GROQ_API_KEY="${GROQ_API_KEY}"
export CF_API_TOKEN="${CF_API_TOKEN}"
export CF_ACCOUNT_ID="${CF_ACCOUNT_ID}"
export COPILOT_GITHUB_TOKEN="${COPILOT_GITHUB_TOKEN}"
npm install -g @github/copilot >/dev/null 2>&1 || true
bash scripts/ai/p6-calc.sh "${INPUT_SOURCE_RUN}" 2>&1 | tee ai.log
