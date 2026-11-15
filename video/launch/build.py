"""Generate the Notchy launch-video HyperFrames compositions (16:9 + 9:16) from one shot/caption plan.

    python3 video/launch/build.py      -> video/launch/comp-16x9/index.html, video/launch/comp-9x16/index.html

Timing follows video/script/launch.md (beat table + measured Kokoro voice lengths, see
video/audio/vo-launch/timing.json). Footage intermediates live in video/launch/media/ (git-ignored,
rebuild with video/launch/make-media.sh). Each comp folder links media -> ../media.
The compositions are silent; audio is mixed separately by video/launch/mix.sh.
"""
import html, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
ACCENT = "#7AA7FF"
XF = 0.35  # crossfade length between shots

# ---- source sizes -----------------------------------------------------------------------------
NOTCH = (1920, 1080)
SETTINGS = (2560, 1440)

# camera presets: kind -> (16:9 s0, s1), (9:16 s0, s1). Notch shots are anchored at the top centre
# (source (960, 0) -> container top centre). 9:16 scales are capped so an 816 px panel stays <= 1080 wide.
CAM = {
    "hook":     ((1.05, 1.55), (1.40, 2.00)),
    "open":     ((1.45, 1.70), (1.25, 1.32)),
    "sessions": ((1.50, 1.78), (1.25, 1.32)),
    "dimnotch": ((1.30, 1.42), (1.50, 1.65)),
    "approval": ((1.00, 1.08), (1.24, 1.30)),
    "banner":   ((1.90, 2.10), (1.50, 1.58)),
    "calendar": ((1.30, 1.42), (1.25, 1.31)),
    "alerts":   ((1.08, 1.15), (1.25, 1.31)),
    "music":    ((1.55, 1.72), (1.25, 1.32)),
    "popup":    ((2.40, 2.65), (2.60, 2.90)),
    "swipe":    ((1.10, 1.15), (1.25, 1.31)),
}
# Settings shots: the window is cut out of the 2560x1440 frame (crop rect) and floated as a card over the
# desktop (closed-notch still). 16:9 shows the whole window above the caption band; 9:16 shows the
# content pane (with its title) at ~0.94x. (crop x, y, w, h), (s0, s1), card centre in the container.
SET_CARD = {
    "16x9": ((640, 224, 1280, 1120), (0.600, 0.620), (960, 424)),
    "9x16": ((992, 224, 928, 1056), (0.930, 0.950), (540, 500)),
}

# ---- shot lists -------------------------------------------------------------------------------
# (id, file, kind, start, end, media_start, cam, transition-in: fade | push | cut)
COMMON = [
    ("a", "closed-notch.png",          "img",   0.00,  3.15, 0.0, "hook",     "fade"),
    ("b", "hover-open-music.mp4",      "video", 2.80,  6.00, 0.4, "open",     "fade"),
    ("c", "claude-sessions.mp4",       "video", 5.65,  9.55, 0.0, "sessions", "fade"),
    ("d", "approval-dwell-allow.mp4",  "video", 9.20, 15.75, 0.0, "approval", "fade"),
    ("e", "banner-claude-finished.mp4","video",15.40, 18.95, 0.1, "banner",   "fade"),
    ("f", "closed-notch.png",          "img",  18.60, 20.45, 0.0, "dimnotch", "fade"),
    ("g", "banner-meeting.mp4",        "video",20.10, 24.45, 0.0, "banner",   "fade"),
    ("h", "calendar-hero.mp4",         "video",24.10, 27.60, 1.0, "calendar", "fade"),
    ("i", "banner-teams.mp4",          "video",27.25, 30.05, 0.4, "banner",   "fade"),
    ("j", "alerts-scroll.mp4",         "video",29.70, 33.45, 1.0, "alerts",   "fade"),
    ("k", "alerts-focus-moon.mp4",     "video",33.10, 37.40, 0.2, "alerts",   "push"),
    ("l", "music-seek-shuffle.mp4",    "video",37.05, 43.70, 0.0, "music",    "fade"),
]
SHOTS_16 = COMMON + [
    ("m", "volume-popup.mp4",          "video",43.35, 45.75, 0.3, "popup",    "push"),
    ("n", "brightness-popup.mp4",      "video",45.40, 48.60, 0.55,"popup",    "push"),
    ("o", "banner-airpods.mp4",        "video",48.25, 50.60, 0.6, "banner",   "push"),
    ("p", "banner-charger.mp4",        "video",50.25, 51.95, 0.5, "banner",   "push"),
    ("q", "banner-drive-eject.mp4",    "video",51.60, 55.45, 0.45,"banner",   "push"),
    ("r", "swipe-tabs-fast.mp4",       "video",55.10, 57.65, 0.2, "swipe",    "fade"),
    ("s", "settings-tabs.png",         "img",  57.30, 58.85, 0.0, "set",      "push"),
    ("t", "settings-theme-glass.mp4",  "video",58.50, 60.15, 0.9, "set",      "cut"),
    ("u", "settings-open-from.mp4",    "video",59.80, 62.55, 0.6, "set",      "cut"),
]
# 9:16 montage (no voice): each device shot holds >= 1.5 s; then "Make it yours" and the end card.
SHOTS_9 = COMMON + [
    ("m", "volume-popup.mp4",          "video",43.35, 45.45, 0.65,"popup",    "push"),
    ("o", "banner-airpods.mp4",        "video",45.10, 47.00, 0.8, "banner",   "push"),
    ("q", "banner-drive-eject.mp4",    "video",46.65, 48.30, 2.65,"banner",   "push"),
    ("r", "swipe-tabs-fast.mp4",       "video",47.95, 49.60, 0.45,"swipe",    "fade"),
    ("t", "settings-theme-glass.mp4",  "video",49.25, 50.80, 1.15,"set",      "push"),
    ("u", "settings-open-from.mp4",    "video",50.45, 52.10, 1.1, "set",      "cut"),
]

# ---- captions ---------------------------------------------------------------------------------
# ("H", [(text, t, cls)], end, style)   headline (style: hook | problem | solution)
# ("S", text, start, end)               sub line under the headline
def H(groups, end, style="solution", stack=True):
    return ("H", [(g + ("", None))[:4] for g in groups], end, style, stack)

def S(text, start, end):
    return ("S", text, start, end)

CAP_COMMON = [
    H([("That notch?", 0.15), ("Doing nothing.", 1.72, "mute")], 2.90, "hook"),
    H([("Until now.", 3.25)], 4.35, "problem"),
    H([("Meet", 4.50), ("Notchy.", 4.75, "accent")], 5.65),
    S("Hover to open", 4.95, 5.65),
    H([("Your AI coding agent needs you…", 5.95), ("but you're in another app?", 7.75)], 9.75, "problem nw"),
    H([("Agent approvals,", 9.95), ("right at the notch", 10.50, "accent")], 15.55),
    S("Rest your pointer to arm Allow once", 12.45, 15.55),
    H([("Long task done?", 15.75), ("Notchy tells you.", 16.85, "accent")], 18.60),
    S("A “finished” banner for long tasks", 17.25, 18.60),
    H([("Running late again?", 18.90)], 20.25, "problem"),
    H([("Never miss", 20.35), ("a meeting", 20.60, "accent")], 27.10),
    S("Reminder 1 min before · Join in one click", 21.20, 24.35),
    S("The Calendar tab counts down to the next one", 24.40, 27.10),
    H([("Teams & Outlook", 27.50), ("won't stop pinging?", 28.15)], 29.62, "problem"),
    H([("Work alerts", 29.75), ("without switching apps", 30.15, "accent")], 33.12),
    S("Teams & Outlook · unread counts in the Alerts tab", 30.60, 33.12),
    H([("Stays quiet", 33.30), ("during calls & Focus", 33.75, "accent")], 36.90),
    S("…and in full screen", 35.20, 36.90),
    H([("Your music,", 37.30), ("at the notch", 37.80, "accent")], 43.20),
    S("Art · controls · drag to seek · shuffle · output", 39.30, 43.20),
]
CAP_16 = CAP_COMMON + [
    H([("A clean volume &", 43.60), ("brightness pop-up", 44.15, "accent")], 48.40),
    S("No more big gray box", 46.75, 48.40),
    H([("Devices", 48.80), ("at a glance", 49.15, "accent")], 54.90),
    S("AirPods battery", 49.00, 50.50),
    S("Charging · time to full", 50.58, 51.80),
    S("USB drive · Eject from the notch", 51.88, 54.90),
    H([("Make it", 55.30), ("yours", 55.60, "accent")], 61.95),
    S("Swipe between tabs", 55.90, 57.05),
    S("Reorder tabs in Settings", 57.12, 58.45),
    S("Black or Glass", 58.52, 59.75),
    S("Pick where it opens & how it moves", 59.82, 61.95),
]
CAP_9 = CAP_COMMON + [
    H([("Volume pop-up", 43.50), ("AirPods · Eject", 45.10, "accent", [45.10, 46.65, 46.65])], 47.85),
    H([("Make it", 48.10), ("yours", 48.40, "accent")], 51.45),
    S("Tabs · themes · animations", 49.45, 51.45),
]

# dimmed "problem" phases (footage darkened while the problem line is on screen)
DIM = [(5.80, 9.75, 0.42), (18.60, 20.25, 0.55), (27.30, 29.62, 0.5)]

ASPECTS = {
    "16x9": dict(W=1920, H=1080, dur=70.0, shots=SHOTS_16, caps=CAP_16, end=62.2,
                 box=(0, 0, 1920, 1080), head_bottom=935, sub_top=955, head_px=76, sub_px=40,
                 cap_w=1500, fade=(69.25, 70.0)),
    "9x16": dict(W=1080, H=1920, dur=58.6, shots=SHOTS_9, caps=CAP_9, end=51.6,
                 box=(0, 250, 1080, 1000), head_bottom=1442, sub_top=1462, head_px=82, sub_px=44,
                 cap_w=960, fade=(57.9, 58.6)),
}


def cam_transform(kind, aspect, box_w, box_h, which):
    """Return (x, y, scale) for the start (which=0) or end (which=1) of the camera move."""
    ai = 0 if aspect == "16x9" else 1
    if kind == "set":
        (_, _, cw, ch), sc, (ax, ay) = SET_CARD[aspect]
        s = sc[which]
        return round(ax - cw * s / 2, 1), round(ay - ch * s / 2, 1), s
    s = CAM[kind][ai][which]
    sw, sh = NOTCH
    x, y = box_w / 2 - 960 * s, 0
    x = min(0, max(box_w - sw * s, x))   # keep the frame covered
    y = min(0, max(box_h - sh * s, y))
    return round(x, 1), round(y, 1), s


def words(text):
    return "".join(f'<span class="w">{html.escape(w)}</span> ' for w in text.split(" ")).strip()


def build(aspect):
    A = ASPECTS[aspect]
    W, Hh = A["W"], A["H"]
    bx, by, bw, bh = A["box"]
    out, js = [], []

    # shots
    shots = A["shots"]
    for n, (sid, src, kind, st, en, ms, cam, tr) in enumerate(shots):
        z = 10 + n
        track = 1 + (n % 2)
        dur = round(en - st, 3)
        x0, y0, s0 = cam_transform(cam, aspect, bw, bh, 0)
        x1, y1, s1 = cam_transform(cam, aspect, bw, bh, 1)
        sw, shh = SETTINGS if cam == "set" else NOTCH
        timing = f'data-start="{st}" data-duration="{dur}"'
        if kind == "video":
            media = (f'<video id="v-{sid}" class="clip" src="media/{src}" {timing} '
                     f'data-media-start="{ms}" data-track-index="{track}" muted playsinline '
                     f'style="width:{sw}px;height:{shh}px"></video>')
        else:
            media = (f'<img id="v-{sid}" class="clip" src="media/{src}" {timing} '
                     f'data-track-index="{track}" style="width:{sw}px;height:{shh}px" alt="" />')
        if cam == "set":
            cx, cy, cw, ch = SET_CARD[aspect][0]
            backdrop = (f'<div id="bd-{sid}" class="clip backdrop" {timing} data-track-index="{30 + n % 2}"></div>')
            inner = (f'{backdrop}<div class="cam win" id="cam-{sid}" style="width:{cw}px;height:{ch}px">'
                     f'<div class="crop" style="left:-{cx}px;top:-{cy}px">{media}</div></div>')
        else:
            inner = f'<div class="cam" id="cam-{sid}">{media}</div>'
        out.append(f'<div class="shot" id="shot-{sid}" style="z-index:{z}">{inner}</div>')
        js.append(f'tl.fromTo("#cam-{sid}", {{x:{x0},y:{y0},scale:{s0}}}, {{x:{x1},y:{y1},scale:{s1},duration:{dur},ease:"sine.inOut"}}, {st});')
        if n > 0 and tr == "fade":
            js.append(f'tl.fromTo("#shot-{sid}", {{opacity:0}}, {{opacity:1,duration:{XF},ease:"power1.inOut"}}, {st});')
        else:  # wrappers are not clips: keep them hidden outside their shot (the Settings card has a shadow)
            js.append(f'tl.fromTo("#shot-{sid}", {{opacity:0}}, {{opacity:1,duration:0.01}}, {st});')
        if n > 0 and tr == "push":
            prev = shots[n - 1][0]
            js.append(f'tl.fromTo("#shot-{sid}", {{x:{bw}}}, {{x:0,duration:{XF},ease:"power3.inOut"}}, {st});')
            js.append(f'tl.fromTo("#shot-{prev}", {{x:0}}, {{x:{-round(bw * 0.35)},duration:{XF},ease:"power3.inOut",immediateRender:false}}, {st});')
        js.append(f'tl.to("#shot-{sid}", {{opacity:0,duration:0.01}}, {en});')

    # dim overlay
    for a, b, lvl in DIM:
        js.append(f'tl.to("#dim", {{opacity:{lvl},duration:0.45,ease:"power2.out"}}, {a});')
        js.append(f'tl.to("#dim", {{opacity:0,duration:0.5,ease:"power2.inOut"}}, {b - 0.1});')

    # captions
    ctrack = {"H": 20, "S": 22}
    flip = {"H": 0, "S": 0}
    for i, c in enumerate(A["caps"]):
        cid = f"cap{i}"
        if c[0] == "H":
            _, groups, end, style, can_stack = c
            st = groups[0][1]
            parts = []
            for gi, (text, t, cls, wt) in enumerate(groups):
                parts.append(f'<span class="g {cls}" id="{cid}g{gi}">{words(text)}</span>')
                if wt:  # explicit per-word entrance times
                    for wi, wtime in enumerate(wt):
                        js.append(f'tl.fromTo("#{cid}g{gi} .w:nth-child({wi + 1})", {{opacity:0,y:34,filter:"blur(8px)"}}, '
                                  f'{{opacity:1,y:0,filter:"blur(0px)",duration:0.55,ease:"power3.out"}}, {wtime});')
                    continue
                js.append(f'tl.fromTo("#{cid}g{gi} .w", {{opacity:0,y:34,filter:"blur(8px)"}}, '
                          f'{{opacity:1,y:0,filter:"blur(0px)",duration:0.55,ease:"power3.out",stagger:0.06}}, {t});')
            tr = ctrack["H"] + flip["H"]; flip["H"] ^= 1
            stack = " stack" if can_stack and len(" ".join(g[0] for g in groups)) > 22 and len(groups) > 1 else ""
            out.append(f'<div class="clip head {style}{stack}" id="{cid}" data-start="{st}" data-duration="{round(end - st + 0.02, 3)}" '
                       f'data-track-index="{tr}">{" ".join(parts)}</div>')
        else:
            _, text, st, end = c
            tr = ctrack["S"] + flip["S"]; flip["S"] ^= 1
            out.append(f'<div class="clip sub" id="{cid}" data-start="{st}" data-duration="{round(end - st + 0.02, 3)}" '
                       f'data-track-index="{tr}">{html.escape(text)}</div>')
            js.append(f'tl.fromTo("#{cid}", {{opacity:0,y:18}}, {{opacity:1,y:0,duration:0.45,ease:"expo.out"}}, {st});')
        js.append(f'tl.to("#{cid}", {{opacity:0,y:-12,duration:0.22,ease:"power2.in"}}, {round(end - 0.22, 3)});')

    # end card
    e = A["end"]
    edur = round(A["dur"] - e, 3)
    out.append(f'''<div id="endcard" class="clip" data-start="{e}" data-duration="{edur}" data-track-index="5">
  <div class="glow"></div>
  <div class="ec">
    <div class="pill" id="pill"><span id="wordmark">Notchy</span></div>
    <div class="l1" id="ec1">Free &amp; open source (GPL-3.0)</div>
    <div class="l2" id="ec2">Built by Ujjwal Kumar</div>
    <div class="l3" id="ec3">github.com/Ujjwalkumar-pm/Notchy</div>
    <div class="l4" id="ec4">macOS 14 or later · best on MacBooks with a notch</div>
  </div>
</div>''')
    js += [
        f'tl.fromTo("#endcard", {{opacity:0}}, {{opacity:1,duration:0.5,ease:"power1.inOut"}}, {e});',
        f'tl.fromTo("#pill", {{width:{"240" if aspect == "16x9" else "220"},height:58,borderRadius:"0 0 26px 26px",y:-40}}, '
        f'{{width:{"780" if aspect == "16x9" else "820"},height:{"210" if aspect == "16x9" else "230"},borderRadius:"60px",y:0,duration:0.75,ease:"expo.inOut"}}, {e + 0.05});',
        f'tl.fromTo("#wordmark", {{opacity:0,scale:0.86,filter:"blur(10px)"}}, {{opacity:1,scale:1,filter:"blur(0px)",duration:0.6,ease:"power3.out"}}, {e + 0.45});',
        f'tl.fromTo(".glow", {{opacity:0,scale:0.7}}, {{opacity:1,scale:1,duration:1.6,ease:"sine.out"}}, {e + 0.4});',
        f'tl.fromTo("#ec1", {{opacity:0,y:24}}, {{opacity:1,y:0,duration:0.55,ease:"power3.out"}}, {e + 0.95});',
        f'tl.fromTo("#ec2", {{opacity:0,y:24}}, {{opacity:1,y:0,duration:0.55,ease:"back.out(1.4)"}}, {e + 2.15});',
        f'tl.fromTo("#ec3", {{opacity:0,y:24}}, {{opacity:1,y:0,duration:0.55,ease:"expo.out"}}, {e + 4.05});',
        f'tl.fromTo("#ec4", {{opacity:0}}, {{opacity:1,duration:0.6,ease:"sine.out"}}, {e + 4.45});',
        f'tl.fromTo("#fade", {{opacity:0}}, {{opacity:1,duration:{round(A["fade"][1] - A["fade"][0], 2)},ease:"sine.in"}}, {A["fade"][0]});',
    ]

    is9 = aspect == "9x16"
    css = f'''
:root {{ --accent:{ACCENT}; --ink:#F5F7FA; --muted:#AEB7C7; --ground:#05060A;
  --font:-apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", Helvetica, Arial, sans-serif;
  --mono:"SF Mono", ui-monospace, Menlo, monospace; }}
* {{ margin:0; padding:0; box-sizing:border-box; }}
html, body {{ width:{W}px; height:{Hh}px; overflow:hidden; background:var(--ground); }}
#root {{ position:relative; width:{W}px; height:{Hh}px; overflow:hidden; background:var(--ground); font-family:var(--font); color:var(--ink); }}
#screen {{ position:absolute; left:{bx}px; top:{by}px; width:{bw}px; height:{bh}px; overflow:hidden; background:#0b0d14;
  {"-webkit-mask-image:linear-gradient(180deg,#000 0,#000 86%,transparent 100%);" if is9 else ""} }}
.shot {{ position:absolute; inset:0; }}
.cam {{ position:absolute; left:0; top:0; transform-origin:0 0; will-change:transform; }}
.cam video, .cam img {{ display:block; }}
.win {{ overflow:hidden; border-radius:22px; box-shadow:0 40px 120px rgba(0,0,0,0.55), 0 0 0 1px rgba(255,255,255,0.08); }}
.crop {{ position:absolute; }}
.backdrop {{ position:absolute; inset:0; background:#0b0d14 url(media/closed-notch.png) center top / cover no-repeat; }}
#brand {{ position:absolute; left:0; right:0; top:118px; text-align:center; z-index:5; font-size:40px; font-weight:700;
  letter-spacing:-0.03em; color:rgba(245,247,250,0.55); {"" if is9 else "display:none;"} }}
#brand i {{ display:inline-block; width:12px; height:12px; border-radius:6px; background:var(--accent); margin-left:8px;
  vertical-align:middle; box-shadow:0 0 18px rgba(122,167,255,0.8); }}
#dim {{ position:absolute; inset:0; background:#000; opacity:0; z-index:90; }}
#band {{ position:absolute; left:0; right:0; bottom:0; height:{460 if not is9 else 0}px; z-index:95;
  background:linear-gradient(180deg, rgba(5,6,10,0) 0%, rgba(5,6,10,0.72) 45%, rgba(5,6,10,0.9) 100%); }}
#halo {{ position:absolute; left:50%; top:{1260 if is9 else 0}px; width:1400px; height:900px; margin-left:-700px; z-index:1;
  background:radial-gradient(closest-side, rgba(122,167,255,0.16), rgba(122,167,255,0) 70%); {"" if is9 else "display:none;"} }}
.head, .sub {{ position:absolute; left:50%; width:{A["cap_w"]}px; margin-left:-{A["cap_w"] // 2}px; text-align:center; z-index:100; }}
.head {{ bottom:{Hh - A["head_bottom"]}px; font-size:{A["head_px"]}px; font-weight:700; line-height:1.08; letter-spacing:-0.025em;
  text-shadow:0 2px 24px rgba(0,0,0,0.55); text-wrap:balance; }}
{'.head.stack .g { display:block; } .head.problem { font-size:68px; }' if is9 else ''}
.head .w {{ display:inline-block; }}
.head .accent {{ color:var(--accent); }}
.head .mute {{ color:var(--muted); }}
.head.problem {{ color:#C9D0DC; font-weight:600; }}
{'' if is9 else '.head.nw .g { white-space:nowrap; }'}
.sub {{ top:{A["sub_top"]}px; font-size:{A["sub_px"]}px; font-weight:500; line-height:1.2; color:#D7DEEA; letter-spacing:-0.005em;
  text-shadow:0 2px 16px rgba(0,0,0,0.6); text-wrap:balance; }}
#endcard {{ position:absolute; inset:0; z-index:200; background:var(--ground); }}
#endcard .glow {{ position:absolute; left:50%; top:{780 if is9 else 330}px; width:1300px; height:900px; margin:-450px 0 0 -650px;
  background:radial-gradient(closest-side, rgba(122,167,255,0.22), rgba(122,167,255,0) 72%); }}
#endcard .ec {{ position:absolute; inset:0; display:flex; flex-direction:column; align-items:center;
  justify-content:{"flex-start" if is9 else "center"}; gap:{30 if is9 else 22}px; padding:{"470px 60px 0" if is9 else "0 120px"}; }}
.pill {{ display:flex; align-items:center; justify-content:center; background:#000; overflow:hidden;
  box-shadow:0 0 0 1.5px rgba(122,167,255,0.45), 0 30px 90px rgba(122,167,255,0.18); margin-bottom:{24 if is9 else 26}px; }}
#wordmark {{ font-size:{132 if is9 else 124}px; font-weight:700; letter-spacing:-0.045em; color:var(--ink); }}
.l1 {{ font-size:{46 if is9 else 44}px; font-weight:500; color:#D7DEEA; }}
.l2 {{ font-size:{66 if is9 else 64}px; font-weight:700; letter-spacing:-0.02em; color:var(--ink); }}
.l3 {{ font-size:{40 if is9 else 42}px; font-weight:600; color:var(--accent); font-family:var(--mono); letter-spacing:-0.01em; }}
.l4 {{ font-size:{34 if is9 else 34}px; font-weight:500; color:var(--muted); text-align:center; max-width:{900 if is9 else 1400}px; }}
#fade {{ position:absolute; inset:0; background:#000; opacity:0; z-index:300; pointer-events:none; }}
'''
    doc = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width={W}, height={Hh}" />
<!-- generated by video/launch/build.py — edit the plan there, not this file -->
<script src="https://cdn.jsdelivr.net/npm/gsap@3.15.0/dist/gsap.min.js"></script>
<style>{css}</style>
</head>
<body>
<div id="root" data-composition-id="main" data-start="0" data-duration="{A["dur"]}" data-width="{W}" data-height="{Hh}">
<div id="halo"></div>
<div id="brand">Notchy<i></i></div>
<div id="screen">
{chr(10).join(o for o in out if o.startswith('<div class="shot"'))}
<div id="dim"></div>
</div>
<div id="band"></div>
{chr(10).join(o for o in out if not o.startswith('<div class="shot"'))}
<div id="fade"></div>
</div>
<script>
window.__timelines = window.__timelines || {{}};
const tl = gsap.timeline({{ paused: true }});
{chr(10).join(js)}
window.__timelines["main"] = tl;
</script>
</body>
</html>
'''
    d = os.path.join(HERE, f"comp-{aspect}")
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "index.html"), "w").write(doc)
    link = os.path.join(d, "media")
    if not os.path.lexists(link):
        os.symlink("../media", link)
    for f, body in (("hyperframes.json", {"paths": {"blocks": "compositions", "assets": "media"}}),
                    ("meta.json", {"id": f"notchy-launch-{aspect}", "name": f"Notchy launch {aspect}"})):
        p = os.path.join(d, f)
        if not os.path.exists(p):
            json.dump(body, open(p, "w"), indent=2)
    print("wrote", d)


if __name__ == "__main__":
    for a in ASPECTS:
        build(a)
