#!/usr/bin/env bash
# Lean model loop for a failed SCOM run. Lab data only: exact error log + the target file. Never personal data.
# Roles by strength: groq = triage (summarize long log -> exact error), copilot = patch writer, cloudflare = reviewer.
# One attempt per writer per failure; on fail go straight to the next writer, then escalate to the agent.
# A model failing twice on a task type is removed from that task type. Machine checks + restore tag gate every merge.
set -uo pipefail
RUN=$1; R=$GITHUB_REPOSITORY; T0=$(date +%s); F=scripts/scom/scom-install.ps1
n=$(gh run list -R $R -w ai-scom-fix.yml --created ">=$(date -u -d '-1 hour' +%FT%TZ)" --json databaseId -q length); [ "${n:-0}" -gt 4 ] && { echo "ESCALATE: loop guard, $n model runs in the last hour"; exit 0; }
git fetch -q origin ai-state 2>/dev/null && git show origin/ai-state:scoreboard.json > sb.json 2>/dev/null || echo '{}' > sb.json
jq '.v2 //= {"fails":{},"stats":{}} | .runs //= []' sb.json > t && mv t sb.json
removed() { [ "$(jq -r --arg k "$1/$2" '.v2.fails[$k] // 0' sb.json)" -ge 2 ]; }
score() { jq --arg k "$1/$2" --arg r $3 '.v2.stats[$k][$r]=((.v2.stats[$k][$r]//0)+1) | (if $r=="fail" then .v2.fails[$k]=((.v2.fails[$k]//0)+1) else .v2.fails[$k]=0 end)' sb.json > t && mv t sb.json; echo "SCORE $1/$2=$3"; }
groq() { jq -n --arg t "$1" '{model:"openai/gpt-oss-120b",temperature:0,messages:[{role:"user",content:$t}]}' | curl -sS https://api.groq.com/openai/v1/chat/completions -H "Authorization: Bearer $GROQ_API_KEY" -H 'Content-Type: application/json' -d @- | jq -r '.choices[0].message.content // .error.message'; }
cloudflare() { jq -n --arg t "$1" '{messages:[{role:"user",content:$t}],max_tokens:3000}' | curl -sS "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/ai/run/@cf/meta/llama-3.3-70b-instruct-fp8-fast" -H "Authorization: Bearer $CF_API_TOKEN" -H 'Content-Type: application/json' -d @- | jq -r '.result.response // .errors'; }
cfm() { jq -n --arg t "$2" '{messages:[{role:"user",content:$t}],max_tokens:4000,temperature:0}' | curl -sS "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/ai/run/$1" -H "Authorization: Bearer $CF_API_TOKEN" -H 'Content-Type: application/json' -d @- | jq -r '.result.response // .result.choices[0].message.content // .errors'; }
kimi_code() { cfm @cf/moonshotai/kimi-k2.7-code "$1"; }
qwen_coder() { cfm @cf/qwen/qwen2.5-coder-32b-instruct "$1"; }
deepseek_pro() { cfm @cf/deepseek-ai/deepseek-v4-pro-0813 "$1"; }
copilot() { mkdir -p /tmp/cw && cd /tmp/cw && timeout 300 copilot --model auto -p "$1" 2>/dev/null; cd - >/dev/null; }
gh run view $RUN -R $R --log-failed 2>/dev/null | cut -f3- > full.log; [ -s full.log ] || gh run view $RUN -R $R --log | cut -f3- > full.log
grep -E 'STAGE_FAIL|FAILED|error|Error|exception|log: ' full.log | tail -40 > err.log
# 1) triage (groq): exact error in 3 lines
if ! removed groq triage; then TRI=$(groq "From this failed lab install log, state the exact failing step and error in at most 3 lines. No advice.
$(tail -150 full.log)"); [ -n "$TRI" ] && score groq triage pass || score groq triage fail; else TRI=$(cat err.log); fi
echo "TRIAGE: $TRI"
# Experiment 2 (after 3/3 diffs failed to apply): smaller target region + replacement block instead of diff, temperature 0.
STG=$(grep -oE 'STAGE_FAIL [a-z-]+|PHASE5_FAILED at [a-z-]+' err.log | tail -1 | awk '{print $NF}'); [ -z "$STG" ] && STG=webconsole
awk -v s="'$STG' {" 'index($0,s)==1{f=1} f{print} f&&/^ }$/{exit}' $F > block.ps1
P="Fix this PowerShell switch-case block from a lab install script. Failure: $TRI
Exact error lines:
$(cat err.log)
Return ONLY the complete corrected block, starting with the line '$STG' { and ending with the line ' }'. Same indentation. No prose, no fences.
=== BLOCK ===
$(cat block.ps1)"
export EXPERIMENT="replacement-block,stage-only-context,temp0"
res=fail; why="no writer available"; FIX=none
# Patch writers: Cloudflare Workers AI code models (Cloudflare does not train on customer content). Groq/Copilot removed from patch (2 fails each).
for W in kimi_code qwen_coder deepseek_pro copilot groq; do removed $W patch && continue; FIX=$W; git checkout -q -- . 2>/dev/null
  $W "$P" | sed '/^```/d' > new.$W.ps1; ok=1; why=""
  head -1 new.$W.ps1 | grep -q "^'$STG' {" && tail -1 new.$W.ps1 | grep -q '^ }$' || { ok=0; why="$W: block format invalid"; }
  [ $ok = 1 ] && { python3 -c "import sys;f,o,n=sys.argv[1:];s=open(f).read();a=open(o).read();b=open(n).read();assert a in s;open(f,'w').write(s.replace(a,b.rstrip('\n')+'\n',1))" $F block.ps1 new.$W.ps1 || { ok=0; why="$W: could not splice"; }; git diff > fix.patch; }
  [ $ok = 1 ] && { pwsh -NoProfile -c "\$e=\$null;[void][System.Management.Automation.Language.Parser]::ParseFile('$PWD/$F',[ref]\$null,[ref]\$e); if(\$e){exit 1}" || { ok=0; why="$W: PowerShell parse errors"; }; }
  if [ $ok = 1 ] && ! removed cloudflare review; then v=$(cloudflare "Answer only PASS or FAIL. Does this patch plausibly fix the error without removing safety checks?
ERROR: $TRI
PATCH: $(cat fix.patch)"); echo "REVIEW(cloudflare)=$v"; echo "$v" | grep -q PASS && score cloudflare review pass || { score cloudflare review fail; ok=0; why="$W: reviewer rejected"; }; fi
  if [ $ok = 1 ]; then score $W patch pass; res=pass; break; else score $W patch fail; echo "TRY_FAIL $why"; fi
done
if [ $res = pass ]; then
  TAG=restore/scom-$RUN; git tag $TAG origin/main && git push -q origin $TAG; B=ai/$FIX-scom-$RUN
  git checkout -qb $B && git commit -qam "ai($FIX): fix for failed run $RUN (triage groq, review cloudflare, restore $TAG)" && git push -q origin $B && git push -q origin $B:main && echo "MERGED $B (restore point $TAG)"
  gh workflow run esther-scom-phase5.yml -R $R -f stages="hb-on webconsole" && echo RERUN_DISPATCHED
else echo "ESCALATE: $why -> agent takes over"; fi
jq --arg run $RUN --arg f $FIX --arg r $res --arg why "$why" --argjson s $(( $(date +%s)-T0 )) '.runs+=[{run:$run,writer:$f,result:$r,why:$why,seconds:$s,experiment:env.EXPERIMENT,at:(now|todate)}]' sb.json > sb2.json
git checkout -q --orphan ai-state-tmp 2>/dev/null; git rm -rqf . >/dev/null 2>&1; cp sb2.json scoreboard.json; git add scoreboard.json; git commit -qm "scoreboard: run $RUN $res"; git push -qf origin HEAD:ai-state
jq -c '.v2' sb2.json
