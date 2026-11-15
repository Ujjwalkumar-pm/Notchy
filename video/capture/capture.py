#!/usr/bin/env python3
"""Records the Notchy launch-video footage from the capture build (demo data only).

    scripts/capture-build.sh                 # builds /tmp/NotchyCapture.app (-D NOTCHY_CAPTURE)
    python3 video/capture/capture.py [shot ...]

For each shot: launches the capture build with --capture-shot, which drives the real UI through
scripted demo states and records Notchy's own windows at 30 fps (raw window PNGs + timings);
then compose.swift resamples to 30 fps and composites them over a generated wallpaper with a
drawn menu bar and camera notch at 2x. Glass stills are real screen grabs of the panel over the
same backdrop (shown by the capture build in a window of its own; checked for foreign windows).

Output: video/footage/<shot>/frame-%05d.png + still.png (git-ignored),
        video/footage/<shot>/contact-sheet.png and video/footage/manifest.json (committed).

Safety: no synthetic input; the capture build has its own bundle id and defaults domain, never
listens on the hook port, never touches ~/.claude, Now Playing, calendars or TCC. Shots that
bring a Notchy window to the front wait until the Mac has been idle for 5 s.
"""
import json
import math
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
APP = "/tmp/NotchyCapture.app"
BUNDLE = "in.ujjwalkumar.notchy.capture"
WORK = "/tmp/notchy-capture-work"
BIN = os.path.join(WORK, "compose")
FOOT = os.path.join(ROOT, "video", "footage")

# name: (preset, beats, kind) — kind "motion" (frames + still) or "grab" (glass still only)
SHOTS = {
    "closed-notch": ("notch", ["L0", "I0", "L9"], "motion"),
    "hover-open-music": ("notch", ["L1"], "motion"),
    "music-playing-loop": ("notch", ["L1", "L9", "I9"], "motion"),
    "approval-dwell-allow": ("notch", ["L2"], "motion"),
    "approval-card-still": ("notch", ["L2"], "motion"),
    "banner-claude-finished": ("notch", ["L2"], "motion"),
    "claude-sessions": ("notch", ["L2"], "motion"),
    "banner-meeting": ("notch", ["L3"], "motion"),
    "calendar-hero": ("notch", ["L3"], "motion"),
    "banner-teams": ("notch", ["L4"], "motion"),
    "banner-outlook": ("notch", ["L4"], "motion"),
    "alerts-scroll": ("notch", ["L4"], "motion"),
    "alerts-focus-moon": ("notch", ["L4"], "motion"),
    "music-seek-shuffle": ("notch", ["L5"], "motion"),
    "volume-popup": ("notch", ["L6"], "motion"),
    "brightness-popup": ("notch", ["L6"], "motion"),
    "banner-airpods": ("notch", ["L7"], "motion"),
    "banner-charger": ("notch", ["L7"], "motion"),
    "banner-drive-eject": ("notch", ["L7"], "motion"),
    "swipe-tabs": ("notch", ["L8"], "motion"),
    "black-music-still": ("notch", ["L8"], "motion"),
    "glass-music": ("notch", ["L8"], "grab"),
    "glass-alerts": ("notch", ["L8"], "grab"),
    "glass-calendar": ("notch", ["L8"], "grab"),
    "context-menu": ("notch", ["I7", "I8"], "motion"),
    "settings-general": ("desk", ["I6", "I8"], "motion"),
    "settings-notch": ("desk", ["L8", "I7"], "motion"),
    "settings-tabs": ("desk", ["L8", "I7"], "motion"),
    "settings-alerts": ("desk", ["I7"], "motion"),
    "settings-calendar": ("desk", ["I7"], "motion"),
    "settings-appearance": ("desk", ["L8", "I7"], "motion"),
    "settings-about": ("desk", ["I7"], "motion"),
    "settings-sidebar-pan": ("desk", ["I7"], "motion"),
    "settings-theme-glass": ("desk", ["L8"], "motion"),
    "settings-open-from": ("desk", ["L8"], "motion"),
    "settings-turnoff-sheet": ("desk", ["I8"], "motion"),
    "welcome-1-hover": ("desk", ["I4"], "motion"),
    "welcome-2-permissions": ("desk", ["I4"], "motion"),
    "welcome-3-tabs": ("desk", ["I5"], "motion"),
    "welcome-steps": ("desk", ["I4", "I5"], "motion"),
}
# Where the still comes from (fraction of the shot) when the last frame isn't the moment.
STILL_AT = {"context-menu": 0.5, "banner-claude-finished": 0.5, "banner-meeting": 0.5, "banner-teams": 0.5,
            "banner-outlook": 0.5, "banner-airpods": 0.5, "banner-charger": 0.5, "banner-drive-eject": 0.25,
            "volume-popup": 0.35, "brightness-popup": 0.35, "settings-turnoff-sheet": 0.5,
            "approval-dwell-allow": 0.44, "welcome-3-tabs": 0.5}
# Shots that activate the capture app (Settings, welcome, the menu) or need a screen grab.
NEEDS_IDLE = {n for n, (p, _, k) in SHOTS.items() if p == "desk" or k == "grab" or n == "context-menu"}


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)


def hid_idle():
    out = subprocess.run(["ioreg", "-c", "IOHIDSystem"], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if "HIDIdleTime" in line:
            return int(line.split()[-1]) / 1e9
    return 0


def wait_idle(seconds=5, limit=600):
    t0 = time.time()
    while hid_idle() < seconds:
        if time.time() - t0 > limit:
            raise SystemExit("Mac not idle; stopping")
        time.sleep(1)


def handle_grabs(shot_dir):
    for f in os.listdir(shot_dir):
        if not (f.startswith("grab-") and f.endswith(".json")):
            continue
        name = f[5:-5]
        done = os.path.join(shot_dir, f"grab-{name}.done")
        if os.path.exists(done):
            continue
        req = json.load(open(os.path.join(shot_dir, f)))
        if req["foreign"]:
            print(f"  grab {name} SKIPPED: foreign windows over the region: {req['foreign']}")
        elif hid_idle() < 2:
            print(f"  grab {name} SKIPPED: Mac in use")
        else:
            x, y, w, h = [int(v) for v in req["rect"]]
            run(["screencapture", "-x", "-R", f"{x},{y},{w},{h}", os.path.join(shot_dir, f"grab-{name}.png")])
            print(f"  grab {name}: {w}x{h} pt")
        open(done, "w").write("ok")


def capture(name):
    preset, _, kind = SHOTS[name]
    shot_dir = os.path.join(WORK, "shots", name)
    shutil.rmtree(shot_dir, ignore_errors=True)
    os.makedirs(shot_dir)
    if name in NEEDS_IDLE:
        wait_idle(10)
    subprocess.run(["defaults", "delete", BUNDLE], capture_output=True)
    args = ["open", "-n", "-W", APP, "--args", "--capture-shot", name, "--capture-out", shot_dir]
    if kind == "grab":
        args += ["--capture-backdrop", os.path.join(WORK, "canvas-notch.png")]
    p = subprocess.Popen(args)
    t0 = time.time()
    while p.poll() is None:
        handle_grabs(shot_dir)
        if time.time() - t0 > 60:
            p.kill()
            raise SystemExit(f"{name}: timed out")
        time.sleep(0.05)
    if not os.path.exists(os.path.join(shot_dir, "DONE")):
        raise SystemExit(f"{name}: capture build did not finish")
    return shot_dir


def contact_sheet(out_dir, frames):
    sheet = os.path.join(out_dir, "contact-sheet.png")
    if frames <= 1:
        run(["ffmpeg", "-loglevel", "error", "-y", "-i", os.path.join(out_dir, "still.png"),
             "-vf", "scale=960:-1", sheet])
        return
    step = max(1, math.ceil(frames / 12))
    run(["ffmpeg", "-loglevel", "error", "-y", "-start_number", "1", "-i", os.path.join(out_dir, "frame-%05d.png"),
         "-vf", f"select='not(mod(n\\,{step}))',scale=400:-1,tile=4x3:padding=4:color=white",
         "-frames:v", "1", sheet])


def compose(name, shot_dir):
    preset, beats, kind = SHOTS[name]
    out_dir = os.path.join(FOOT, name)
    shutil.rmtree(out_dir, ignore_errors=True)
    os.makedirs(out_dir)
    entry = {"name": name, "preset": preset, "beats": beats, "fps": 30}
    w, h = (1920, 1080) if preset == "notch" else (2560, 1440)
    entry["width"], entry["height"] = w, h
    if kind == "grab":
        gname = name
        if not os.path.exists(os.path.join(shot_dir, f"grab-{gname}.png")):
            print(f"  {name}: no grab")
            return None
        run([BIN, "grab", shot_dir, gname, preset, os.path.join(out_dir, "still.png")])
        entry.update(frames=0, duration=0, still="still.png",
                     notes="Real screen grab of the Glass panel over the capture backdrop (Glass only renders on screen).")
    else:
        run([BIN, "shot", shot_dir, preset, out_dir])
        n = len([f for f in os.listdir(out_dir) if f.startswith("frame-")])
        if name in STILL_AT:
            pick = max(1, round(n * STILL_AT[name]))
            shutil.copyfile(os.path.join(out_dir, "frame-%05d.png" % pick), os.path.join(out_dir, "still.png"))
            entry["still_frame"] = pick
        entry.update(frames=n, duration=round(n / 30, 2), still="still.png", pattern="frame-%05d.png")
    contact_sheet(out_dir, entry["frames"])
    return entry


def main():
    os.makedirs(WORK, exist_ok=True)
    run(["swiftc", "-O", "-target", "arm64-apple-macos14", os.path.join(ROOT, "video/capture/compose.swift"), "-o", BIN],
        stderr=subprocess.DEVNULL)
    args = sys.argv[1:]
    # --recompose: rebuild footage from the last recordings in WORK without recording again.
    recompose = "--recompose" in args
    names = [a for a in args if a != "--recompose"] or list(SHOTS)
    # Geometry and the backdrop come from a first, plain run.
    geo_dir = os.path.join(WORK, "shots", "closed-notch") if recompose else capture("closed-notch")
    for preset in ("notch", "desk"):
        run([BIN, "canvas", os.path.join(geo_dir, "geometry.json"), preset, os.path.join(WORK, f"canvas-{preset}.png")])
    manifest_path = os.path.join(FOOT, "manifest.json")
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {"shots": []}
    by_name = {s["name"]: s for s in manifest["shots"]}
    for name in names:
        print(name)
        if name == "closed-notch" or recompose:
            shot_dir = os.path.join(WORK, "shots", name)
        else:
            shot_dir = capture(name)
        entry = compose(name, shot_dir)
        if entry:
            by_name[name] = entry
    manifest = {
        "about": "Notchy launch-video footage: the real app UI (capture build, demo data only) composited "
                 "over a generated wallpaper with a drawn menu bar and camera notch. 2x scale. "
                 "notch preset = 960x540 pt around the notch; desk preset = 1280x720 pt. "
                 "Beats: L = video/script/launch.md, I = video/script/install.md.",
        "shots": [by_name[n] for n in SHOTS if n in by_name],
    }
    json.dump(manifest, open(manifest_path, "w"), indent=2)
    print("manifest:", manifest_path)


if __name__ == "__main__":
    main()
