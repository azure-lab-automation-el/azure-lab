#!/usr/bin/env bash
set -euo pipefail
export GH_TOKEN="${GH_TOKEN}"
export WHISPER_MODEL="${WHISPER_MODEL}"
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
export INPUT_SRC_TAG="${INPUT_SRC_TAG}"
export INPUT_OUT_TAG="${INPUT_OUT_TAG}"
ENTRY_FAILED=0
echo "-- (cache step dropped: Cache pip + Whisper model + rclone)"
echo "-- (cache step dropped: Cache subtitle timing (per-audio Whisper results))"
echo "== Tools =="
t0=$(date +%s)
command -v ffmpeg >/dev/null && fc-list | grep -qi dejavu && command -v zip >/dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq ffmpeg fonts-dejavu-core zip >/dev/null; }
pip install -q faster-whisper
echo "TOOLS_SECONDS=$(( $(date +%s)-t0 ))"
echo "== Source assets =="
export MEGA_EMAIL="${MEGA_EMAIL}"
export MEGA_PASSWORD="${MEGA_PASSWORD}"
mkdir -p src out qa; S="${INPUT_SRC_TAG}"
if [[ "$S" == mega:* ]]; then
  if [ ! -x ~/rclone-bin/rclone ]; then mkdir -p ~/rclone-bin; curl -fsSL -o /tmp/rc.zip https://downloads.rclone.org/v1.71.1/rclone-v1.71.1-linux-amd64.zip && unzip -qj /tmp/rc.zip '*/rclone' -d ~/rclone-bin; fi
  export RCLONE_CONFIG_MEGA_TYPE=mega RCLONE_CONFIG_MEGA_USER="$MEGA_EMAIL"; export RCLONE_CONFIG_MEGA_PASS="$(~/rclone-bin/rclone obscure "$MEGA_PASSWORD")"
  ~/rclone-bin/rclone copyto "$S" /tmp/inputs.tar && tar -xf /tmp/inputs.tar -C src
else
  gh release download "$S" -R "${GITHUB_REPOSITORY}" -D src
fi
ls src | wc -l
echo "== Subtitle timing =="
source scripts/lib/watchdog.sh 15 subtitles
t0=$(date +%s)
python3 scripts/lessons/align_ass.py L4 src out
python3 scripts/lessons/align_ass.py L5 src out
echo "SUBTITLES_SECONDS=$(( $(date +%s)-t0 ))"
echo "== Render =="
source scripts/lib/watchdog.sh 15 render
t0=$(date +%s)
# Both lessons in parallel; each keeps its own log so errors stay attributable.
scripts/lessons/render.sh L4 src out JFrog-Lesson-4-Cleanup-Policy-HE > /tmp/r4.log 2>&1 & p4=$!
scripts/lessons/render.sh L5 src out JFrog-Lesson-5-Smart-Archiving-HE > /tmp/r5.log 2>&1 & p5=$!
rc=0; wait $p4 || rc=1; wait $p5 || rc=1; cat /tmp/r4.log /tmp/r5.log
echo "RENDER_SECONDS=$(( $(date +%s)-t0 ))"; exit $rc
echo "== QA frames =="
for n in JFrog-Lesson-4-Cleanup-Policy-HE JFrog-Lesson-5-Smart-Archiving-HE; do
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 out/$n.mp4)
  for k in 1 2 3 4 5 6 7 8 9 10 11 12; do t=$(python3 -c "print(round($d*($k-0.5)/12,2))"); ffmpeg -y -v error -ss $t -i out/$n.mp4 -frames:v 1 -vf scale=640:-1 qa/$n-$k.png; done
done
cp out/*-align.json out/*.ass qa/
echo "== Bundle and publish =="
if [ "${INPUT_PUBLISH}" = "true" ]; then
cd out
zip -q -j JFrog-Lesson-4-Cleanup-Policy-HE.zip JFrog-Lesson-4-Cleanup-Policy-HE.mp4 L4.srt
zip -q -j JFrog-Lesson-5-Smart-Archiving-HE.zip JFrog-Lesson-5-Smart-Archiving-HE.mp4 L5.srt
sha256sum *.zip | tee SHA256SUMS.txt
gh release view "${INPUT_OUT_TAG}" -R "${GITHUB_REPOSITORY}" >/dev/null 2>&1 || gh release create "${INPUT_OUT_TAG}" -R "${GITHUB_REPOSITORY}" --title "${INPUT_OUT_TAG}" --notes "Finished lesson bundles (temporary; moved to MEGA then deleted)"
gh release upload "${INPUT_OUT_TAG}" -R "${GITHUB_REPOSITORY}" --clobber JFrog-Lesson-4-Cleanup-Policy-HE.zip JFrog-Lesson-5-Smart-Archiving-HE.zip
echo RENDER_OK
fi
