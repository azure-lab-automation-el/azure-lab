#!/usr/bin/env bash
set -euo pipefail
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
export GH_TOKEN="${GH_TOKEN}"
export INPUT_TAG="${INPUT_TAG}"
export INPUT_MEGA_PATH="${INPUT_MEGA_PATH}"
ENTRY_FAILED=0
echo "== Check secrets =="
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
[ -n "$MEGA_EMAIL" ] || { echo "MEGA_EMAIL missing"; exit 1; }
[ -n "$MEGA_PASSWORD" ] || { echo "MEGA_PASSWORD missing - add it under Settings > Secrets > Actions"; exit 1; }
echo "== Download release assets =="
export GH_TOKEN="${GH_TOKEN}"
mkdir -p out
gh release download "${INPUT_TAG}" -R "${GITHUB_REPOSITORY}" -D out
ls -la out
echo "-- (cache step dropped: Cache rclone)"
echo "== Install rclone (pinned, cached) =="
if [ ! -x ~/rclone-bin/rclone ]; then mkdir -p ~/rclone-bin; curl -fsSL -o /tmp/rc.zip https://downloads.rclone.org/v1.71.1/rclone-v1.71.1-linux-amd64.zip && unzip -qj /tmp/rc.zip '*/rclone' -d ~/rclone-bin; fi
echo ~/rclone-bin >> $GITHUB_PATH; ~/rclone-bin/rclone version | head -1
export PATH="$HOME/rclone-bin:$PATH"
echo "== Upload to MEGA (parallel) =="
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
export RCLONE_CONFIG_MEGA_TYPE=mega
export RCLONE_CONFIG_MEGA_USER="$MEGA_EMAIL"
export RCLONE_CONFIG_MEGA_PASS="$(rclone obscure "$MEGA_PASSWORD")"
rclone copy out "mega:${INPUT_MEGA_PATH}" --transfers 4 --stats-one-line --stats 10s
echo "== verify"
rclone lsl "mega:${INPUT_MEGA_PATH}"
rclone check out "mega:${INPUT_MEGA_PATH}" --size-only --one-way && echo MEGA_UPLOAD_OK
echo "== Delete the temp release (only after MEGA verify passed) =="
export GH_TOKEN="${GH_TOKEN}"
gh release delete "${INPUT_TAG}" -R "${GITHUB_REPOSITORY}" --yes --cleanup-tag && echo TEMP_RELEASE_DELETED
