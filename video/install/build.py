"""Generate the Notchy install & setup video HyperFrames compositions (16:9 + 9:16) from one plan.

    python3 video/install/build.py   -> video/install/comp-16x9/index.html, video/install/comp-9x16/index.html

Same look and caption system as the launch video (video/launch/build.py). Timing follows
video/script/install.md (87.0 s, both cuts) and the measured Kokoro lines in video/audio/vo-install/timing.json.
Real footage intermediates live in video/install/media/ (git-ignored, rebuild with make-media.sh).
The GitHub page, Finder, the macOS "Not Opened" alert, System Settings and the menu-bar close-up menu are
clean HTML redraws (generic windows, demo content only). The compositions are silent; mix.sh adds audio.
"""
import html, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
ACCENT = "#7AA7FF"
XF = 0.35
DUR = 87.0
NOTCH = (1920, 1080)
DESK = (2560, 1440)

ASPECTS = {
    "16x9": dict(W=1920, H=1080, box=(0, 0, 1920, 1080), head_bottom=935, sub_top=955, head_px=76, sub_px=40,
                 cap_w=1760, stage=(1.0, 360, 46), card=(0.600, 0.620, 960, 424)),
    "9x16": dict(W=1080, H=1920, box=(0, 250, 1080, 1000), head_bottom=1442, sub_top=1462, head_px=78, sub_px=44,
                 cap_w=960, stage=(0.88, 12, 166), card=(0.790, 0.810, 540, 500)),
}
END = 81.0
BG_S = 1.0  # desktop backdrop scale behind the redraws (= end of the title push-in)

# ---------------------------------------------------------------------------------------------
# shots: (id, kind, start, end, transition-in, params)
#   kind "img"/"video": real footage; params: src, cam, media_start
#   kind "rd": HTML redraw; params: builder name
SHOTS = [
    ("t0",  "img",   0.00,  4.60, "fade", dict(src="closed-notch.png", cam="title")),
    ("gh",  "rd",    4.60, 11.00, "cut",  dict(rd="github")),
    ("fd",  "rd",   11.00, 31.50, "push", dict(rd="finder")),
    ("w1",  "video",31.50, 36.00, "push", dict(src="welcome-1.mp4", cam="desk", ms=0.2)),
    ("w2",  "video",36.00, 46.00, "cut",  dict(src="welcome-2.mp4", cam="desk", ms=0.0)),
    ("w3",  "video",46.00, 52.00, "cut",  dict(src="welcome-3.mp4", cam="desk", ms=0.0)),
    ("sg",  "img",  52.00, 62.50, "push", dict(src="settings-general.png", cam="set")),
    ("cm",  "video",62.50, 66.20, "push", dict(src="ctx.mp4", cam="menu", ms=0.0)),
    ("mb",  "img",  66.20, 68.60, "cut",  dict(src="menubar.png", cam="mbar")),
    ("ro",  "rd",   68.60, 70.60, "push", dict(rd="reopen")),
    ("sp",  "video",70.60, 72.50, "push", dict(src="sidebar.mp4", cam="set", ms=0.0)),
    ("to",  "video",72.50, 76.60, "cut",  dict(src="turnoff.mp4", cam="set", ms=0.0)),
    ("cq",  "video",76.60, 78.40, "push", dict(src="ctx.mp4", cam="menu", ms=0.75)),
    ("tr",  "rd",   78.40, END + 0.6, "push", dict(rd="trash")),
]

# camera presets per aspect: (s0, s1, anchor source x) - top-anchored on the anchor x
CAM = {
    "title": {"16x9": (1.0, 1.0, 960), "9x16": (1.0, 1.0, 960)},
    "desk":  {"16x9": (0.750, 0.790, 1280), "9x16": (0.930, 0.960, 1280)},
    "menu":  {"16x9": (2.00, 2.10, 1084), "9x16": (2.30, 2.40, 1084)},
    "mbar":  {"16x9": (2.60, 2.70, 2122), "9x16": (2.20, 2.30, 2122)},
}
SRC = {"title": NOTCH, "desk": DESK, "menu": NOTCH, "mbar": DESK}
SET_CROP = (640, 224, 1280, 1120)   # the Settings window inside the 2560x1440 frame

# ---------------------------------------------------------------------------------------------
# captions (same system as the launch video)
def H(groups, end, style="solution", stack=True):
    return ("H", [(g + ("", None))[:4] for g in groups], end, style, stack)


def S(text, start, end):
    return ("S", text, start, end)


CAPS = [
    H([("Install & set up", 0.35), ("Notchy", 0.95, "accent")], 4.40),
    S("macOS 14 or later", 2.30, 4.40),
    H([("Download", 4.85), ("Notchy.zip", 5.20, "accent")], 10.85),
    S("github.com/Ujjwalkumar-pm/Notchy → Releases", 5.50, 10.85),
    H([("Unzip, then drag to", 11.25), ("Applications", 11.75, "accent")], 17.35),
    S("Double-click Notchy.zip · drag Notchy into Applications", 13.40, 17.35),
    H([("First open only:", 17.75), ("macOS can't verify Notchy", 18.30, "accent")], 23.25),
    S("That's expected: Notchy isn't notarized", 21.90, 23.25),
    H([("System Settings →", 23.30), ("Open Anyway", 24.00, "accent")], 31.30),
    S("Privacy & Security → Security → Open Anyway", 23.70, 27.60),
    S("Confirm with Touch ID or your password", 27.70, 31.30),
    H([("First run:", 31.75), ("a quick welcome", 32.15, "accent")], 33.35),
    H([("Step 1 ·", 33.50), ("Hover the notch", 33.85, "accent")], 35.95),
    S("Or press ⌥⌘N from anywhere", 34.20, 35.95),
    H([("Step 2 ·", 36.05), ("Allow what you use", 36.40, "accent")], 45.85),
    S("Click Allow… — Notchy opens the right pane", 38.55, 42.00),
    S("Notchy works without them", 42.10, 45.85),
    H([("Step 3 ·", 46.25), ("Pick your tabs", 46.60, "accent")], 51.85),
    S("Optional: a menu bar icon", 48.20, 51.85),
    H([("Your AI coding agent:", 52.25), ("set up for you", 52.85, "accent")], 59.45),
    S("Notchy adds its hooks to the agent's settings", 53.40, 55.25),
    S("Your old file is backed up first", 55.30, 57.65),
    S("Turn off in Settings → General", 57.70, 59.45),
    H([("Notchy turns on", 59.55), ("Start at login", 59.95, "accent")], 62.35),
    S("Change it in Settings → General", 60.30, 62.35),
    H([("Open", 62.75), ("Settings", 63.00, "accent")], 72.35),
    S("Right-click the notch → Settings…", 63.30, 66.15),
    S("…or the menu bar icon", 66.30, 68.55),
    S("…or open Notchy again from Applications", 68.65, 72.35),
    H([("To", 72.75), ("uninstall", 72.95, "accent")], 80.85),
    S("1 · Settings → General → coding agent integration off", 73.90, 76.85),
    S("2 · Quit Notchy from the notch menu", 76.95, 78.70),
    S("3 · Drag Notchy to the Trash", 78.80, 80.85),
]

# ---------------------------------------------------------------------------------------------
# redraw building blocks (stage = 1200 x 760 design px)
APPICON = '<div class="appicon{cls}" {attrs}><i></i></div>'


def appicon(cls="", attrs=""):
    return APPICON.format(cls=(" " + cls) if cls else "", attrs=attrs)


ZIPICON = '<div class="zipicon"><b></b><span>ZIP</span></div>'
CURSOR = ('<svg class="cursor" id="cur-{sid}" viewBox="0 0 28 40" width="34" height="48">'
          '<path d="M2 2 L2 31 L9.5 24.5 L14.5 36 L19 34 L14 22.8 L24 22.8 Z" fill="#111" stroke="#fff" '
          'stroke-width="2.2" stroke-linejoin="round"/></svg>')


def lights():
    return '<div class="lights"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i></div>'


def generic_icon(color, glyph):
    return f'<div class="gicon" style="background:{color}">{glyph}</div>'


class Cur:
    """Cursor choreography helper (stage coordinates of the pointer tip)."""

    def __init__(self, sid, js, x, y, t):
        self.sel, self.js = f"#cur-{sid}", js
        js.append(f'tl.set("{self.sel}", {{x:{x},y:{y}}}, {t});')

    def move(self, x, y, t, d=0.6, ease="power2.inOut"):
        self.js.append(f'tl.to("{self.sel}", {{x:{x},y:{y},duration:{d},ease:"{ease}"}}, {t});')

    def click(self, t):
        self.js.append(f'tl.to("{self.sel}", {{scale:0.8,duration:0.07,yoyo:true,repeat:1,ease:"power1.inOut"}}, {t});')


def rd_github(sid, st, js):
    rows = [("Notchy.zip", True), ("Source code (zip)", False), ("Source code (tar.gz)", False)]
    asset_html = "".join(
        f'<div class="asset{" hot" if hot else ""}" id="{sid}-a{i}">'
        f'{"<span class=" + chr(34) + "zipmini" + chr(34) + "></span>" if hot else "<span class=" + chr(34) + "srcmini" + chr(34) + "></span>"}'
        f'<span class="aname">{n}</span></div>' for i, (n, hot) in enumerate(rows))
    body = f'''
<div class="win browser" id="{sid}-win">
  <div class="bbar">{lights()}
    <div class="nav">&#8249;&nbsp;&nbsp;&#8250;</div>
    <div class="addr"><span class="lock"></span>github.com/Ujjwalkumar-pm/Notchy/releases</div>
    <div class="dlbtn" id="{sid}-dl"><svg viewBox="0 0 40 40" width="40" height="40">
      <circle cx="20" cy="20" r="16" fill="none" stroke="rgba(255,255,255,0.14)" stroke-width="3"/>
      <circle id="{sid}-ring" cx="20" cy="20" r="16" fill="none" stroke="{ACCENT}" stroke-width="3" stroke-linecap="round"
        stroke-dasharray="100.5" stroke-dashoffset="100.5" transform="rotate(-90 20 20)"/>
      <path d="M20 11 V25 M14 20 L20 26 L26 20" fill="none" stroke="#e6edf3" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
  </div>
  <div class="ghpage">
    <div class="ghhead"><b>GitHub</b><span class="crumb">Ujjwalkumar-pm <i>/</i> <strong>Notchy</strong></span><span class="pub">Public</span></div>
    <div class="ghtabs"><span>Code</span><span>Issues</span><span>Pull requests</span><span>Actions</span><span class="on">Releases</span></div>
    <div class="rel">
      <div class="reltitle">v1.0.0 <span class="latest">Latest</span></div>
      <div class="relmeta"><span class="avatar"></span>Ujjwalkumar-pm released this</div>
      <div class="relnotes">First public release. Download <b>Notchy.zip</b>, unzip it and drag Notchy into Applications.<br>Requires macOS 14 or later.</div>
      <div class="assets"><div class="ahead">&#9662; Assets <span class="cnt">3</span></div>{asset_html}</div>
    </div>
  </div>
  <div class="dlpop" id="{sid}-pop">{ZIPICON}<div><b>Notchy.zip</b><span>Downloaded</span></div><em>&#10003;</em></div>
</div>
{CURSOR.format(sid=sid)}'''
    js += [
        f'tl.fromTo("#{sid}-win", {{opacity:0,scale:0.94,y:24}}, {{opacity:1,scale:1,y:0,duration:0.55,ease:"expo.out"}}, {st + 0.05});',
        f'tl.fromTo("#cur-{sid}", {{opacity:0}}, {{opacity:1,duration:0.2}}, {st + 0.9});',
    ]
    c = Cur(sid, js, 1010, 690, st)
    c.move(232, 487, 6.6, 1.2)                    # onto Notchy.zip
    js.append(f'tl.to("#{sid}-a0", {{backgroundColor:"rgba(122,167,255,0.16)",duration:0.25}}, 7.6);')
    c.click(8.0)
    js += [
        f'tl.to("#{sid}-ring", {{attr:{{"stroke-dashoffset":0}},duration:1.0,ease:"power1.inOut"}}, 8.25);',
        f'tl.fromTo("#{sid}-dl", {{scale:1}}, {{scale:1.18,duration:0.18,yoyo:true,repeat:1,ease:"power1.inOut"}}, 8.15);',
        f'tl.fromTo("#{sid}-pop", {{opacity:0,y:-14,scale:0.96}}, {{opacity:1,y:0,scale:1,duration:0.45,ease:"back.out(1.6)"}}, 9.3);',
    ]
    c.move(1030, 300, 9.0, 0.9)
    return body


def finder_icons(sid, js):
    return ""


APPS = [("Calculator", "#5b5f68", "&#215;"), ("Notes", "#e9c44a", "&#8801;"), ("Notchy", None, ""),
        ("Preview", "#4c8fe0", "&#9635;"), ("TextEdit", "#d9d9de", "A")]


def finder_window(sid, show_apps=False, trash=False):
    sb = [("Applications", "apps"), ("Desktop", "desk"), ("Documents", "docs"), ("Downloads", "dl")]
    sel = "apps" if show_apps else "dl"
    side = "".join(f'<div class="sbi{" sel" if k == sel else ""}" id="{sid}-sb-{k}"><span class="fold"></span>{n}</div>'
                   for n, k in sb)
    apps = "".join(
        f'<div class="fitem" id="{sid}-app-{n.lower()}">{appicon() if col is None else generic_icon(col, g)}<span>{n}</span></div>'
        for n, col, g in APPS)
    dl = (f'<div class="fitem" id="{sid}-zip">{ZIPICON}<span>Notchy.zip</span></div>'
          f'<div class="fitem" id="{sid}-app">{appicon()}<span>Notchy</span></div>')
    title = "Applications" if show_apps else "Downloads"
    trash_html = (f'<div class="trash" id="{sid}-trash"><svg viewBox="0 0 80 96" width="80" height="96">'
                  '<rect x="8" y="16" width="64" height="76" rx="10" fill="rgba(235,240,248,0.16)" stroke="rgba(235,240,248,0.75)" stroke-width="3"/>'
                  '<rect x="2" y="8" width="76" height="10" rx="5" fill="rgba(235,240,248,0.85)"/>'
                  '<path d="M26 32 V80 M40 32 V80 M54 32 V80" stroke="rgba(235,240,248,0.55)" stroke-width="3" stroke-linecap="round"/></svg>'
                  '<span>Trash</span></div>') if trash else ""
    return f'''
<div class="win finder" id="{sid}-win">
  <div class="fside">{lights()}<div class="sbh">Favorites</div>{side}</div>
  <div class="fmain">
    <div class="fbar"><span class="nav">&#8249;&nbsp;&nbsp;&#8250;</span><b id="{sid}-title">{title}</b>
      <span id="{sid}-title2" class="t2">Applications</span></div>
    <div class="fgrid" id="{sid}-vdl" style="{'display:none' if show_apps else ''}">{dl}</div>
    <div class="fgrid" id="{sid}-vapps" style="{'' if show_apps else 'opacity:0'}">{apps}</div>
  </div>
</div>{trash_html}
<div class="ghost" id="{sid}-ghost">{appicon()}</div>'''


def alert(sid, key, title, body, buttons):
    btns = "".join(f'<div class="abtn{" def" if d else ""}" id="{sid}-{key}-b{i}">{b}</div>' for i, (b, d) in enumerate(buttons))
    return (f'<div class="alert" id="{sid}-{key}">{appicon("sm")}<div class="atitle">{title}</div>'
            f'<div class="abody">{body}</div><div class="abtns">{btns}</div></div>')


SS_SIDEBAR = [("Wi-Fi", "#2d7cf6"), ("Bluetooth", "#2d7cf6"), ("Network", "#2d7cf6"), None,
              ("Notifications", "#e5484d"), ("Sound", "#e5484d"), ("Focus", "#6e56cf"), None,
              ("General", "#8e8e93"), ("Appearance", "#3a3a3c"), ("Accessibility", "#2d7cf6"),
              ("Desktop & Dock", "#3a3a3c"), ("Displays", "#2d7cf6"), None,
              ("Privacy & Security", "#2d7cf6"), ("Touch ID & Password", "#e5484d")]
SS_ROWS = ["Location Services", "Contacts", "Calendars", "Reminders", "Photos", "Bluetooth", "Microphone",
           "Camera", "Accessibility", "Full Disk Access"]


def ss_window(sid):
    side = []
    for it in SS_SIDEBAR:
        if it is None:
            side.append('<div class="ssgap"></div>')
            continue
        n, c = it
        k = "ps" if n.startswith("Privacy") else n.split()[0].lower().replace("-", "")
        side.append(f'<div class="ssi" id="{sid}-ss-{k}"><span class="sq" style="background:{c}"></span>{n}</div>')
    rows = "".join(f'<div class="ssrow"><span class="sq" style="background:#2d7cf6"></span>{r}<em>&#8250;</em></div>' for r in SS_ROWS)
    return f'''
<div class="win ss" id="{sid}-ss">
  <div class="ssside">{lights()}<div class="sssearch">&#9906;&nbsp; Search</div>{"".join(side)}</div>
  <div class="ssmain">
    <div class="sstitle"><span class="nav">&#8249;&nbsp;&nbsp;&#8250;</span><b>Privacy &amp; Security</b></div>
    <div class="ssview"><div class="ssscroll" id="{sid}-scroll">
      <div class="ssgroup">{rows}</div>
      <div class="sshead">Security</div>
      <div class="ssgroup">
        <div class="ssrow tall">Allow applications from<span class="pop">App Store &amp; Known Developers &#8661;</span></div>
        <div class="ssrow tall blocked" id="{sid}-blocked">“Notchy” was blocked to protect your Mac.
          <span class="pbtn" id="{sid}-open">Open Anyway</span></div>
      </div>
      <div class="ssgroup"><div class="ssrow">FileVault<em>Off &#8250;</em></div><div class="ssrow">Lockdown Mode<em>Off &#8250;</em></div></div>
    </div></div>
  </div>
</div>'''


NOT_OPENED_BODY = "Apple could not verify “Notchy” is free of malware that may harm your Mac or compromise your privacy."


def rd_finder(sid, st, js):
    """11.0-31.5: Downloads -> unzip -> drag to Applications -> first open -> Not Opened -> Privacy & Security."""
    body = finder_window(sid) + ss_window(sid)
    body += alert(sid, "a1", "“Notchy” Not Opened", NOT_OPENED_BODY, [("Done", True), ("Move to Trash", False)])
    body += alert(sid, "a2", "Open “Notchy”?", NOT_OPENED_BODY, [("Open Anyway", True), ("Done", False)])
    body += f'''<div class="auth" id="{sid}-auth"><div class="fp" id="{sid}-fp"><svg viewBox="0 0 64 64" width="88" height="88">
<g fill="none" stroke="#ff5a6e" stroke-width="3.2" stroke-linecap="round">
<path d="M18 46c-3-5-4-10-4-15 0-10 8-18 18-18s18 8 18 18"/><path d="M24 50c-3-5-4-11-4-17 0-7 5-12 12-12s12 5 12 12c0 4-1 7-2 9"/>
<path d="M32 52c-3-6-4-12-4-18 0-3 2-5 4-5s4 2 4 5c0 6 2 11 5 15"/><path d="M38 40c0-3 0-5 0-6"/></g></svg>
<div class="fpok" id="{sid}-fpok">&#10003;</div></div>
<div class="atitle">Privacy &amp; Security</div><div class="abody">Touch ID or enter your password to allow this.</div>
<div class="pwd"><span id="{sid}-dots">&#9679;&#9679;&#9679;&#9679;&#9679;&#9679;&#9679;&#9679;</span></div>
<div class="abtns"><div class="abtn">Use Password…</div><div class="abtn">Cancel</div></div></div>'''
    body += CURSOR.format(sid=sid)
    js.append(f'tl.fromTo("#cur-{sid}", {{opacity:0}}, {{opacity:1,duration:0.2}}, {st + 0.4});')
    # Finder geometry: window at (50,40) 1100x680; sidebar 250; grid origin (300+50, 40+70+30)
    c = Cur(sid, js, 900, 640, st)
    c.move(405, 205, 11.5, 0.7)                     # onto Notchy.zip
    js.append(f'tl.to("#{sid}-zip", {{backgroundColor:"rgba(122,167,255,0.22)",duration:0.12}}, 12.15);')
    c.click(12.2); c.click(12.42)
    js += [f'tl.fromTo("#{sid}-app", {{opacity:0,scale:0.5}}, {{opacity:1,scale:1,duration:0.5,ease:"back.out(1.8)"}}, 12.75);',
           f'tl.to("#{sid}-zip", {{backgroundColor:"rgba(122,167,255,0)",duration:0.2}}, 12.8);']
    c.move(595, 205, 13.55, 0.5)                    # onto the app
    js.append(f'tl.to("#{sid}-app", {{backgroundColor:"rgba(122,167,255,0.22)",duration:0.12}}, 14.05);')
    # drag: ghost icon follows the pointer to the sidebar "Applications" row (x 150, y 150)
    js += [f'tl.set("#{sid}-ghost", {{x:543,y:150,opacity:0}}, {st});',
           f'tl.to("#{sid}-ghost", {{opacity:0.75,duration:0.15}}, 14.15);',
           f'tl.to("#{sid}-ghost", {{x:110,y:110,duration:1.05,ease:"power2.inOut"}}, 14.2);']
    c.move(165, 160, 14.2, 1.05)
    js += [f'tl.to("#{sid}-sb-apps", {{backgroundColor:"rgba(122,167,255,0.35)",duration:0.15}}, 15.0);',
           f'tl.to("#{sid}-ghost", {{opacity:0,scale:0.4,duration:0.25,ease:"power2.in"}}, 15.35);',
           f'tl.to("#{sid}-app", {{opacity:0,scale:0.6,duration:0.25,ease:"power2.in"}}, 15.35);',
           # show Applications
           f'tl.to("#{sid}-sb-dl", {{backgroundColor:"rgba(255,255,255,0)",duration:0.1}}, 15.7);',
           f'tl.to("#{sid}-sb-apps", {{backgroundColor:"rgba(255,255,255,0.13)",duration:0.15}}, 15.7);',
           f'tl.to("#{sid}-vdl", {{opacity:0,duration:0.15}}, 15.7);',
           f'tl.to("#{sid}-title", {{opacity:0,duration:0.1}}, 15.7);',
           f'tl.to("#{sid}-title2", {{opacity:1,duration:0.15}}, 15.8);',
           f'tl.fromTo("#{sid}-vapps", {{opacity:0}}, {{opacity:1,duration:0.3,immediateRender:false}}, 15.8);',
           f'tl.fromTo("#{sid}-app-notchy", {{scale:0.6}}, {{scale:1,duration:0.45,ease:"back.out(2)",immediateRender:false}}, 15.85);']
    c.move(785, 205, 16.4, 0.8)                     # onto Notchy in Applications (3rd item)
    js.append(f'tl.to("#{sid}-app-notchy", {{backgroundColor:"rgba(122,167,255,0.22)",duration:0.12}}, 17.55);')
    c.click(17.6); c.click(17.82)
    # first open -> "Not Opened" alert (stage centre)
    js += [f'tl.fromTo("#{sid}-a1", {{opacity:0,scale:0.9}}, {{opacity:1,scale:1,duration:0.35,ease:"back.out(1.5)"}}, 18.35);',
           f'tl.fromTo("#{sid}-win", {{filter:"brightness(1)"}}, {{filter:"brightness(0.7)",duration:0.3,immediateRender:false}}, 18.35);']
    c.move(600, 452, 20.6, 0.9)                     # Done
    js.append(f'tl.to("#{sid}-a1-b0", {{filter:"brightness(1.25)",duration:0.1}}, 21.55);')
    c.click(21.6)
    js += [f'tl.to("#{sid}-a1", {{opacity:0,scale:0.96,duration:0.2,ease:"power2.in"}}, 21.75);',
           # System Settings opens over Finder
           f'tl.set("#{sid}-ss", {{opacity:1}}, 22.4);',
           f'tl.fromTo("#{sid}-ss", {{scale:0.93}}, {{scale:1,duration:0.5,ease:"expo.out"}}, 22.4);',
           f'tl.set("#{sid}-win", {{opacity:0}}, 22.4);',
           f'tl.set("#{sid}-mbss", {{opacity:1}}, 22.4);']
    c.move(190, 545, 22.6, 0.75)                    # Privacy & Security in the sidebar
    c.click(23.4)
    js += [f'tl.to("#{sid}-ss-ps", {{backgroundColor:"#2a63d4",color:"#fff",duration:0.12}}, 23.45);',
           f'tl.to("#{sid}-scroll", {{y:-500,duration:1.5,ease:"power2.inOut"}}, 24.0);',
           f'tl.fromTo("#{sid}-blocked", {{boxShadow:"0 0 0 0px rgba(122,167,255,0)"}}, '
           f'{{boxShadow:"0 0 0 4px rgba(122,167,255,0.9)",duration:0.4,ease:"power2.out"}}, 25.55);']
    c.move(1075, 309, 25.4, 0.9)                    # Open Anyway
    js.append(f'tl.to("#{sid}-open", {{backgroundColor:"rgba(255,255,255,0.32)",duration:0.1}}, 26.5);')
    c.click(26.55)
    js += [f'tl.to("#{sid}-blocked", {{boxShadow:"0 0 0 0px rgba(122,167,255,0)",duration:0.3}}, 26.8);',
           f'tl.fromTo("#{sid}-a2", {{opacity:0,scale:0.9}}, {{opacity:1,scale:1,duration:0.35,ease:"back.out(1.5)"}}, 26.85);',
           f'tl.fromTo("#{sid}-ss", {{filter:"brightness(1)"}}, {{filter:"brightness(0.7)",duration:0.3,immediateRender:false}}, 26.85);']
    c.move(600, 452, 27.3, 0.75)                    # Open Anyway (default)
    js.append(f'tl.to("#{sid}-a2-b0", {{filter:"brightness(1.25)",duration:0.1}}, 28.1);')
    c.click(28.15)
    c.move(940, 640, 28.35, 0.6)
    js += [f'tl.set("#{sid}-a2", {{opacity:0}}, 28.4);',
           f'tl.set("#{sid}-auth", {{opacity:1}}, 28.4);',
           f'tl.fromTo("#{sid}-auth", {{scale:0.94}}, {{scale:1,duration:0.35,ease:"back.out(1.5)"}}, 28.4);',
           f'tl.fromTo("#{sid}-dots", {{clipPath:"inset(0 100% 0 0)"}}, {{clipPath:"inset(0 0% 0 0)",duration:0.9,ease:"steps(8)"}}, 29.0);',
           f'tl.fromTo("#{sid}-fp", {{scale:1}}, {{scale:1.08,duration:0.25,yoyo:true,repeat:1}}, 29.4);',
           f'tl.fromTo("#{sid}-fpok", {{opacity:0,scale:0.4}}, {{opacity:1,scale:1,duration:0.35,ease:"back.out(2)"}}, 30.0);',
           f'tl.to("#{sid}-auth", {{opacity:0,scale:0.96,duration:0.25,ease:"power2.in"}}, 30.7);',
           f'tl.to("#{sid}-ss", {{filter:"brightness(1)",duration:0.3}}, 30.7);',
           f'tl.to("#cur-{sid}", {{opacity:0,duration:0.2}}, 30.8);']
    return body


def rd_reopen(sid, st, js):
    """68.6-70.6: Applications -> double-click Notchy -> Settings opens."""
    body = finder_window(sid, show_apps=True) + CURSOR.format(sid=sid)
    js.append(f'tl.fromTo("#cur-{sid}", {{opacity:0}}, {{opacity:1,duration:0.15}}, {st + 0.2});')
    c = Cur(sid, js, 900, 560, st)
    c.move(785, 205, st + 0.25, 0.75)
    js.append(f'tl.to("#{sid}-app-notchy", {{backgroundColor:"rgba(122,167,255,0.22)",duration:0.1}}, {st + 1.05});')
    c.click(st + 1.1); c.click(st + 1.3)
    js.append(f'tl.fromTo("#{sid}-app-notchy", {{scale:1}}, {{scale:1.08,duration:0.18,yoyo:true,repeat:1}}, {st + 1.35});')
    return body


def rd_trash(sid, st, js):
    """78.4-81.6: drag Notchy from Applications to the Trash."""
    body = finder_window(sid, show_apps=True, trash=True) + CURSOR.format(sid=sid)
    js.append(f'tl.fromTo("#cur-{sid}", {{opacity:0}}, {{opacity:1,duration:0.15}}, {st + 0.15});')
    c = Cur(sid, js, 900, 560, st)
    c.move(785, 205, st + 0.2, 0.6)
    js += [f'tl.to("#{sid}-app-notchy", {{backgroundColor:"rgba(122,167,255,0.22)",duration:0.1}}, {st + 0.85});',
           f'tl.set("#{sid}-ghost", {{x:733,y:150,opacity:0}}, {st});',
           f'tl.to("#{sid}-ghost", {{opacity:0.75,duration:0.12}}, {st + 0.95});',
           f'tl.to("#{sid}-ghost", {{x:1072,y:612,duration:1.0,ease:"power2.inOut"}}, {st + 1.0});',
           f'tl.to("#{sid}-trash", {{scale:1.15,duration:0.2}}, {st + 1.8});']
    c.move(1123, 662, st + 1.0, 1.0)
    js += [f'tl.to("#{sid}-ghost", {{opacity:0,scale:0.3,duration:0.25,ease:"power2.in"}}, {st + 2.1});',
           f'tl.to("#{sid}-app-notchy", {{opacity:0,duration:0.25}}, {st + 2.1});',
           f'tl.to("#{sid}-trash", {{scale:1,duration:0.3,ease:"back.out(2)"}}, {st + 2.15});']
    return body


RD = {"github": rd_github, "finder": rd_finder, "reopen": rd_reopen, "trash": rd_trash}

# overlays drawn inside footage cams (source coordinates): (shot, kind, x, y, w, h, t_in, t_out)
RINGS = [
    ("w3", 2085, 6, 74, 58, 50.25, 51.9),            # the new menu-bar icon (16:9 only; off-frame in 9:16)
    ("sg", 384 - 6, 209 - 4, 851 + 12, 73 + 8, 53.75, 59.4),   # coding-agent integration row (card coords)
    ("sg", 384 - 6, 137 - 4, 851 + 12, 72 + 8, 59.6, 62.4),    # Start at login row
    ("cm", 950, 82, 268, 44, 64.6, 66.2),            # "Settings…" item
    ("to", 648 - 6, 674 - 6, 220 + 12, 56 + 12, 74.6, 76.6),  # "Turn Off" (card coords)
    ("cq", 950, 152, 268, 44, 77.0, 78.4),           # "Quit Notchy"
]


def words(text):
    return "".join(f'<span class="w">{html.escape(w)}</span> ' for w in text.split(" ")).strip()


def cam_xy(cam, aspect, bw, which):
    s0, s1, ax = CAM[cam][aspect]
    s = (s0, s1)[which]
    sw = SRC[cam][0]
    x = bw / 2 - ax * s
    x = min(0, max(bw - sw * s, x))
    return round(x, 1), 0, s


def build(aspect):
    A = ASPECTS[aspect]
    W, Hh = A["W"], A["H"]
    bx, by, bw, bh = A["box"]
    is9 = aspect == "9x16"
    out, js = [], []
    ss, sx, sy = A["stage"]

    for n, (sid, kind, st, en, tr, p) in enumerate(SHOTS):
        z = 10 + n
        track = 1 + (n % 2)
        dur = round(en - st, 3)
        # media outlives the shot by the push length so the outgoing frame is still there while it slides out
        tail = XF if (n + 1 < len(SHOTS) and SHOTS[n + 1][4] == "push") else 0
        timing = f'data-start="{st}" data-duration="{round(dur + tail, 3)}"'
        if kind == "rd":
            bgx = round(bw / 2 - 960 * BG_S, 1)
            body = RD[p["rd"]](sid, st, js)
            mbss = ('<div class="mbapp" id="fd-mbss"><b>System Settings</b><span>Edit</span><span>View</span>'
                    '<span>Window</span><span>Help</span></div>') if sid == "fd" else ""
            inner = (f'<div class="rdbg" style="width:1920px;height:1080px;transform:translate({bgx}px,0) scale({BG_S})">{mbss}</div>'
                     f'<div class="stage" style="transform:translate({sx}px,{sy}px) scale({ss})">{body}</div>')
        else:
            src = p["src"]
            cam = p["cam"]
            if kind == "video":
                media = (f'<video id="v-{sid}" class="clip" src="media/{src}" {timing} data-media-start="{p.get("ms", 0)}" '
                         f'data-track-index="{track}" muted playsinline></video>')
            else:
                media = f'<img id="v-{sid}" class="clip" src="media/{src}" {timing} data-track-index="{track}" alt="" />'
            rings = "".join(
                f'<div class="ring" id="ring-{sid}-{i}" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px"></div>'
                for i, (rs, x, y, w, h, a, b) in enumerate(RINGS) if rs == sid)
            if cam == "set":
                cx, cy, cw, ch = SET_CROP
                s0, s1, ax, ay = A["card"]
                chips = ""
                if sid == "sg" and not is9:
                    chips = f'''<div class="chips" id="chips">
  <div class="chip" id="chip0"><div class="file"><span>{{ }}</span></div><div><b>settings.json</b><span>Notchy hooks added</span></div></div>
  <div class="chip" id="chip1"><div class="file bak"><span>{{ }}</span></div><div><b>settings.json.notchy-bak-20261116-094112</b><span>Your old file, saved first</span></div></div>
</div>'''
                inner = (f'<div class="rdbg" style="width:1920px;height:1080px;transform:translate({round(bw / 2 - 960 * BG_S, 1)}px,0) scale({BG_S})"></div>'
                         f'<div class="cam win card" id="cam-{sid}" style="width:{cw}px;height:{ch}px">'
                         f'<div class="crop" style="left:-{cx}px;top:-{cy}px;width:{DESK[0]}px;height:{DESK[1]}px">{media}</div>'
                         f'<div class="rings" >{rings}</div></div>{chips}')
                x0, y0 = round(ax - cw * s0 / 2, 1), round(ay - ch * s0 / 2, 1)
                x1, y1 = round(ax - cw * s1 / 2, 1), round(ay - ch * s1 / 2, 1)
            else:
                swh = SRC[cam]
                extra = ""
                if sid == "mb":
                    extra = f'''<div class="nmenu" id="mbmenu" style="left:2096px;top:64px">
<div class="nmi" id="mbset"><span class="gear">&#9881;</span>Settings…</div><div class="nmsep"></div><div class="nmi">Quit Notchy</div></div>
{CURSOR.format(sid=sid).replace('class="cursor"', 'class="cursor src"')}'''
                inner = (f'<div class="cam" id="cam-{sid}" style="width:{swh[0]}px;height:{swh[1]}px">'
                         f'<div class="crop" style="left:0;top:0;width:{swh[0]}px;height:{swh[1]}px">{media}</div>{rings}{extra}</div>')
                x0, y0, s0 = cam_xy(cam, aspect, bw, 0)
                x1, y1, s1 = cam_xy(cam, aspect, bw, 1)
            js.append(f'tl.fromTo("#cam-{sid}", {{x:{x0},y:{y0},scale:{s0}}}, {{x:{x1},y:{y1},scale:{s1},duration:{dur},ease:"sine.inOut"}}, {st});')
            for i, (rs, x, y, w, h, a, b) in enumerate(RINGS):
                if rs == sid:
                    js.append(f'tl.fromTo("#ring-{sid}-{i}", {{opacity:0,scale:1.12}}, {{opacity:1,scale:1,duration:0.4,ease:"power3.out"}}, {a});')
                    js.append(f'tl.to("#ring-{sid}-{i}", {{opacity:0,duration:0.2}}, {b - 0.2});')
            if sid == "sg" and not is9:
                js.append('tl.fromTo("#chip0", {opacity:0,x:40}, {opacity:1,x:0,duration:0.55,ease:"expo.out"}, 54.1);')
                js.append('tl.fromTo("#chip1", {opacity:0,x:40}, {opacity:1,x:0,duration:0.55,ease:"back.out(1.4)"}, 56.25);')
                js.append('tl.to("#chips", {opacity:0,duration:0.3}, 59.3);')
            if sid == "mb":
                js += ['tl.set("#cur-mb", {x:2200,y:160}, 66.2);',
                       'tl.fromTo("#cur-mb", {opacity:0}, {opacity:1,duration:0.15}, 66.35);',
                       'tl.to("#cur-mb", {x:2124,y:30,duration:0.5,ease:"power2.inOut"}, 66.4);',
                       'tl.to("#cur-mb", {scale:0.8,duration:0.07,yoyo:true,repeat:1}, 66.95);',
                       'tl.fromTo("#mbmenu", {opacity:0,y:-8}, {opacity:1,y:0,duration:0.2,ease:"power2.out"}, 67.05);',
                       'tl.to("#cur-mb", {x:2170,y:96,duration:0.45,ease:"power2.inOut"}, 67.35);',
                       'tl.to("#mbset", {backgroundColor:"#2f6fe0",duration:0.1}, 67.75);']
        out.append(f'<div class="shot" id="shot-{sid}" style="z-index:{z}">{inner}</div>')
        js.append(f'tl.fromTo("#shot-{sid}", {{opacity:0}}, {{opacity:1,duration:{XF if (n > 0 and tr == "fade") else 0.01}}}, {st});')
        if n > 0 and tr == "push":
            prev = SHOTS[n - 1][0]
            js.append(f'tl.fromTo("#shot-{sid}", {{x:{bw}}}, {{x:0,duration:{XF},ease:"power3.inOut"}}, {st});')
            js.append(f'tl.fromTo("#shot-{prev}", {{x:0}}, {{x:{-round(bw * 0.35)},duration:{XF},ease:"power3.inOut",immediateRender:false}}, {st});')
        js.append(f'tl.to("#shot-{sid}", {{opacity:0,duration:0.01}}, {en if n + 1 == len(SHOTS) else round(en + (XF if SHOTS[n + 1][4] == "push" else 0), 3)});')

    # title-card icon
    js.append('tl.fromTo("#t0icon", {opacity:0,scale:0.7,y:30}, {opacity:1,scale:1,y:0,duration:0.8,ease:"back.out(1.5)"}, 0.25);')
    js.append('tl.fromTo("#t0glow", {opacity:0,scale:0.6}, {opacity:1,scale:1,duration:1.4,ease:"sine.out"}, 0.35);')

    # captions
    ctrack = {"H": 20, "S": 22}
    flip = {"H": 0, "S": 0}
    for i, c in enumerate(CAPS):
        cid = f"cap{i}"
        if c[0] == "H":
            _, groups, end, style, can_stack = c
            st = groups[0][1]
            parts = []
            for gi, (text, t, cls, wt) in enumerate(groups):
                parts.append(f'<span class="g {cls}" id="{cid}g{gi}">{words(text)}</span>')
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
    e = END
    out.append(f'''<div id="endcard" class="clip" data-start="{e}" data-duration="{round(DUR - e, 3)}" data-track-index="5">
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
        f'tl.fromTo("#pill", {{width:{"240" if not is9 else "220"},height:58,borderRadius:"0 0 26px 26px",y:-40}}, '
        f'{{width:{"780" if not is9 else "820"},height:{"210" if not is9 else "230"},borderRadius:"60px",y:0,duration:0.75,ease:"expo.inOut"}}, {e + 0.05});',
        f'tl.fromTo("#wordmark", {{opacity:0,scale:0.86,filter:"blur(10px)"}}, {{opacity:1,scale:1,filter:"blur(0px)",duration:0.6,ease:"power3.out"}}, {e + 0.45});',
        f'tl.fromTo(".glow", {{opacity:0,scale:0.7}}, {{opacity:1,scale:1,duration:1.6,ease:"sine.out"}}, {e + 0.4});',
        f'tl.fromTo("#ec1", {{opacity:0,y:24}}, {{opacity:1,y:0,duration:0.55,ease:"power3.out"}}, {e + 0.95});',
        f'tl.fromTo("#ec2", {{opacity:0,y:24}}, {{opacity:1,y:0,duration:0.55,ease:"back.out(1.4)"}}, {e + 1.55});',
        f'tl.fromTo("#ec3", {{opacity:0,y:24}}, {{opacity:1,y:0,duration:0.55,ease:"expo.out"}}, {e + 2.15});',
        f'tl.fromTo("#ec4", {{opacity:0}}, {{opacity:1,duration:0.6,ease:"sine.out"}}, {e + 2.7});',
        f'tl.fromTo("#fade", {{opacity:0}}, {{opacity:1,duration:0.7,ease:"sine.in"}}, {DUR - 0.7});',
    ]

    t0icon = (f'<div id="t0glow"></div><div id="t0icon">{appicon("big")}</div>')
    css = CSS_BASE.format(W=W, H=Hh, bx=bx, by=by, bw=bw, bh=bh, accent=ACCENT,
                          mask="-webkit-mask-image:linear-gradient(180deg,#000 0,#000 86%,transparent 100%);" if is9 else "",
                          brand="" if is9 else "display:none;", band=0 if is9 else 460, halo_top=1260 if is9 else 0,
                          halo_disp="" if is9 else "display:none;", cap_w=A["cap_w"], cap_half=A["cap_w"] // 2,
                          head_bottom=Hh - A["head_bottom"], head_px=A["head_px"], sub_top=A["sub_top"], sub_px=A["sub_px"],
                          stack=".head.stack .g { display:block; } .head.problem { font-size:68px; }" if is9 else "",
                          glow_top=780 if is9 else 330, ec_just="flex-start" if is9 else "center", ec_gap=30 if is9 else 22,
                          ec_pad="470px 60px 0" if is9 else "0 120px", pill_mb=24 if is9 else 26, wm=132 if is9 else 124,
                          l1=46 if is9 else 44, l2=66 if is9 else 64, l3=40 if is9 else 42, l4w=900 if is9 else 1400,
                          t0x=bw // 2, t0y=(470 if is9 else 400)) + CSS_RD
    shots_html = "\n".join(o for o in out if o.startswith('<div class="shot"'))
    rest = "\n".join(o for o in out if not o.startswith('<div class="shot"'))
    doc = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width={W}, height={Hh}" />
<!-- generated by video/install/build.py — edit the plan there, not this file -->
<script src="https://cdn.jsdelivr.net/npm/gsap@3.15.0/dist/gsap.min.js"></script>
<style>{css}</style>
</head>
<body>
<div id="root" data-composition-id="main" data-start="0" data-duration="{DUR}" data-width="{W}" data-height="{Hh}">
<div id="halo"></div>
<div id="brand">Notchy<i></i></div>
<div id="screen">
{shots_html}
<div id="t0wrap">{t0icon}</div>
</div>
<div id="band"></div>
{rest}
<div id="fade"></div>
</div>
<script>
window.__timelines = window.__timelines || {{}};
const tl = gsap.timeline({{ paused: true }});
{chr(10).join(j for j in js if j)}
tl.to("#t0wrap", {{opacity:0,duration:0.01}}, 4.6);
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
                    ("meta.json", {"id": f"notchy-install-{aspect}", "name": f"Notchy install {aspect}"})):
        p = os.path.join(d, f)
        if not os.path.exists(p):
            json.dump(body, open(p, "w"), indent=2)
    print("wrote", d)


CSS_BASE = '''
:root {{ --accent:{accent}; --ink:#F5F7FA; --muted:#AEB7C7; --ground:#05060A;
  --font:-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif;
  --mono:"SF Mono", ui-monospace, Menlo, monospace; }}
* {{ margin:0; padding:0; box-sizing:border-box; }}
html, body {{ width:{W}px; height:{H}px; overflow:hidden; background:var(--ground); }}
#root {{ position:relative; width:{W}px; height:{H}px; overflow:hidden; background:var(--ground); font-family:var(--font); color:var(--ink); }}
#screen {{ position:absolute; left:{bx}px; top:{by}px; width:{bw}px; height:{bh}px; overflow:hidden; background:#0b0d14; {mask} }}
.shot {{ position:absolute; inset:0; overflow:hidden; }}
.cam {{ position:absolute; left:0; top:0; transform-origin:0 0; will-change:transform; }}
.cam video, .cam img {{ display:block; width:100%; height:100%; }}
.crop {{ position:absolute; }}
.win.card {{ overflow:hidden; border-radius:22px; box-shadow:0 40px 120px rgba(0,0,0,0.55), 0 0 0 1px rgba(255,255,255,0.08); }}
.rings {{ position:absolute; inset:0; }}
.ring {{ position:absolute; border-radius:16px; border:5px solid var(--accent); opacity:0;
  box-shadow:0 0 28px rgba(122,167,255,0.75), inset 0 0 18px rgba(122,167,255,0.25); }}
.rdbg {{ position:absolute; left:0; top:0; transform-origin:0 0; background:#0b0d14 url(media/closed-notch.png) 0 0 / 100% 100% no-repeat; }}
#t0wrap {{ position:absolute; inset:0; z-index:60; pointer-events:none; }}
#t0icon {{ position:absolute; left:{t0x}px; top:{t0y}px; width:0; height:0; }}
#t0icon .appicon {{ position:absolute; left:-110px; top:-110px; }}
#t0glow {{ position:absolute; left:{t0x}px; top:{t0y}px; width:900px; height:900px; margin:-450px 0 0 -450px;
  background:radial-gradient(closest-side, rgba(122,167,255,0.28), rgba(122,167,255,0) 70%); }}
#brand {{ position:absolute; left:0; right:0; top:118px; text-align:center; z-index:5; font-size:40px; font-weight:700;
  letter-spacing:-0.03em; color:rgba(245,247,250,0.55); {brand} }}
#brand i {{ display:inline-block; width:12px; height:12px; border-radius:6px; background:var(--accent); margin-left:8px;
  vertical-align:middle; box-shadow:0 0 18px rgba(122,167,255,0.8); }}
#band {{ position:absolute; left:0; right:0; bottom:0; height:{band}px; z-index:95;
  background:linear-gradient(180deg, rgba(5,6,10,0) 0%, rgba(5,6,10,0.72) 45%, rgba(5,6,10,0.9) 100%); }}
#halo {{ position:absolute; left:50%; top:{halo_top}px; width:1400px; height:900px; margin-left:-700px; z-index:1;
  background:radial-gradient(closest-side, rgba(122,167,255,0.16), rgba(122,167,255,0) 70%); {halo_disp} }}
.head, .sub {{ position:absolute; left:50%; width:{cap_w}px; margin-left:-{cap_half}px; text-align:center; z-index:100; }}
.head {{ bottom:{head_bottom}px; font-size:{head_px}px; font-weight:700; line-height:1.08; letter-spacing:-0.025em;
  text-shadow:0 2px 24px rgba(0,0,0,0.55); text-wrap:balance; }}
{stack}
.head .w {{ display:inline-block; }}
.head .accent {{ color:var(--accent); }}
.head .mute {{ color:var(--muted); }}
.head.problem {{ color:#C9D0DC; font-weight:600; }}
.sub {{ top:{sub_top}px; font-size:{sub_px}px; font-weight:500; line-height:1.2; color:#D7DEEA; letter-spacing:-0.005em;
  text-shadow:0 2px 16px rgba(0,0,0,0.6); text-wrap:balance; }}
#endcard {{ position:absolute; inset:0; z-index:200; background:var(--ground); }}
#endcard .glow {{ position:absolute; left:50%; top:{glow_top}px; width:1300px; height:900px; margin:-450px 0 0 -650px;
  background:radial-gradient(closest-side, rgba(122,167,255,0.22), rgba(122,167,255,0) 72%); }}
#endcard .ec {{ position:absolute; inset:0; display:flex; flex-direction:column; align-items:center;
  justify-content:{ec_just}; gap:{ec_gap}px; padding:{ec_pad}; }}
.pill {{ display:flex; align-items:center; justify-content:center; background:#000; overflow:hidden;
  box-shadow:0 0 0 1.5px rgba(122,167,255,0.45), 0 30px 90px rgba(122,167,255,0.18); margin-bottom:{pill_mb}px; }}
#wordmark {{ font-size:{wm}px; font-weight:700; letter-spacing:-0.045em; color:var(--ink); }}
.l1 {{ font-size:{l1}px; font-weight:500; color:#D7DEEA; }}
.l2 {{ font-size:{l2}px; font-weight:700; letter-spacing:-0.02em; color:var(--ink); }}
.l3 {{ font-size:{l3}px; font-weight:600; color:var(--accent); font-family:var(--mono); letter-spacing:-0.01em; }}
.l4 {{ font-size:34px; font-weight:500; color:var(--muted); text-align:center; max-width:{l4w}px; }}
#fade {{ position:absolute; inset:0; background:#000; opacity:0; z-index:300; pointer-events:none; }}
'''

CSS_RD = '''
/* ---- redraws (stage 1200x760) ---- */
.mbapp { position:absolute; left:0; top:0; width:790px; height:65px; opacity:0; display:flex; align-items:center; gap:41px;
  padding-left:37px; font-size:25px; color:#fff; font-family:var(--font);
  background:linear-gradient(90deg, rgb(46,59,97), rgb(46,60,98) 300px, rgb(44,59,93) 700px, rgb(44,59,93)); }
.mbapp b { font-weight:700; }
.stage { position:absolute; left:0; top:0; width:1200px; height:760px; transform-origin:0 0; font-family:var(--font); }
.stage .win { position:absolute; overflow:hidden; border-radius:18px; background:#1e1f24;
  box-shadow:0 40px 110px rgba(0,0,0,0.55), 0 0 0 1px rgba(255,255,255,0.10); }
.lights { display:flex; gap:10px; }
.lights i { width:15px; height:15px; border-radius:50%; display:block; }
.nav { color:#8b93a1; font-size:30px; line-height:1; }
.cursor { position:absolute; left:0; top:0; z-index:50; transform-origin:2px 2px; filter:drop-shadow(0 3px 6px rgba(0,0,0,0.45)); }
.cursor.src { width:44px; height:62px; }
.appicon { position:relative; width:104px; height:104px; border-radius:24px; background:linear-gradient(160deg,#20232c,#06070b 70%);
  box-shadow:0 6px 16px rgba(0,0,0,0.45), inset 0 0 0 1.5px rgba(255,255,255,0.10); }
.appicon i { position:absolute; left:22px; top:30px; width:60px; height:44px; border:5px solid var(--accent); border-radius:10px; }
.appicon i::after { content:""; position:absolute; left:4px; right:4px; top:5px; height:5px; border-radius:3px; background:var(--accent); }
.appicon.sm { width:84px; height:84px; border-radius:20px; margin:0 auto 14px; }
.appicon.sm i { left:18px; top:24px; width:48px; height:36px; border-width:4px; border-radius:8px; }
.appicon.sm i::after { top:4px; height:4px; }
.appicon.big { width:220px; height:220px; border-radius:50px; box-shadow:0 30px 80px rgba(0,0,0,0.5), 0 0 0 2px rgba(122,167,255,0.35); }
.appicon.big i { left:46px; top:62px; width:128px; height:96px; border-width:9px; border-radius:20px; }
.appicon.big i::after { left:9px; right:9px; top:10px; height:10px; border-radius:5px; }
.zipicon { position:relative; width:84px; height:104px; margin:0 10px; border-radius:8px 26px 8px 8px; background:linear-gradient(180deg,#f2f4f8,#d7dbe3); }
.zipicon b { position:absolute; left:36px; top:0; width:12px; height:60px;
  background:repeating-linear-gradient(180deg,#6f7683 0 6px,#f2f4f8 6px 12px); }
.zipicon span { position:absolute; left:0; right:0; bottom:10px; text-align:center; font-size:17px; font-weight:800; color:#5a616e; letter-spacing:0.08em; }
.gicon { width:104px; height:104px; border-radius:24px; display:flex; align-items:center; justify-content:center;
  font-size:52px; font-weight:700; color:rgba(255,255,255,0.92); box-shadow:0 6px 16px rgba(0,0,0,0.35), inset 0 0 0 1.5px rgba(255,255,255,0.12); }
/* browser */
.browser { left:0; top:0; width:1200px; height:760px; background:#0d1117; }
.bbar { height:66px; display:flex; align-items:center; gap:26px; padding:0 22px; background:#24262c; border-bottom:1px solid #30333b; }
.addr { flex:1; margin:0 30px; height:40px; border-radius:11px; background:#16181d; color:#c9d1d9; font-size:21px;
  display:flex; align-items:center; justify-content:center; gap:10px; letter-spacing:-0.005em; }
.lock { width:13px; height:11px; border-radius:2px; background:#8b93a1; position:relative; top:2px; }
.lock::before { content:""; position:absolute; left:2px; top:-8px; width:5px; height:7px; border:2px solid #8b93a1; border-bottom:0; border-radius:5px 5px 0 0; }
.dlbtn { width:40px; height:40px; }
.ghpage { padding:0 46px; color:#e6edf3; }
.ghhead { height:74px; display:flex; align-items:center; gap:22px; font-size:24px; }
.ghhead b { font-size:27px; letter-spacing:-0.02em; }
.crumb { color:#c9d1d9; } .crumb i { color:#6e7681; font-style:normal; margin:0 4px; } .crumb strong { color:#fff; }
.pub { font-size:16px; color:#9198a1; border:1px solid #3d444d; border-radius:20px; padding:2px 11px; }
.ghtabs { display:flex; gap:34px; font-size:20px; color:#9198a1; border-bottom:1px solid #30363d; height:48px; align-items:center; }
.ghtabs .on { color:#e6edf3; font-weight:600; position:relative; }
.ghtabs .on::after { content:""; position:absolute; left:-6px; right:-6px; bottom:-15px; height:3px; border-radius:2px; background:#f78166; }
.rel { margin-top:26px; border:1px solid #30363d; border-radius:12px; padding:24px 30px; }
.reltitle { font-size:38px; font-weight:700; letter-spacing:-0.02em; display:flex; align-items:center; gap:16px; }
.latest { font-size:16px; font-weight:600; color:#3fb950; border:1.5px solid #238636; border-radius:20px; padding:2px 12px; letter-spacing:0; }
.relmeta { margin-top:8px; font-size:18px; color:#9198a1; display:flex; align-items:center; gap:10px; }
.avatar { width:24px; height:24px; border-radius:50%; background:linear-gradient(135deg,#7AA7FF,#3b4b7a); }
.relnotes { margin-top:16px; font-size:20px; line-height:1.5; color:#c9d1d9; }
.relnotes b { color:#e6edf3; }
.assets { margin-top:20px; border-top:1px solid #30363d; padding-top:14px; }
.ahead { font-size:21px; font-weight:600; margin-bottom:8px; }
.cnt { font-size:15px; background:#30363d; border-radius:12px; padding:1px 9px; margin-left:6px; }
.asset { height:50px; display:flex; align-items:center; gap:14px; padding:0 14px; border:1px solid #30363d; border-radius:8px; margin-top:-1px; font-size:20px; color:#c9d1d9; }
.asset.hot .aname { color:#4493f8; font-weight:600; }
.zipmini { width:18px; height:22px; border-radius:3px; background:repeating-linear-gradient(180deg,#9198a1 0 3px,transparent 3px 6px) 7px 0/4px 12px no-repeat, #30363d; }
.srcmini { width:18px; height:22px; border-radius:3px; background:#30363d; }
.dlpop { position:absolute; right:16px; top:76px; width:360px; padding:16px 18px; display:flex; align-items:center; gap:14px; opacity:0;
  background:#2a2c33; border-radius:14px; box-shadow:0 18px 50px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.1); }
.dlpop .zipicon { width:44px; height:54px; margin:0; border-radius:5px 13px 5px 5px; }
.dlpop .zipicon b { left:18px; width:7px; height:30px; background:repeating-linear-gradient(180deg,#6f7683 0 4px,#f2f4f8 4px 8px); }
.dlpop .zipicon span { font-size:10px; bottom:5px; }
.dlpop div:nth-child(2) { flex:1; display:flex; flex-direction:column; gap:2px; }
.dlpop b { font-size:21px; color:#fff; } .dlpop span { font-size:17px; color:#9aa3b2; }
.dlpop em { font-style:normal; font-size:26px; color:#3fb950; }
/* finder */
.finder { left:50px; top:40px; width:1100px; height:680px; display:flex; background:#1e1f24; }
.fside { width:250px; background:#2a2b31; padding:22px 14px; border-right:1px solid #34353c; }
.sbh { margin:30px 10px 10px; font-size:16px; font-weight:600; color:#8b919c; }
.sbi { height:44px; display:flex; align-items:center; gap:12px; padding:0 12px; border-radius:9px; font-size:21px; color:#e8eaee; }
.sbi.sel { background:rgba(255,255,255,0.13); }
.fold { width:24px; height:18px; border-radius:3px; border:2.5px solid var(--accent); position:relative; }
.fmain { flex:1; position:relative; }
.fbar { height:70px; display:flex; align-items:center; gap:24px; padding:0 26px; border-bottom:1px solid #2f3037; font-size:24px; position:relative; }
.fbar b { font-weight:700; color:#f2f3f5; }
.fbar .t2 { position:absolute; left:106px; font-weight:700; color:#f2f3f5; opacity:0; }
.fgrid { position:absolute; left:20px; top:100px; right:20px; display:flex; flex-wrap:wrap; gap:26px 30px; }
.fitem { width:160px; padding:10px 0 8px; border-radius:14px; display:flex; flex-direction:column; align-items:center; gap:10px; font-size:19px; color:#e8eaee; }
.fitem > div:first-child { margin:0 auto; }
#fd-app { opacity:0; }
.ghost { position:absolute; left:0; top:0; z-index:40; opacity:0; pointer-events:none; }
.trash { position:absolute; left:1060px; top:590px; width:126px; height:150px; border-radius:24px; z-index:30;
  background:rgba(40,42,50,0.85); box-shadow:0 20px 60px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.12);
  display:flex; flex-direction:column; align-items:center; justify-content:center; gap:6px; color:#e8eaee; font-size:18px; }
/* alerts */
.alert, .auth { position:absolute; left:350px; top:170px; width:500px; padding:30px 34px 26px; text-align:center; z-index:30; opacity:0;
  background:rgba(44,45,52,0.97); border-radius:26px; box-shadow:0 40px 120px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.12); }
.atitle { font-size:25px; font-weight:700; color:#f4f5f7; letter-spacing:-0.01em; }
.abody { margin-top:12px; font-size:19px; line-height:1.42; color:#d0d4db; }
.abtns { margin-top:22px; display:flex; flex-direction:column; gap:12px; }
.abtn { height:46px; border-radius:12px; background:rgba(255,255,255,0.13); color:#f4f5f7; font-size:20px; font-weight:500;
  display:flex; align-items:center; justify-content:center; }
.abtn.def { background:#2a6ff0; color:#fff; font-weight:600; }
.auth { top:150px; }
.fp { position:relative; width:88px; height:88px; margin:0 auto 12px; }
.fpok { position:absolute; right:-8px; bottom:-4px; width:38px; height:38px; border-radius:50%; background:#30c050; color:#fff;
  font-size:24px; font-weight:700; display:flex; align-items:center; justify-content:center; opacity:0; }
.pwd { margin:18px auto 0; height:46px; border-radius:10px; background:rgba(0,0,0,0.35); box-shadow:inset 0 0 0 1px rgba(255,255,255,0.14);
  display:flex; align-items:center; padding:0 16px; color:#e8eaee; font-size:18px; letter-spacing:4px; }
/* system settings */
.ss { left:0; top:0; width:1200px; height:760px; display:flex; z-index:20; opacity:0; background:#1e1f24; }
.ssside { width:330px; background:#26272d; padding:22px 14px; border-right:1px solid #34353c; }
.sssearch { margin:22px 6px 14px; height:38px; border-radius:9px; background:rgba(255,255,255,0.07); color:#8b919c; font-size:18px; display:flex; align-items:center; padding:0 12px; }
.ssi { height:36px; display:flex; align-items:center; gap:12px; padding:0 10px; border-radius:8px; font-size:19px; color:#e8eaee; }
.ssgap { height:10px; }
.sq { width:24px; height:24px; border-radius:6px; flex:none; }
.ssmain { flex:1; display:flex; flex-direction:column; }
.sstitle { height:70px; display:flex; align-items:center; gap:24px; padding:0 28px; font-size:24px; color:#f2f3f5; border-bottom:1px solid #2f3037; }
.ssview { position:relative; flex:1; overflow:hidden; }
.ssscroll { position:absolute; left:28px; right:28px; top:22px; }
.ssgroup { background:rgba(255,255,255,0.05); border-radius:14px; overflow:visible; margin-bottom:22px; }
.ssrow { height:52px; display:flex; align-items:center; gap:14px; padding:0 18px; font-size:20px; color:#e8eaee; border-bottom:1px solid rgba(255,255,255,0.06); position:relative; }
.ssrow em { margin-left:auto; font-style:normal; color:#8b919c; }
.ssrow.tall { height:76px; }
.ssrow .pop { margin-left:auto; font-size:18px; color:#d0d4db; background:rgba(255,255,255,0.1); border-radius:8px; padding:6px 12px; }
.ssrow.blocked { border-radius:12px; }
.pbtn { margin-left:auto; font-size:19px; color:#fff; background:rgba(255,255,255,0.16); border-radius:9px; padding:8px 18px; font-weight:500; }
.sshead { font-size:21px; font-weight:700; color:#f2f3f5; margin:8px 4px 12px; }
/* drawn Notchy menu (menu-bar close-up), sized like the real one in the 2x frame */
.nmenu { position:absolute; width:250px; padding:7px; border-radius:14px; background:rgba(40,41,46,0.97); opacity:0;
  box-shadow:0 12px 34px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.12); font-family:var(--font); }
.nmi { height:36px; display:flex; align-items:center; gap:10px; padding:0 12px; border-radius:8px; font-size:22px; color:#f0f1f3; }
.gear { font-size:22px; color:#d0d4db; }
.nmsep { height:1px; margin:6px 12px; background:rgba(255,255,255,0.14); }
/* Settings chips (16:9) */
.chips { position:absolute; left:1395px; top:300px; width:500px; display:flex; flex-direction:column; gap:22px; }
.chip { display:flex; gap:18px; align-items:center; padding:18px 20px; border-radius:18px; opacity:0;
  background:rgba(20,22,30,0.82); box-shadow:0 20px 60px rgba(0,0,0,0.45), 0 0 0 1px rgba(122,167,255,0.35); }
.chip .file { width:54px; height:66px; flex:none; border-radius:6px 16px 6px 6px; background:#e9edf4; display:flex; align-items:center; justify-content:center; }
.chip .file span { font-family:var(--mono); font-size:18px; font-weight:700; color:#3b4b7a; }
.chip .file.bak { background:#c9d2e3; }
.chip div:last-child { display:flex; flex-direction:column; gap:4px; min-width:0; }
.chip b { font-family:var(--mono); font-size:19px; color:#fff; font-weight:600; word-break:break-all; }
.chip span { font-size:20px; color:#AEB7C7; }
'''

if __name__ == "__main__":
    for a in ASPECTS:
        build(a)
