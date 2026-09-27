# Live step status for the Estherdaxes Ops dashboard. Source it, then: ops_step N TOTAL "Hebrew step" "command" "Hebrew explanation"
# Writes status/<run>.json on the ops-status branch (GITHUB_TOKEN, contents: write). Never fails the caller.
# Secrets: values registered with ops_mask are replaced by *** ; SAS-like query strings are masked too.
OPS_MASKS=()
ops_mask() { for v in "$@"; do [ -n "$v" ] && OPS_MASKS+=("$v"); done; }
_ops_clean() { local s="$1" m; for m in "${OPS_MASKS[@]}"; do s="${s//"$m"/***}"; done
  printf '%s' "$s" | sed -E 's/(sig|se|sp|sv|st|skoid|sktid|ske|sks|skv|spr|sr|srt|ss)=[^& "]+/\1=***/g; s/(p|pw|password|key|token)=[^ "]+/\1=***/Ig'; }
ops_step() {
  [ -n "${GH_TOKEN:-}" ] && [ -n "${GITHUB_RUN_ID:-}" ] || return 0
  ( set +e
    local R="$GITHUB_REPOSITORY" n="$1" t="$2" label="$3" cmd expl="$5"; cmd=$(_ops_clean "$4")
    local body; body=$(jq -nc --arg run "$GITHUB_RUN_ID" --arg wf "$GITHUB_WORKFLOW" --argjson n "$n" --argjson t "$t" --arg l "$label" --arg c "$cmd" --arg e "$expl" --arg at "$(date -u +%FT%TZ)" \
      '{run:$run,workflow:$wf,step:$n,total:$t,label:$l,command:$c,explain:$e,at:$at}')
    # Stored as status/<run>.json on the ops-status branch (never main, so no deploy is triggered).
    if ! gh api "repos/$R/git/ref/heads/ops-status" >/dev/null 2>&1; then
      local sha; sha=$(gh api "repos/$R/git/ref/heads/main" -q .object.sha); gh api "repos/$R/git/refs" -f ref=refs/heads/ops-status -f sha="$sha" >/dev/null 2>&1; fi
    local f="status/$GITHUB_RUN_ID.json" old; old=$(gh api "repos/$R/contents/$f?ref=ops-status" -q .sha 2>/dev/null || true)
    local args=(-X PUT "repos/$R/contents/$f" -f message="ops status $GITHUB_RUN_ID step $n" -f branch=ops-status -f content="$(printf '%s' "$body" | base64 -w0)")
    [ -n "$old" ] && args+=(-f sha="$old")
    gh api "${args[@]}" >/dev/null 2>&1 || echo "[ops] status write failed"
    echo "[ops] $n/$t $label"
  ) || true
}
