"""Render the install-video voiceover (Kokoro af_heart, speed 1.0), one sentence at a time,
joined per beat with 0.35 s pauses. Output: video/audio/vo-install/I<n>.wav (24 kHz mono) + timing.json.
Usage: video/.venv/bin/python video/install/vo.py [I3 I6 ...]
Same engine and settings as video/launch/vo.py. TTS respellings are voice-only; captions keep the real spelling."""
import os, sys, json, numpy as np, soundfile as sf
from kokoro_onnx import Kokoro

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "video/launch"))
from vo import models  # shared model lookup (video/launch/vo.py)

OUT = os.path.join(ROOT, "video/audio/vo-install")
PAUSE = 0.35
BEATS = {
    "I0": ["Let's get Notchy installed.", "You'll need macOS 14 or later."],
    "I1": ["Head to the Notchy page on GitHub, open Releases, and download the zip file."],
    "I2": ["Double-click the zip to unzip it.", "Then drag Notchy into your Applications folder."],
    "I3": ["The first time you open it, macOS says it can't verify Notchy.", "That's expected.",
           "Go to System Settings, Privacy and Security, and click Open Anyway."],
    "I4": ["Next, a quick welcome.", "Step one: hover the notch to open it.", "Step two: allow only what you use.",
           "Each Allow button opens the right spot in System Settings.", "Skip one, and that feature just stays off."],
    "I5": ["Step three: pick your tabs.", "Want a menu bar icon?", "Switch it on here."],
    "I6": ["Notchy hooks into your AI coding agent for you.", "It backs up your old settings file first.",
           "You can turn it off in Settings, under General."],
    "I7": ["To open Settings, right-click the notch and choose Settings.",
           "You can also use the menu bar icon, or just open Notchy again from Applications."],
    "I8": ["Want to remove it?",
           "Turn off the coding agent integration in Settings, quit from the notch menu, and drag Notchy to the Trash."],
    "I9": ["That's it.", "Enjoy Notchy."],
}


def main():
    os.makedirs(OUT, exist_ok=True)
    k = Kokoro(*models())
    only = set(sys.argv[1:])
    tpath = f"{OUT}/timing.json"
    timing = json.load(open(tpath)) if os.path.exists(tpath) else {}
    for beat, lines in BEATS.items():
        if only and beat not in only:
            continue
        parts, sr, t, sent = [], 24000, 0.0, []
        for i, line in enumerate(lines):
            a, sr = k.create(line, voice="af_heart", speed=1.0, lang="en-us")
            sent.append({"text": line, "start": round(t, 3), "end": round(t + len(a) / sr, 3)})
            t += len(a) / sr + PAUSE
            parts.append(a)
            if i < len(lines) - 1:
                parts.append(np.zeros(int(PAUSE * sr), dtype=a.dtype))
        audio = np.concatenate(parts)
        sf.write(f"{OUT}/{beat}.wav", audio, sr)
        timing[beat] = {"duration": round(len(audio) / sr, 3), "sentences": sent}
        print(f"{beat}\t{len(audio)/sr:.2f}s")
    json.dump(timing, open(tpath, "w"), indent=1)


if __name__ == "__main__":
    main()
