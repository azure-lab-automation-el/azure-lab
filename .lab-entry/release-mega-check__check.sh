#!/usr/bin/env bash
set -euo pipefail
export GH_TOKEN="${GH_TOKEN}"
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
ENTRY_FAILED=0
echo "== step =="
export GH_TOKEN="${GH_TOKEN}"
for t in lesson-jfrog-l4-l5 lesson-src-jfrog-l4-l5; do echo "== $t"; gh release view $t -R ${GITHUB_REPOSITORY} --json assets -q '.assets[]|"\(.size) \(.name)"'; done
mkdir -p a; gh release download lesson-jfrog-l4-l5 -R ${GITHUB_REPOSITORY} -D a
echo "== step =="
curl -fsSL https://rclone.org/install.sh | sudo bash >/dev/null
echo "== step =="
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
export RCLONE_CONFIG_MEGA_TYPE=mega RCLONE_CONFIG_MEGA_USER="$MEGA_EMAIL"; export RCLONE_CONFIG_MEGA_PASS="$(rclone obscure "$MEGA_PASSWORD")"
rclone check a mega:JFrog/L4-L5 --size-only --one-way && echo FINAL_IN_MEGA_OK
echo "== MEGA JFrog tree"; rclone lsl mega:JFrog | head -60
