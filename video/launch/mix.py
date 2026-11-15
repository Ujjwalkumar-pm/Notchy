"""Build the launch-video audio stems: VO placed per beat + music bed ducked under the voice.

    video/.venv/bin/python video/launch/mix.py 16x9|9x16 OUT_DIR
writes OUT_DIR/vo-<aspect>.wav (voice only) and OUT_DIR/premix-<aspect>.wav (voice + ducked music),
48 kHz stereo float. Loudness normalisation and the limiter run afterwards in mix.sh (ffmpeg).
"""
import json, os, re, subprocess, sys, tempfile
import numpy as np, soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
VO_DIR = os.path.join(ROOT, "video/audio/vo-launch")
MUSIC = os.path.join(ROOT, "video/audio/music-launch.wav")
SR = 48000
DUCK_DB = -10.0          # music under voice
MUSIC_REL_DB = -3.0      # un-ducked music vs voice loudness (so ducked music sits ~13 dB under the voice)

PLACE = {
    "16x9": [("L0", 0.05), ("L1", 3.25), ("L2", 5.9), ("L3", 18.9), ("L4", 27.5), ("L5", 37.3),
             ("L6", 43.6), ("L7", 48.8), ("L8", 55.3), ("L9", 62.5)],
    "9x16": [("L0", 0.05), ("L1", 3.25), ("L2", 5.9), ("L3", 18.9), ("L4", 27.5), ("L5", 37.3),
             ("L8v", 48.1), ("L9", 51.9)],
}
DUR = {"16x9": 70.0, "9x16": 58.6}


def load48(path):
    """Decode any audio file to 48 kHz stereo float via ffmpeg (swr, long filter)."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-af", "aresample=48000:filter_size=64:phase_shift=12",
                          "-ac", "2", "-f", "f32le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype="<f4").reshape(-1, 2).copy()


def lufs(x):
    with tempfile.TemporaryDirectory() as d:
        tmp = os.path.join(d, "lufs.wav")
        sf.write(tmp, x, SR, subtype="FLOAT")
        err = subprocess.run(["ffmpeg", "-nostats", "-i", tmp, "-af", "ebur128", "-f", "null", "-"],
                             capture_output=True, text=True).stderr
    return float(re.findall(r"I:\s+(-?[\d.]+) LUFS", err)[-1])


def ramp_env(n, spans, depth_db, attack=0.18, release=0.45):
    """Gain envelope: 1.0 outside spans, depth inside, with cosine ramps."""
    g_db = np.zeros(n)
    t = np.arange(n) / SR
    for a, b in spans:
        a0, b1 = a - attack, b + release
        m = (t >= a0) & (t <= b1)
        tt = t[m]
        x = np.ones_like(tt)
        up = tt < a
        x[up] = 0.5 - 0.5 * np.cos(np.pi * (tt[up] - a0) / attack)
        dn = tt > b
        x[dn] = 0.5 + 0.5 * np.cos(np.pi * (tt[dn] - b) / release)
        g_db[m] = np.minimum(g_db[m], depth_db * x)
    return 10 ** (g_db / 20)


def main(aspect, out):
    os.makedirs(out, exist_ok=True)
    timing = json.load(open(os.path.join(VO_DIR, "timing.json")))
    n = int(DUR[aspect] * SR)
    vo = np.zeros((n, 2), dtype=np.float32)
    spans = []
    for beat, at in PLACE[aspect]:
        a = load48(os.path.join(VO_DIR, f"{beat}.wav"))
        i = int(at * SR)
        vo[i:i + len(a)] += a[: n - i]
        for s in timing[beat]["sentences"]:
            spans.append((at + s["start"], at + s["end"]))
    # merge spans closer than 0.8 s so the bed doesn't pump between sentences
    spans.sort()
    merged = [list(spans[0])]
    for a, b in spans[1:]:
        if a - merged[-1][1] < 0.8:
            merged[-1][1] = b
        else:
            merged.append([a, b])

    m = load48(MUSIC)
    if aspect == "16x9":
        mus = m[:n].copy()
        fade_a, fade_b = 68.6, 70.0
    else:
        # 9:16: play bars 1-22 (0-51.33 s), then splice to the resolve section (bar 28, 63.0 s) on the
        # bar line so the end card gets the closing chords; the final downbeat lands at 58.33 s.
        cut, jump, xf = 22 * 7 / 3, 63.0, int(0.25 * SR)
        a = m[: int(cut * SR) + xf].copy()
        b = m[int(jump * SR) - 0: int(jump * SR) + (n - int(cut * SR))].copy()
        w = np.linspace(0, 1, xf)[:, None]
        mus = np.zeros((n, 2), dtype=np.float32)
        ic = int(cut * SR)
        mus[:ic] = a[:ic]
        mus[ic:ic + xf] = a[ic:ic + xf] * np.cos(w * np.pi / 2) + b[:xf] * np.sin(w * np.pi / 2)
        mus[ic + xf:] = b[xf: xf + n - ic - xf]
        fade_a, fade_b = 57.5, 58.6
    t = np.arange(n) / SR
    fade = np.clip((fade_b - t) / (fade_b - fade_a), 0, 1) ** 1.5
    mus *= fade[:, None]

    gain_db = (lufs(vo) + MUSIC_REL_DB) - lufs(mus)
    mus *= 10 ** (gain_db / 20)
    mus *= ramp_env(n, merged, DUCK_DB)[:, None]
    sf.write(os.path.join(out, f"vo-{aspect}.wav"), vo, SR, subtype="FLOAT")
    sf.write(os.path.join(out, f"premix-{aspect}.wav"), vo + mus, SR, subtype="FLOAT")
    print(f"{aspect}: music gain {gain_db:+.1f} dB, duck {DUCK_DB} dB over {len(merged)} voice spans")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
