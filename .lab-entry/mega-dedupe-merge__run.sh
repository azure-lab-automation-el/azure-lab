#!/usr/bin/env bash
set -euo pipefail
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
ENTRY_FAILED=0
echo "== step =="
curl -fsSL -o megacmd.deb https://mega.nz/linux/repo/xUbuntu_24.04/amd64/megacmd-xUbuntu_24.04_amd64.deb && sudo apt-get install -y -q ./megacmd.deb >/dev/null
curl -fsSL https://rclone.org/install.sh | sudo bash >/dev/null
echo "== step =="
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
set -euo pipefail
mega-login "$MEGA_EMAIL" "$MEGA_PASSWORD" >/dev/null
mega-ls -l //bin | head -20
if mega-ls /JFrog/L4-L5-rebuild/1-narration-L4-L5-flac.tar >/dev/null 2>&1; then echo "old tar already in place"; else mega-mv //bin/1-narration-L4-L5-flac.tar /JFrog/L4-L5-rebuild/ && echo RESTORED_FROM_RUBBISH || { echo RESTORE_FAILED; exit 1; }; fi
mega-ls -l /JFrog/L4-L5-rebuild
mega-logout >/dev/null || true
export RCLONE_CONFIG_MEGA_TYPE=mega RCLONE_CONFIG_MEGA_USER="$MEGA_EMAIL"; export RCLONE_CONFIG_MEGA_PASS="$(rclone obscure "$MEGA_PASSWORD")"
D=mega:JFrog/L4-L5-rebuild
rclone copy $D/1-narration-L4-L5-flac.tar old; rclone copy $D/L4-L5-render-inputs.tar cur
mkdir o n; tar -xf old/*.tar -C o; tar -xf cur/*.tar -C n
tar -tf cur/*.tar | grep -q 'L4-L5-narration-final.txt' && echo "TXT_ALREADY_IN_NEW" || cp "$(find o -name L4-L5-narration-final.txt)" n/
tar -cf merged.tar -C n .
rclone copyto merged.tar $D/L4-L5-render-inputs.v2.tar
rclone copyto $D/L4-L5-render-inputs.v2.tar back.tar
cmp merged.tar back.tar && tar -tf back.tar | grep -c . && tar -tf back.tar | grep -q 'L4-L5-narration-final.txt' && echo V2_VERIFIED || { echo V2_CHECK_FAILED; exit 1; }
rclone deletefile $D/L4-L5-render-inputs.tar
rclone moveto $D/L4-L5-render-inputs.v2.tar $D/L4-L5-render-inputs.tar
rclone deletefile $D/1-narration-L4-L5-flac.tar && echo OLD_TAR_TO_RUBBISH
rclone lsl $D
