#!/usr/bin/env bash
# Plain (unencrypted) mirror backup of the repo to MEGA, verified by round-trip hash. His private storage, his call (12:25).
set -euo pipefail
: "${GH_TOKEN:?}" "${MEGA_EMAIL:?}" "${MEGA_PASSWORD:?}" "${GITHUB_REPOSITORY:?}"
TS=$(date -u +%Y%m%d-%H%M%S); F="repo-mirror-$TS.tgz"
echo "== mirror clone"
git clone --quiet --mirror "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" mirror.git
tar czf "$F" mirror.git
sha256sum "$F" | awk '{print $1}' > /tmp/local.sha; echo "local sha256: $(cat /tmp/local.sha)  bytes: $(stat -c%s "$F")"
echo "== rclone -> MEGA"
mkdir -p /tmp/rcbin
curl -fsSL -o /tmp/rc.zip https://downloads.rclone.org/v1.71.1/rclone-v1.71.1-linux-amd64.zip
unzip -qj /tmp/rc.zip '*/rclone' -d /tmp/rcbin; export PATH="/tmp/rcbin:$PATH"
export RCLONE_CONFIG_MEGA_TYPE=mega RCLONE_CONFIG_MEGA_USER="$MEGA_EMAIL" RCLONE_CONFIG_MEGA_PASS="$(rclone obscure "$MEGA_PASSWORD")"
rclone copy "$F" mega:Backups/repo-mirrors/
echo "== verify round-trip"
rclone cat "mega:Backups/repo-mirrors/$F" | sha256sum | awk '{print $1}' > /tmp/remote.sha
cmp /tmp/local.sha /tmp/remote.sha
echo "MIRROR_BACKUP_VERIFIED mega:Backups/repo-mirrors/$F"
