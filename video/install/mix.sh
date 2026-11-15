#!/usr/bin/env bash
# Notchy install & setup video: render the silent compositions, mix VO + ducked music, loudness-normalise
# (-14 LUFS integrated, true peak <= -1 dBTP) and export the final MP4s to ~/Desktop/Notchy-Launch-Kit.
#
#   video/install/mix.sh            # render + mix both aspects
#   SKIP_RENDER=1 video/install/mix.sh   # re-mix using existing silent renders
#
# Needs: ffmpeg, node 22+, video/.venv (see video/README.md), VO in video/audio/vo-install/
# (python video/install/vo.py), music in video/audio/music-install.wav (video/audio/make-music.py),
# footage intermediates in video/install/media/ (video/install/make-media.sh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PY="${PY:-$REPO/video/.venv/bin/python}"
[[ -x "$PY" ]] || PY=/tmp/kokoro-venv/bin/python   # legacy fallback
WORK="$HERE/renders"
KIT="$HOME/Desktop/Notchy-Launch-Kit"
mkdir -p "$WORK" "$KIT/review"

python3 "$HERE/build.py"

for A in 16x9 9x16; do
  if [[ -z "${SKIP_RENDER:-}" ]]; then
    (cd "$HERE/comp-$A" && npx -y hyperframes@0.9.52 render --quality high --fps 30 --output "$WORK/silent-$A.mp4")
  fi
  "$PY" "$HERE/mix.py" "$A" "$WORK"

  PRE="acompressor=threshold=-20dB:ratio=2.5:attack=12:release=220:makeup=2"
  # pass 1: measure
  J=$(ffmpeg -hide_banner -nostats -i "$WORK/premix-$A.wav" \
      -af "$PRE,loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json" -f null - 2>&1 | sed -n '/^{/,/^}/p')
  get() { echo "$J" | python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }
  # pass 2: linear normalisation with measured values, then a safety limiter
  ffmpeg -y -v error -i "$WORK/premix-$A.wav" -af "$PRE,loudnorm=I=-14:TP=-1.5:LRA=11:linear=true:\
measured_I=$(get input_i):measured_TP=$(get input_tp):measured_LRA=$(get input_lra):\
measured_thresh=$(get input_thresh):offset=$(get target_offset),aresample=48000,\
alimiter=limit=0.85:attack=2:release=60:level=false" -ar 48000 -c:a pcm_s24le "$WORK/final-$A.wav"

  ffmpeg -y -v error -i "$WORK/silent-$A.mp4" -i "$WORK/final-$A.wav" -map 0:v:0 -map 1:a:0 \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -r 30 -profile:v high -movflags +faststart \
    -c:a aac -b:a 192k -ar 48000 -shortest "$KIT/Notchy-Install-$A.mp4"
  echo "== $A"; ffmpeg -hide_banner -nostats -i "$KIT/Notchy-Install-$A.mp4" -af ebur128=peak=true -f null - 2>&1 \
    | sed -n '/Summary/,$p' | grep -E "I:|Peak:"
done

# voice-only review file (16:9 timeline) for a pronunciation check
ffmpeg -y -v error -i "$WORK/vo-16x9.wav" -af "loudnorm=I=-16:TP=-1.5" -ar 48000 -c:a aac -b:a 192k \
  "$KIT/review/install-voice.m4a"
echo "done -> $KIT"
