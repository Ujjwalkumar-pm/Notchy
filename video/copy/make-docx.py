#!/usr/bin/env python3
"""Build Notchy-Launch-Post-Copy.docx (LinkedIn + Instagram copy, alt text, pre-post checklist).

Usage: video/.venv/bin/python video/copy/make-docx.py [out.docx]
Needs python-docx (installed by video/requirements.txt; see video/README.md).
Facts follow the fact-check columns in video/script/launch.md and install.md.
"""
import sys
from pathlib import Path

from docx import Document
from docx.enum.text import WD_BREAK
from docx.shared import Pt, RGBColor

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / "Desktop/Notchy-Launch-Kit/Notchy-Launch-Post-Copy.docx"
REPO = "github.com/Ujjwalkumar-pm/Notchy"

LINKEDIN_LAUNCH = f"""The notch on my MacBook sat there doing nothing all day.

Small things kept slipping. My AI coding agent would wait for my permission in a terminal I had moved away from. A meeting would start while I was deep in a document. Teams and Outlook pinged from behind other windows.

I built Notchy to put those things in the one spot I always see - the top of the screen.

What it does:

1. Agent approvals at the notch. When your AI coding agent needs permission, a card slides out of the notch. Rest your pointer on it to arm Allow once, then click.

2. Meeting reminders with a Join button, one minute before any meeting that has a join link. The Calendar tab counts down to the next one.

3. Teams and Outlook alerts without switching apps. Messages and unread counts wait in the Alerts tab, and by default banners stay quiet during calls, Focus and full screen.

It also handles music controls, a slim volume and brightness pop-up, and AirPods battery.

Notchy is free and open source (GPL-3.0). It needs macOS 14 or later and works best on a MacBook with a notch.

Code and download: {REPO}

This is v1.0.0 and I would like your feedback. If you try it, tell me what breaks and what the notch should do next.

#macOS #OpenSource #DevTools"""

LINKEDIN_INSTALL = f"""Here is how to set up Notchy in about 90 seconds.

1. Download Notchy.zip from the v1.0.0 release on GitHub.
2. Unzip it and drag Notchy into Applications.
3. Open it. macOS will say it cannot verify Notchy, because the app is not notarized. Go to System Settings > Privacy & Security and click Open Anyway. You only do this once.
4. The welcome window has three steps: hover the notch, allow only the permissions you want, and pick your tabs.
5. Notchy hooks into your AI coding agent for you. It adds its entries to the agent's settings file and backs up your old file first. You can turn this off in Settings > General.
6. Start at login is on by default. You can change it in Settings > General.

Right-click the notch any time to open Settings.

{REPO}

#macOS #OpenSource"""

IG_LAUNCH = f"""My MacBook notch was doing nothing, so I gave it a job.

Notchy is a free, open-source Mac app. Approvals from your AI coding agent, meeting reminders with a Join button, and Teams and Outlook alerts show up right at the notch. Music controls, a slim volume pop-up and AirPods battery are in there too.

Free on GitHub: {REPO} (link in bio)
macOS 14 or later · best on MacBooks with a notch
Built by Ujjwal Kumar

#Notchy #macOS #MacBook #MacBookPro #MacApps #MacSetup #AI #DeveloperTools #Productivity #OpenSource #IndieDev #BuildInPublic #SwiftUI"""

IG_INSTALL = f"""Setting up Notchy takes about 90 seconds.

Download Notchy.zip from GitHub and drag it into Applications. The first time you open it, macOS asks you to confirm in System Settings > Privacy & Security > Open Anyway, because the app is not notarized. Then follow the three-step welcome.

{REPO} (link in bio)
Save this for when you install it.

#Notchy #macOS #MacBook #MacApps #AI #OpenSource #DeveloperTools #Productivity #MacTips #IndieDev"""

ALT = [
    ("thumbnail-linkedin-1920x1080.png",
     "Dark launch image for Notchy. On the left, large text reads \"Your notch, finally useful.\" with the line "
     "\"AI agent approvals, meeting reminders and Teams & Outlook alerts, right at the notch.\", then \"Built by "
     "Ujjwal Kumar\" and a \"Free & open source\" tag. On the right, the Notchy panel shows a \"Needs approval · Bash\" "
     "card for npm test with Deny and Allow once buttons, and a meeting reminder for \"Design review\" with a Join button."),
    ("cover-instagram-reel-1080x1920.png",
     "Vertical cover for the Notchy launch Reel. The Notchy wordmark sits above the line \"Your notch, finally useful.\" "
     "Below it, the Notchy panel shows a coding agent's approval card with Deny and Allow once, and a \"Design review\" "
     "meeting reminder with a Join button. At the bottom: \"Built by Ujjwal Kumar\", " + REPO + " and \"Free & open source\"."),
    ("cover-instagram-feed-1080x1350.png",
     "Notchy cover. The wordmark and the line \"Your notch, finally useful.\" sit above two real Notchy screens: a "
     "coding agent's approval card with Deny and Allow once, and a meeting reminder with a Join button. Below them: "
     "\"Built by Ujjwal Kumar\", " + REPO + " and \"Free & open source\"."),
]

CHECKLIST = [
    "Make the GitHub repo Ujjwalkumar-pm/Notchy public. Remove your name from build notes and design docs first if you still want that.",
    "Bump the app version to 1.0.0, build Notchy.zip, and publish the GitHub Release v1.0.0 with Notchy.zip attached (the install video shows exactly this).",
    "Open " + REPO + " in a private window. Check the link works, the release downloads, and the README install steps match the video.",
    "Do one test install on a clean user account: download the zip in Safari, open it, and confirm Open Anyway appears in Privacy & Security.",
    "Instagram: add the GitHub link to your bio (both captions say \"link in bio\"), or remove those words. Add your Instagram handle to the captions if you want one.",
    "Instagram: upload cover-instagram-reel-1080x1920.png as the Reel cover and check the grid crop. Use cover-instagram-feed-1080x1350.png for a feed post.",
    "LinkedIn: upload thumbnail-linkedin-1920x1080.png as the video thumbnail. Paste the alt text from section 5 where the app allows it.",
    "Read each post once more on your phone before posting.",
]


def heading(doc, text, level=1):
    h = doc.add_heading(text, level=level)
    for r in h.runs:
        r.font.color.rgb = RGBColor(0x1F, 0x3A, 0x6E)


def note(doc, text):
    p = doc.add_paragraph()
    r = p.add_run(text)
    r.italic = True
    r.font.size = Pt(9.5)
    r.font.color.rgb = RGBColor(0x55, 0x5F, 0x6D)


def post(doc, text):
    """One paragraph per block; single newlines inside a block become line breaks (paste-ready)."""
    for block in text.split("\n\n"):
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(8)
        lines = block.split("\n")
        for i, line in enumerate(lines):
            run = p.add_run(line)
            if i < len(lines) - 1:
                run.add_break(WD_BREAK.LINE)


def words(text):
    return len([w for w in text.split() if not w.startswith("#")])


def main():
    doc = Document()
    st = doc.styles["Normal"]
    st.font.name = "Calibri"
    st.font.size = Pt(11)

    doc.add_heading("Notchy launch - post copy", 0)
    note(doc, "Videos, thumbnail and covers are in the same folder (Desktop/Notchy-Launch-Kit). "
              "Copy each post from the first line to the hashtags.")

    heading(doc, "1. LinkedIn - launch post (with Notchy-Launch-16x9.mp4)")
    note(doc, f"{words(LINKEDIN_LAUNCH)} words without hashtags · 3 hashtags · thumbnail: thumbnail-linkedin-1920x1080.png")
    post(doc, LINKEDIN_LAUNCH)

    heading(doc, "2. LinkedIn - install video post (with Notchy-Install-16x9.mp4)")
    note(doc, f"{words(LINKEDIN_INSTALL)} words without hashtags · post a day or two after the launch post, or as its first comment")
    post(doc, LINKEDIN_INSTALL)

    heading(doc, "3. Instagram - launch Reel caption (Notchy-Launch-9x16.mp4)")
    note(doc, "13 hashtags · cover: cover-instagram-reel-1080x1920.png")
    post(doc, IG_LAUNCH)

    heading(doc, "4. Instagram - install Reel caption (Notchy-Install-9x16.mp4)")
    note(doc, "10 hashtags")
    post(doc, IG_INSTALL)

    heading(doc, "5. Alt text for the covers")
    for name, alt in ALT:
        p = doc.add_paragraph()
        p.add_run(name).bold = True
        doc.add_paragraph(alt)

    heading(doc, "6. Before you post")
    for item in CHECKLIST:
        doc.add_paragraph(item, style="List Bullet")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc.save(OUT)
    print(f"wrote {OUT} (LinkedIn launch post: {words(LINKEDIN_LAUNCH)} words)")


if __name__ == "__main__":
    main()
