#!/usr/bin/env bash
set -euo pipefail
export INPUT_SCENARIO="${INPUT_SCENARIO}"
ENTRY_FAILED=0
echo "-- (cache step dropped: Reuse unchanged recording)"
echo "-- (cache step dropped: Cache Playwright browser)"
echo "== Start Artifactory OSS =="
source scripts/lib/watchdog.sh 8 artifactory-start
# Recent Artifactory 7.x needs an external DB: throwaway PostgreSQL on the same runner.
# Browser + ffmpeg install runs in the background while Artifactory boots (the Record step waits for it).
( npm i --no-save playwright@1 && npx playwright install --with-deps chromium && sudo apt-get install -y -qq ffmpeg ) > /tmp/tools.log 2>&1 && touch /tmp/tools.ok &
docker pull -q postgres:16-alpine >/dev/null & a=$!; docker pull -q releases-docker.jfrog.io/jfrog/artifactory-oss:latest >/dev/null & b=$!; wait $a $b
docker network create jf
docker run -d --name pg --network jf -e POSTGRES_USER=artifactory -e POSTGRES_PASSWORD=lab-only-pw -e POSTGRES_DB=artifactory postgres:16-alpine
sleep 8
docker run -d --name rt --network jf -p 8082:8082 -p 8081:8081 \
  -e JF_SHARED_DATABASE_TYPE=postgresql -e JF_SHARED_DATABASE_DRIVER=org.postgresql.Driver \
  -e JF_SHARED_DATABASE_URL=jdbc:postgresql://pg:5432/artifactory -e JF_SHARED_DATABASE_USERNAME=artifactory -e JF_SHARED_DATABASE_PASSWORD=lab-only-pw \
  releases-docker.jfrog.io/jfrog/artifactory-oss:latest
up=0
for i in $(seq 1 48); do
  for u in http://localhost:8082/artifactory/api/system/ping http://localhost:8081/artifactory/api/system/ping; do
    s=$(curl -s -o /dev/null -w '%{http_code}' $u || true); [ "$s" = 200 ] && { echo "RT_UP after $((i*10))s via $u"; up=1; break 2; }
  done
  [ $((i % 6)) = 0 ] && { echo "--- $((i*10))s: container=$(docker inspect -f '{{.State.Status}}' rt)"; docker logs --tail 5 rt 2>&1 | cut -c1-200; }
  sleep 10
done
if [ $up != 1 ]; then echo RT_NOT_UP; docker logs --tail 120 rt 2>&1 | cut -c1-300; exit 1; fi
curl -s http://localhost:8082/artifactory/api/system/version || curl -s http://localhost:8081/artifactory/api/system/version
# The UI goes through the router on 8082; wait until router health and /ui/ are ready (up to 10 min).
for i in $(seq 1 60); do
  h=$(curl -s http://localhost:8082/router/api/v1/system/health | tr -d '\n' | grep -o '"state" *: *"[A-Z]*"' | head -1)
  u=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8082/ui/ || true)
  case "$h" in *HEALTHY*) [ "$u" = 200 ] && { echo "UI_UP after $((i*10))s ($h ui=$u)"; break; };; esac
  [ $((i % 6)) = 0 ] && echo "--- ui wait $((i*10))s: health=$h ui=$u"
  sleep 10
done
echo "== Seed demo data (REST) =="
bash scripts/jfrog-rec/seed.sh
echo "== Record =="
source scripts/lib/watchdog.sh 22 record
for i in $(seq 1 60); do [ -f /tmp/tools.ok ] && break; pgrep -f "playwright|apt-get|npm" >/dev/null || { cat /tmp/tools.log; echo TOOLS_FAIL; exit 1; }; sleep 5; done; [ -f /tmp/tools.ok ] || { tail -30 /tmp/tools.log; echo TOOLS_TIMEOUT; exit 1; }
node scripts/jfrog-rec/${INPUT_SCENARIO}.mjs
t0=$(date +%s)
for f in out/*.webm; do
  # Trim any leading loading-spinner frames: start 1s before the first bright (UI) frame.
  t0=$(ffmpeg -v info -i "$f" -vf "fps=2,signalstats,metadata=print:key=lavfi.signalstats.YAVG" -f null - 2>&1 | awk '/pts_time/{match($0,/pts_time:[0-9.]+/);t=substr($0,RSTART+9,RLENGTH-9)} /YAVG=/{split($0,a,"=");if(a[2]+0>120){print t;exit}}')
  ss=$(python3 -c "print(max(0,float('${t0:-0}')-1))"); echo "TRIM_START $ss"
  # Also cut any mid-video loading-spinner stretch (dark frames, YAVG<120) so only real UI remains.
  ffmpeg -v error -y -ss "$ss" -i "$f" -vf "scale=1920:1080,signalstats,metadata=select:key=lavfi.signalstats.YAVG:value=120:function=greater,setpts=N/FRAME_RATE/TB" -an -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -movflags +faststart "${f%.webm}.mp4"
  rm -f "$f"
done
echo "ENCODE_SECONDS=$(( $(date +%s)-t0 ))"; ls -la out
ls out/*.mp4 >/dev/null && ! ls out/fail.png >/dev/null 2>&1 && echo RECORD_OK
echo "-- (cache step dropped: Save recording for reuse)"
echo "== step =="
echo "REUSED unchanged recording (scenario/seed/workflow identical); set force=true to re-record"; ls -la out
