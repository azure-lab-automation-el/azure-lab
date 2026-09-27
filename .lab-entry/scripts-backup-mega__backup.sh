#!/usr/bin/env bash
set -euo pipefail
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
ENTRY_FAILED=0
echo "-- (cache step dropped: Cache rclone)"
echo "== Install rclone (pinned, cached) =="
if [ ! -x ~/rclone-bin/rclone ]; then mkdir -p ~/rclone-bin; curl -fsSL -o /tmp/rc.zip https://downloads.rclone.org/v1.71.1/rclone-v1.71.1-linux-amd64.zip && unzip -qj /tmp/rc.zip '*/rclone' -d ~/rclone-bin; fi
echo ~/rclone-bin >> $GITHUB_PATH
export PATH="$HOME/rclone-bin:$PATH"
echo "== Bundle and upload =="
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
set -euo pipefail
export RCLONE_CONFIG_MEGA_TYPE=mega RCLONE_CONFIG_MEGA_USER="$MEGA_EMAIL"
export RCLONE_CONFIG_MEGA_PASS="$(rclone obscure "$MEGA_PASSWORD")"
f="azure-lab-automation-$(date -u +%F).bundle"
git bundle create "$f" --all && git bundle verify "$f" >/dev/null
D=mega:Backups/azure-lab-automation
rclone copy "$f" "$D"
rclone check . "$D" --include "$f" --size-only --one-way && echo BACKUP_UPLOAD_OK
# retention: keep newest 8; rclone's MEGA backend moves deletions to the rubbish bin unless --mega-hard-delete is set
rclone lsf "$D" --include '*.bundle' | sort -r | tail -n +9 | while read -r old; do rclone deletefile "$D/$old"; echo "moved to rubbish: $old"; done
rclone lsl "$D"
