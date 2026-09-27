#!/usr/bin/env bash
set -euo pipefail
export GH_TOKEN="${GH_TOKEN}"
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
ENTRY_FAILED=0
echo "== step =="
curl -fsSL https://rclone.org/install.sh | sudo bash >/dev/null
echo "== step =="
export GH_TOKEN="${GH_TOKEN}"
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
set -euo pipefail; R=${GITHUB_REPOSITORY}
export RCLONE_CONFIG_MEGA_TYPE=mega RCLONE_CONFIG_MEGA_USER="$MEGA_EMAIL"; export RCLONE_CONFIG_MEGA_PASS="$(rclone obscure "$MEGA_PASSWORD")"
mkdir -p fin src; gh release download lesson-jfrog-l4-l5 -R $R -D fin; gh release download lesson-src-jfrog-l4-l5 -R $R -D src
rclone check fin mega:JFrog/L4-L5 --size-only --one-way
tar -cf L4-L5-render-inputs.tar -C src .; tar -tf L4-L5-render-inputs.tar | wc -l
rclone copy L4-L5-render-inputs.tar mega:JFrog/L4-L5-rebuild
rclone check . mega:JFrog/L4-L5-rebuild --size-only --one-way --include L4-L5-render-inputs.tar
echo MEGA_VERIFIED
gh release delete lesson-jfrog-l4-l5 -R $R --cleanup-tag -y
gh release delete lesson-src-jfrog-l4-l5 -R $R --cleanup-tag -y
gh release list -R $R; echo RELEASES_DELETED
rclone lsl mega:JFrog/L4-L5-rebuild
