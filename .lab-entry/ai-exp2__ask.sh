#!/usr/bin/env bash
set -euo pipefail
export CF_API_TOKEN="${CF_API_TOKEN}"
export CF_ACCOUNT_ID="${CF_ACCOUNT_ID}"
ENTRY_FAILED=0
echo "== step =="
export CF_API_TOKEN="${CF_API_TOKEN}"
export CF_ACCOUNT_ID="${CF_ACCOUNT_ID}"
mkdir out
curl -s "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/ai/models/search?per_page=300" -H "Authorization: Bearer $CF_API_TOKEN" | jq -r '.result[]|select(.task.name=="Text Generation")|.name' | grep -iE 'kimi|deepseek|qwen2.5-coder|qwen3-coder' | tee out/models.txt
while read -r m; do s=$(date +%s)
  jq -n --rawfile t ai/exp2/prompt.txt '{messages:[{role:"user",content:$t}],max_tokens:4000}' > req.json
  curl -sS --max-time 240 "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/ai/run/$m" -H "Authorization: Bearer $CF_API_TOKEN" -H 'Content-Type: application/json' -d @req.json > resp.json || true
  f=out/$(echo "$m" | tr '/@' '__').js
  jq -r '.result.response // .result.choices[0].message.content // (.errors|tostring) // "EMPTY"' resp.json > "$f"
  echo "$m $(( $(date +%s)-s ))s $(wc -c < "$f")B" | tee -a out/timing.txt
done < out/models.txt
