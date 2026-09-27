#!/usr/bin/env bash
set -euo pipefail
export GROQ_API_KEY="${GROQ_API_KEY}"
export CF_API_TOKEN="${CF_API_TOKEN}"
export CF_ACCOUNT_ID="${CF_ACCOUNT_ID}"
ENTRY_FAILED=0
echo "== step =="
export GROQ_API_KEY="${GROQ_API_KEY}"
export CF_API_TOKEN="${CF_API_TOKEN}"
export CF_ACCOUNT_ID="${CF_ACCOUNT_ID}"
echo "== GROQ"; curl -s https://api.groq.com/openai/v1/models -H "Authorization: Bearer $GROQ_API_KEY" | jq -r '.data[].id' | sort
echo "== CF"; curl -s "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/ai/models/search?per_page=300" -H "Authorization: Bearer $CF_API_TOKEN" | jq -r '.result[]|select(.task.name=="Text Generation")|.name' | sort
