#!/usr/bin/env bash
set -euo pipefail
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
export INPUT_BUNDLE_B64="${INPUT_BUNDLE_B64}"
ENTRY_FAILED=0
echo "-- (cache step dropped: Cache rclone)"
echo "== Install rclone (pinned, cached) =="
if [ ! -x ~/rclone-bin/rclone ]; then mkdir -p ~/rclone-bin; curl -fsSL -o /tmp/rc.zip https://downloads.rclone.org/v1.71.1/rclone-v1.71.1-linux-amd64.zip && unzip -qj /tmp/rc.zip '*/rclone' -d ~/rclone-bin; fi
echo ~/rclone-bin >> $GITHUB_PATH
export PATH="$HOME/rclone-bin:$PATH"
echo "== Verify bundle and upload to MEGA =="
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
export B64="${INPUT_BUNDLE_B64}"
set -euo pipefail
f="azure-lab-toolchain-$(date -u +%F).bundle"
echo "$B64" | base64 -d > "$f"
git bundle verify "$f"
export RCLONE_CONFIG_MEGA_TYPE=mega RCLONE_CONFIG_MEGA_USER="$MEGA_EMAIL"
export RCLONE_CONFIG_MEGA_PASS="$(rclone obscure "$MEGA_PASSWORD")"
D=mega:Backups/azure-lab-toolchain
rclone copy "$f" "$D"
rclone check . "$D" --include "$f" --size-only --one-way && echo BACKUP_UPLOAD_OK
rclone lsl "$D"
