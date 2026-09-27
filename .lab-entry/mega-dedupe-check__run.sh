#!/usr/bin/env bash
set -euo pipefail
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
ENTRY_FAILED=0
echo "== step =="
curl -fsSL https://rclone.org/install.sh | sudo bash >/dev/null
echo "== step =="
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
set -euo pipefail
export RCLONE_CONFIG_MEGA_TYPE=mega RCLONE_CONFIG_MEGA_USER="$MEGA_EMAIL"; export RCLONE_CONFIG_MEGA_PASS="$(rclone obscure "$MEGA_PASSWORD")"
D=mega:JFrog/L4-L5-rebuild; rclone copy $D/1-narration-L4-L5-flac.tar old; rclone copy $D/L4-L5-render-inputs.tar new
mkdir o n; tar -xf old/*.tar -C o; tar -xf new/*.tar -C n
echo "== old contents"; (cd o && find . -type f | sort | xargs sha256sum) | tee old.sum
(cd n && find . -type f -name '*.flac' | sort | xargs sha256sum) > new.sum
same=1; while read -r h f; do b=$(basename "$f"); case "$b" in *.flac) ;; *) echo "NON_FLAC_IN_OLD $f"; same=0; continue;; esac
  nh=$(grep " \./$b$\| .*/$b$" new.sum | awk '{print $1}' | head -1); if [ "$h" = "$nh" ]; then echo "SAME $b"; else echo "DIFF $b old=$h new=${nh:-missing}"; same=0; fi; done < old.sum
if [ $same = 1 ]; then rclone deletefile $D/1-narration-L4-L5-flac.tar && echo OLD_TAR_TO_RUBBISH; else echo KEPT_OLD_TAR; fi
rclone lsl $D
