"""Render the launch-video voiceover (Kokoro af_heart, speed 1.0), one sentence at a time,
joined per beat with 0.35 s pauses. Output: video/audio/vo-launch/L<n>.wav (24 kHz mono).
Usage: video/.venv/bin/python video/launch/vo.py   (models in ~/.cache/hyperframes/tts, see video/README.md)
TTS respellings are voice-only; captions keep the real spelling ("Oojwal" -> Ujjwal)."""
import os, sys, json, numpy as np, soundfile as sf
from kokoro_onnx import Kokoro

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "video/audio/vo-launch")
PAUSE = 0.35
BEATS = {
    "L0": ["That notch on your Mac?", "It's been doing nothing."],
    "L1": ["Until now.", "Meet Notchy."],
    "L2": ["Your AI coding agent needs permission while you're in another app?",
           "The request slides right out of the notch.",
           "Rest your pointer on it, tap Allow once, and keep going.",
           "And when a long task finishes, Notchy lets you know."],
    "L3": ["Running late again?", "A minute before your call, a reminder pops out with a Join button.",
           "And the Calendar tab counts down to the next one."],
    "L4": ["Teams and Outlook won't stop pinging?", "Your messages and unread counts wait in the Alerts tab.",
           "And banners stay quiet during calls, Focus, and full screen."],
    "L5": ["Your music lives up here too.", "Artwork, controls, drag to seek, shuffle, and where the sound goes."],
    "L6": ["Volume and brightness get a slim little pop-up.", "No more big gray box."],
    "L7": ["Your AirPods battery.", "Your charger.", "A USB drive you can eject right from the notch."],
    "L8": ["And it's yours to shape.",
           "Reorder and swipe tabs, go Black or Glass, and pick where it opens and how it moves."],
    "L8v": ["Make it yours.", "Tabs, themes, animations."],
    "L9": ["It's free and open source.", "Built by Oojwal Kumar.", "Grab it on GitHub."],
}

def models():
    C = os.path.expanduser("~/.cache/hyperframes/tts")
    for m, v in ((f"{C}/models/kokoro-v1.0.onnx", f"{C}/voices/voices-v1.0.bin"),
                 ("/tmp/kmodels/kokoro-v1.0.onnx", "/tmp/kmodels/voices-v1.0.bin")):  # /tmp = legacy fallback
        if os.path.exists(m) and os.path.exists(v):
            return m, v
    sys.exit("kokoro model files not found")

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
