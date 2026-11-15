#!/bin/bash
# Render the cover/thumbnail/banner HTML files to PNG with headless Chrome, plus 25% previews for the
# legibility check and one contact sheet (review/covers-overview.png).
# Usage: video/covers/render.sh [out_dir]   (default out_dir: ~/Desktop/Notchy-Launch-Kit)
# The UI cutouts in media/ are committed; rebuild them from the footage with make-media.py if needed.
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-$HOME/Desktop/Notchy-Launch-Kit}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SPECS=(
  thumbnail-linkedin-1920x1080:1920,1080
  thumbnail-linkedin-install-1920x1080:1920,1080
  banner-linkedin-1584x396:1584,396
  post-linkedin-1200x627:1200,627
  cover-instagram-reel-1080x1920:1080,1920
  cover-instagram-reel-install-1080x1920:1080,1920
  cover-instagram-feed-1080x1350:1080,1350
  post-instagram-square-1080x1080:1080,1080
)
mkdir -p png preview "$OUT/review"
for spec in "${SPECS[@]}"; do
  name="${spec%%:*}"; size="${spec##*:}"; w="${size%%,*}"; h="${size##*,}"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size="$size" --virtual-time-budget=2000 --screenshot="$PWD/png/$name.png" "file://$PWD/$name.html" 2>/dev/null
  got="$(sips -g pixelWidth -g pixelHeight "png/$name.png" | awk '/pixel/{printf $2" "}')"
  [ "$got" = "$w $h " ] || { echo "SIZE MISMATCH $name: $got" >&2; exit 1; }
  sips -Z $(( (w > h ? w : h) / 4 )) "png/$name.png" --out "preview/$name-25.png" >/dev/null
  cp "png/$name.png" "$OUT/$name.png"
  echo "$name -> $OUT/$name.png ($w x $h)"
done

# Contact sheet of all eight (a small HTML page, screenshotted the same way).
SHEET="$PWD/preview/_overview.html"
cat > "$SHEET" <<'HTML'
<!doctype html><html><head><meta charset="UTF-8"><style>
body{margin:0;background:#16181D;font-family:-apple-system,"Helvetica Neue",sans-serif;color:#AEB7C7;width:2400px;height:1500px;overflow:hidden}
.g{position:absolute} .g img{display:block;box-shadow:0 0 0 1px #333a46} .g p{margin:8px 0 0;font-size:18px}
h1{position:absolute;left:40px;top:18px;margin:0;font-size:26px;color:#F5F7FA;font-weight:700}
</style></head><body><h1>Notchy launch covers</h1>
<div class="g" style="left:40px;top:70px"><img src="../png/thumbnail-linkedin-1920x1080.png" width="640"><p>thumbnail-linkedin-1920x1080</p></div>
<div class="g" style="left:40px;top:470px"><img src="../png/thumbnail-linkedin-install-1920x1080.png" width="640"><p>thumbnail-linkedin-install-1920x1080</p></div>
<div class="g" style="left:40px;top:870px"><img src="../png/post-linkedin-1200x627.png" width="640"><p>post-linkedin-1200x627</p></div>
<div class="g" style="left:40px;top:1260px"><img src="../png/banner-linkedin-1584x396.png" width="800"><p>banner-linkedin-1584x396</p></div>
<div class="g" style="left:740px;top:70px"><img src="../png/cover-instagram-reel-1080x1920.png" width="420"><p>cover-instagram-reel-1080x1920</p></div>
<div class="g" style="left:1190px;top:70px"><img src="../png/cover-instagram-reel-install-1080x1920.png" width="420"><p>cover-instagram-reel-install-1080x1920</p></div>
<div class="g" style="left:1640px;top:70px"><img src="../png/cover-instagram-feed-1080x1350.png" width="420"><p>cover-instagram-feed-1080x1350</p></div>
<div class="g" style="left:1640px;top:650px"><img src="../png/post-instagram-square-1080x1080.png" width="420"><p>post-instagram-square-1080x1080</p></div>
</body></html>
HTML
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=2400,1500 --virtual-time-budget=2000 --screenshot="$OUT/review/covers-overview.png" "file://$SHEET" 2>/dev/null
rm -f "$SHEET"
echo "overview -> $OUT/review/covers-overview.png"
