#!/usr/bin/env bash
set -euo pipefail
export COPILOT_GITHUB_TOKEN="${COPILOT_GITHUB_TOKEN}"
export INPUT_TASK="${INPUT_TASK}"
export GROQ_API_KEY="${GROQ_API_KEY}"
export CF_API_TOKEN="${CF_API_TOKEN}"
export CF_ACCOUNT_ID="${CF_ACCOUNT_ID}"
ENTRY_FAILED=0
echo "== Copilot =="
export COPILOT_GITHUB_TOKEN="${COPILOT_GITHUB_TOKEN}"
export TASK="${INPUT_TASK}"
if [ "${INPUT_ENGINE}" = "copilot" ]; then
npm install -g @github/copilot >/dev/null 2>&1
mkdir -p w && cd w && copilot --model auto -p "$TASK" --allow-all-tools 2>&1 | tee ../answer.txt
fi
echo "== Groq =="
export GROQ_API_KEY="${GROQ_API_KEY}"
export TASK="${INPUT_TASK}"
if [ "${INPUT_ENGINE}" = "groq" ]; then
jq -n --arg t "$TASK" '{model:"openai/gpt-oss-120b",messages:[{role:"user",content:$t}]}' > req.json
curl -sS https://api.groq.com/openai/v1/chat/completions -H "Authorization: Bearer $GROQ_API_KEY" -H 'Content-Type: application/json' -d @req.json > resp.json
jq -r '.choices[0].message.content // .error.message // .' resp.json | tee answer.txt
fi
echo "== Cloudflare Workers AI =="
export CF_API_TOKEN="${CF_API_TOKEN}"
export CF_ACCOUNT_ID="${CF_ACCOUNT_ID}"
export TASK="${INPUT_TASK}"
if [ "${INPUT_ENGINE}" = "cloudflare" ]; then
jq -n --arg t "$TASK" '{messages:[{role:"user",content:$t}]}' > req.json
curl -sS "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/ai/run/@cf/meta/llama-3.3-70b-instruct-fp8-fast" -H "Authorization: Bearer $CF_API_TOKEN" -H 'Content-Type: application/json' -d @req.json > resp.json
jq -r '.result.response // .errors // .' resp.json | tee answer.txt
fi
