#!/usr/bin/env bash
# Renders one lesson in a single encode: scene PNGs (each held for its narration part's length) + concatenated narration FLACs
# -> burned Hebrew subtitles. Slides are static, so 10 fps is enough (subtitle timing resolution 0.1 s).
set -euo pipefail
L=$1; SRC=$2; OUT=$3; NAME=$4; FPS=${RENDER_FPS:-10}
W=$(mktemp -d); : > $W/img.txt; : > $W/aud.txt; total=0
for i in 01 02 03 04 05 06 07 08; do
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 $SRC/$L-$i.flac)
  printf "file '%s'\nduration %s\n" "$(realpath $SRC/$L-scene-$i.png)" "$d" >> $W/img.txt
  printf "file '%s'\n" "$(realpath $SRC/$L-$i.flac)" >> $W/aud.txt
  total=$(python3 -c "print($total+$d)")
done
printf "file '%s'\n" "$(realpath $SRC/$L-scene-08.png)" >> $W/img.txt   # concat demuxer needs the last image repeated
ffmpeg -y -v error -f concat -safe 0 -i $W/img.txt -f concat -safe 0 -i $W/aud.txt \
  -vf "fps=$FPS,scale=1920:1080,format=yuv420p,subtitles=$OUT/$L.ass" -c:v libx264 -preset ${FINAL_PRESET:-veryfast} -crf 23 -tune stillimage \
  -c:a aac -b:a 128k -ar 48000 -t "$total" -movflags +faststart "$OUT/$NAME.mp4"
ffmpeg -v error -i "$OUT/$NAME.mp4" -f null - && echo "DECODE_OK $NAME"
echo "EXPECTED_DURATION $NAME $total"
ffprobe -v error -show_entries format=duration,size -of compact "$OUT/$NAME.mp4"
