#!/usr/bin/env python3
"""Cut the real Notchy panels out of the capture stills as transparent PNGs for the covers.

Usage: /opt/homebrew/bin/python3.12 video/covers/make-media.py   (needs Pillow; footage stills must exist)
Each cutout is the black panel exactly as captured (2x, demo data), with its real rounded corners
recovered from the wallpaper around it. Top edge stays square: it sits flush with the screen top.
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

HERE = Path(__file__).resolve().parent
FOOT = HERE.parent / "footage"
OUT = HERE / "media"

# name: (still, box x0, y0, x1, y1, radius, round_top)
CUTS = {
    # approval card + now playing, card settled, no pointer, no product names other than demo data
    "panel-approval": ("approval-card-still/frame-00076.png", None, 0, None, None, None, False),
    "panel-music": ("music-playing-loop/still.png", None, 0, None, None, None, False),
    "panel-meeting": ("banner-meeting/still.png", None, 0, None, None, None, False),
    # welcome window, step 2 "Allow what you use" (a real window under the notch)
    "window-welcome-allow": ("welcome-2-permissions/still.png", 820, 90, 1740, 1010, None, True),
}


def dark(px):
    return max(px[:3]) < 14


def panel_box(im):
    """Black panel attached to the top edge, centred on the still."""
    w, h = im.size
    cx = w // 2
    # bottom: scan the centre column up from the bottom to the first panel pixel
    yb = h - 1
    while yb > 0 and not dark(im.getpixel((cx, yb))):
        yb -= 1
    # sides: scan inward from both edges on a row clear of the rounded corners and the menu bar
    y = max(90, yb - 70)
    x0 = 0
    while x0 < cx and not dark(im.getpixel((x0, y))):
        x0 += 1
    x1 = w - 1
    while x1 > cx and not dark(im.getpixel((x1, y))):
        x1 -= 1
    return x0, 0, x1 + 1, yb + 1


def best_radius(im, box, round_top):
    x0, y0, x1, y1 = box
    best, best_err = 20, 1e18
    crop = im.crop(box).convert("L")
    dk = crop.point(lambda v: 255 if v < 14 else 0)
    for r in range(8, 90, 2):
        m = rounded_mask(crop.size, r, round_top, 1)
        err = sum(ImageChops.difference(m, dk).crop((0, crop.size[1] - 100, 100, crop.size[1])).get_flattened_data())
        if err < best_err:
            best, best_err = r, err
    return best


def rounded_mask(size, r, round_top, ss=4):
    w, h = size
    m = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (0, 0, w * ss - 1, h * ss - 1), radius=r * ss, fill=255,
        corners=(round_top, round_top, True, True))
    return m.resize((w, h), Image.LANCZOS) if ss > 1 else m


def main():
    OUT.mkdir(exist_ok=True)
    for name, (src, bx0, by0, bx1, by1, r, round_top) in CUTS.items():
        im = Image.open(FOOT / src).convert("RGB")
        box = (bx0, by0, bx1, by1) if bx0 is not None else panel_box(im)
        if r is None:
            r = best_radius(im, box, round_top)
        crop = im.crop(box).convert("RGBA")
        crop.putalpha(rounded_mask(crop.size, r, round_top))
        crop.save(OUT / f"{name}.png", optimize=True)
        print(f"{name}: box={box} size={crop.size} radius={r}")


if __name__ == "__main__":
    main()
