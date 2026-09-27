#!/usr/bin/env bash
# P6 free-allowance calc through the model pipeline. Identifiers stripped before any model sees data.
set -uo pipefail
R=$GITHUB_REPOSITORY; SRC=$1; T0=$(date +%s)
gh run view $SRC -R $R --log | cut -f3- | cut -c30- | sed -n '/^== DISKS/,/^== USAGE THIS MONTH/p' | grep -v '36;1m' \
 | sed -E 's#/subscriptions/[^ \t]*##g; s/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<id>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/<email>/g' > raw.txt
wc -l raw.txt
groq() { jq -n --arg t "$1" '{model:"openai/gpt-oss-120b",temperature:0,messages:[{role:"user",content:$t}]}' | curl -sS https://api.groq.com/openai/v1/chat/completions -H "Authorization: Bearer $GROQ_API_KEY" -H 'Content-Type: application/json' -d @- | jq -r '.choices[0].message.content // .error.message'; }
cloudflare() { jq -n --arg t "$1" '{messages:[{role:"user",content:$t}],max_tokens:1500}' | curl -sS "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/ai/run/@cf/meta/llama-3.3-70b-instruct-fp8-fast" -H "Authorization: Bearer $CF_API_TOKEN" -H 'Content-Type: application/json' -d @- | jq -r '.result.response // .errors'; }
NOW=$(date -u +%FT%TZ)
TAB=$(groq "Lab Azure data below (disk list, disk write events, VM start/deallocate events, cost meters). Disks are Premium_LRS (P6) only while their VM runs; deallocate switches them to Standard. Produce ONLY a CSV with header disk,start_utc,end_utc listing every interval this calendar month (from $(date -u +%Y-%m-01)T00:00:00Z) during which each disk was Premium, using VM start as start and deallocate as end; an interval still running ends at $NOW. No prose.
$(cat raw.txt)")
printf '%s\n' "$TAB" | sed '/^```/d' > intervals.csv; echo "== groq table"; cat intervals.csv
CODE=$(cd /tmp && timeout 300 copilot --model auto -p "Write ONLY a python3 script (no prose, no fences) that reads intervals.csv (header disk,start_utc,end_utc, ISO8601 UTC) and prints: total Premium hours per disk, the sum of all hours, and P6_DISK_MONTHS=<sum/720 rounded to 3 decimals>. It must also print PROJECTED=<value> where value = P6_DISK_MONTHS + (hours from $NOW to $(date -u -d "$(date -u +%Y-%m-01) +1 month" +%FT%TZ) for one new always-on disk)/720 + existing disks projected at their average daily Premium hours so far for the rest of the month /720. Handle Z suffixes." 2>/dev/null)
printf '%s\n' "$CODE" | sed '/^```/d' > calc.py; echo "== copilot script"; cat calc.py
python3 calc.py | tee calc.out || echo CALC_FAILED
V=$(cloudflare "Answer PASS or FAIL then one line why. Free allowance is 2.0 P6 disk-months per month. Is this calculation consistent with the interval table, and is PROJECTED below 2.0?
TABLE:
$(cat intervals.csv)
OUTPUT:
$(cat calc.out 2>/dev/null)")
echo "REVIEW(cloudflare)=$V"; echo "SECONDS=$(( $(date +%s)-T0 ))"
