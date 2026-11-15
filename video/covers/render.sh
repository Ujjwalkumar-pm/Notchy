#!/bin/bash
# Render the cover HTML files to PNG with headless Chrome, plus 25% previews for the legibility check.
# Usage: video/covers/render.sh [out_dir]   (default out_dir: ~/Desktop/Notchy-Launch-Kit)
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-$HOME/Desktop/Notchy-Launch-Kit}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p png preview "$OUT"
for spec in thumbnail-linkedin-1920x1080:1920,1080 cover-instagram-reel-1080x1920:1080,1920 cover-instagram-feed-1080x1350:1080,1350; do
  name="${spec%%:*}"; size="${spec##*:}"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size="$size" --virtual-time-budget=2000 --screenshot="$PWD/png/$name.png" "file://$PWD/$name.html" 2>/dev/null
  w="${size%%,*}"
  sips -Z $(( (w > ${size##*,} ? w : ${size##*,}) / 4 )) "png/$name.png" --out "preview/$name-25.png" >/dev/null
  cp "png/$name.png" "$OUT/$name.png"
  echo "$name -> $OUT/$name.png ($(sips -g pixelWidth -g pixelHeight "png/$name.png" | awk '/pixel/{printf $2" "}'))"
done
