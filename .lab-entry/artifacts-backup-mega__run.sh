#!/usr/bin/env bash
set -euo pipefail
export GH_TOKEN="${GH_TOKEN}"
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
export INPUT_DELETE_NAMES="${INPUT_DELETE_NAMES}"
ENTRY_FAILED=0
echo "-- (cache step dropped: Cache rclone)"
echo "== Install rclone =="
if [ ! -x ~/rclone-bin/rclone ]; then mkdir -p ~/rclone-bin; curl -fsSL -o /tmp/rc.zip https://downloads.rclone.org/v1.71.1/rclone-v1.71.1-linux-amd64.zip && unzip -qj /tmp/rc.zip '*/rclone' -d ~/rclone-bin; fi
echo ~/rclone-bin >> $GITHUB_PATH
export PATH="$HOME/rclone-bin:$PATH"
echo "== Backup, verify, delete =="
export GH_TOKEN="${GH_TOKEN}"
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
export DEL="${INPUT_DELETE_NAMES}"
export R="${GITHUB_REPOSITORY}"
set -euo pipefail
export RCLONE_CONFIG_MEGA_TYPE=mega RCLONE_CONFIG_MEGA_USER="$MEGA_EMAIL"
export RCLONE_CONFIG_MEGA_PASS="$(rclone obscure "$MEGA_PASSWORD")"
D=mega:Backups/actions-artifacts; mkdir -p out
gh api --paginate "repos/$R/actions/artifacts?per_page=100" -q '.artifacts[]|select(.expired|not)|[.id,.name,.workflow_run.id]|@tsv' > list.tsv
echo "artifacts: $(wc -l < list.tsv)"
declare -A WF
while IFS=$'\t' read -r id name run; do
  [ -n "${WF[$run]:-}" ] || WF[$run]=$(gh api repos/$R/actions/runs/$run -q .name 2>/dev/null || echo unknown-workflow)
  mkdir -p "out/${WF[$run]}"; gh api "repos/$R/actions/artifacts/$id/zip" > "out/${WF[$run]}/$id-$name.zip"
  echo -e "$id\t$name\t${WF[$run]}/$id-$name.zip" >> map.tsv
done < list.tsv
echo "downloaded: $(find out -name '*.zip' | wc -l) files, $(du -sm out | cut -f1) MB"
rclone copy out "$D" --transfers 4
rclone check out "$D" --size-only --one-way && echo ARTIFACTS_BACKUP_OK
ok=0; del=0; freed=0
while IFS=$'\t' read -r id name path; do
  local_sz=$(stat -c %s "out/$path"); remote_sz=$(rclone size "$D/$path" --json | jq .bytes)
  if [ "$local_sz" = "$remote_sz" ]; then ok=$((ok+1)); else echo "VERIFY_FAIL $path $local_sz vs $remote_sz"; continue; fi
  if [ -n "$DEL" ] && echo ",$DEL," | grep -q ",$name,"; then
    sz=$(gh api repos/$R/actions/artifacts/$id -q .size_in_bytes); gh api -X DELETE repos/$R/actions/artifacts/$id && del=$((del+1)) && freed=$((freed+sz)); fi
done < map.tsv
echo "VERIFIED=$ok DELETED=$del FREED_MB=$((freed/1048576))"
