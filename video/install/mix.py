"""Build the install-video audio stems: VO placed per beat + music bed ducked under the voice.

    video/.venv/bin/python video/install/mix.py 16x9|9x16 OUT_DIR
writes OUT_DIR/vo-<aspect>.wav and OUT_DIR/premix-<aspect>.wav (48 kHz stereo float).
Both cuts share one 87.0 s timeline. Helpers (decode, LUFS, duck envelope) come from video/launch/mix.py.
"""
import json, os, sys
import numpy as np, soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "video/launch"))
from mix import load48, lufs, ramp_env, SR, DUCK_DB, MUSIC_REL_DB  # noqa: E402

VO_DIR = os.path.join(ROOT, "video/audio/vo-install")
MUSIC = os.path.join(ROOT, "video/audio/music-install.wav")
DUR = 87.0
# beat -> start (s); must match the caption timing in video/install/build.py
PLACE = [("I0", 0.3), ("I1", 4.85), ("I2", 11.25), ("I3", 17.75), ("I4", 31.75), ("I5", 46.25),
         ("I6", 52.25), ("I7", 62.75), ("I8", 72.75), ("I9", 81.3)]


def main(aspect, out):
    os.makedirs(out, exist_ok=True)
    timing = json.load(open(os.path.join(VO_DIR, "timing.json")))
    n = int(DUR * SR)
    vo = np.zeros((n, 2), dtype=np.float32)
    spans = []
    for beat, at in PLACE:
        a = load48(os.path.join(VO_DIR, f"{beat}.wav"))
        i = int(at * SR)
        vo[i:i + len(a)] += a[: n - i]
        spans += [(at + s["start"], at + s["end"]) for s in timing[beat]["sentences"]]
    spans.sort()
    merged = [list(spans[0])]
    for a, b in spans[1:]:
        if a - merged[-1][1] < 0.8:
            merged[-1][1] = b
        else:
            merged.append([a, b])
    # the bed is 32 bars = exactly 87.0 s (resolve from 76.12 s, Cmaj7 on the last bar); gentle tail fade
    mus = load48(MUSIC)[:n].copy()
    t = np.arange(n) / SR
    mus *= (np.clip((DUR - t) / 1.6, 0, 1) ** 1.5)[:, None]
    gain_db = (lufs(vo) + MUSIC_REL_DB) - lufs(mus)
    mus *= 10 ** (gain_db / 20)
    mus *= ramp_env(n, merged, DUCK_DB)[:, None]
    sf.write(os.path.join(out, f"vo-{aspect}.wav"), vo, SR, subtype="FLOAT")
    sf.write(os.path.join(out, f"premix-{aspect}.wav"), vo + mus, SR, subtype="FLOAT")
    print(f"{aspect}: music gain {gain_db:+.1f} dB, duck {DUCK_DB} dB over {len(merged)} voice spans")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
