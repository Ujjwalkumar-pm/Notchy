#!/usr/bin/env python3
"""Original music beds for the Notchy launch/install videos.
Pure numpy synthesis (no samples, loops or soundfonts). Run:
  video/.venv/bin/python video/audio/make-music.py
Outputs music-launch.wav (75 s) and music-install.wav (92 s): 48 kHz stereo 24-bit.
"""
import os, re, subprocess, numpy as np, soundfile as sf

SR = 48000
HERE = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(7)

def mid(n): return 440.0 * 2 ** ((n - 69) / 12)

def fft_filter(x, curve):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * curve(f), len(x))

class Mix:
    def __init__(self, n):
        self.n = n
        self.bus = {k: np.zeros((2, n)) for k in ("pad", "pluck", "bass", "drum")}
    def add(self, bus, start, sig, pan=0.0):
        i = int(start * SR)
        if i >= self.n: return
        sig = sig[: self.n - i]
        l = np.sqrt(0.5 * (1 - pan)); r = np.sqrt(0.5 * (1 + pan))
        self.bus[bus][0, i:i + len(sig)] += sig * l
        self.bus[bus][1, i:i + len(sig)] += sig * r

def pad_note(f, dur, rel=1.0, det=0.0):
    n = int((dur + rel) * SR); t = np.arange(n) / SR
    s = np.zeros(n)
    for k in range(1, 7):                       # softened saw, harmonics capped (~<2 kHz)
        s += np.sin(2 * np.pi * f * (1 + det) * k * t + k) / k ** 1.6
    env = np.minimum(1, t / 0.9) * np.where(t < dur, 1, np.exp(-(t - dur) * 4.0 / rel))
    return s * env

def pluck(f, dur=0.9):
    n = int(dur * SR); t = np.arange(n) / SR
    s = sum(np.sin(2 * np.pi * f * k * t) * np.exp(-t * (5 + 7 * k)) / k ** 1.3 for k in range(1, 6))
    return s * np.minimum(1, t / 0.003)

def bass_note(f, dur):
    n = int((dur + 0.15) * SR); t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * 2 * f * t)
    env = np.minimum(1, t / 0.02) * np.where(t < dur, 1, np.exp(-(t - dur) * 30))
    return s * env

def kick():
    t = np.arange(int(0.45 * SR)) / SR
    ph = 2 * np.pi * (45 * t + (95 / 28) * (1 - np.exp(-28 * t)))
    return np.sin(ph) * np.exp(-t * 9) * np.minimum(1, t / 0.002)

def hat(open_=False):
    t = np.arange(int((0.18 if open_ else 0.06) * SR)) / SR
    nz = rng.standard_normal(len(t)); nz = np.diff(nz, prepend=0); nz = np.diff(nz, prepend=0)
    return nz * np.exp(-t * (18 if open_ else 70)) * 0.35

def snap():
    t = np.arange(int(0.22 * SR)) / SR
    nz = fft_filter(rng.standard_normal(len(t)), lambda f: 1 / (1 + (f / 1400) ** 4) * (f > 150))
    return (nz * np.exp(-t * 22) * 2.5 + np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30))

def reverb(x, sec=2.6, wet=1.0):
    n = int(sec * SR); t = np.arange(n) / SR
    out = np.zeros_like(x)
    for c in range(2):
        ir = rng.standard_normal(n) * np.exp(-t * 2.4)
        ir = fft_filter(ir, lambda f: 1 / (1 + (f / 3500) ** 2) * (f > 120))
        ir[: int(0.02 * SR)] *= np.linspace(0, 1, int(0.02 * SR))
        L = len(x[c]) + n
        out[c] = np.fft.irfft(np.fft.rfft(x[c], L) * np.fft.rfft(ir, L), L)[: len(x[c])] * 0.06
    return out * wet

def pingpong(x, beat, taps=4, fb=0.45):
    out = x.copy(); d = int(beat * 0.75 * SR)
    for k in range(1, taps + 1):
        g = fb ** k; sh = d * k
        c = k % 2
        out[c, sh:] += x[1 - c, :-sh] * g if sh < x.shape[1] else 0
    return out

# ---- chord data (A minor / C major family) ----
# (bass midi, pad voicing, arp tones low->high)
CH = {
 "Am": (45, [57, 60, 64], [69, 72, 76, 81]),
 "F":  (41, [53, 57, 60], [65, 69, 72, 77]),
 "C":  (48, [52, 55, 60], [67, 72, 76, 79]),
 "G":  (43, [50, 55, 59], [67, 71, 74, 79]),
 "Cmaj7": (48, [52, 59, 60], [67, 71, 76, 79]),
}
ARP8 = [0, 1, 2, 3, 2, 1, 2, 1]
ARP16 = [0, 1, 2, 3, 2, 3, 2, 1, 0, 1, 2, 3, 3, 2, 1, 2]

def render(total, bpm_bar, bars, plan, name, bpm_label):
    bar = bpm_bar; beat = bar / 4
    n = int(total * SR); m = Mix(n)
    for b in range(bars):
        t0 = b * bar
        ch, lay = plan(b)
        bass, padv, arp = CH[ch]
        # pad
        if lay.get("pad", 1):
            ext = lay.get("padext", 0)
            for j, nt in enumerate(padv):
                for d, pan in ((-0.0025, -0.45), (0.0025, 0.45)):
                    m.add("pad", t0, pad_note(mid(nt + (12 if lay.get("padhi") else 0)), bar + ext, 1.6, d) * 0.11, pan)
            if lay.get("padhi"):
                for nt in padv:
                    m.add("pad", t0, pad_note(mid(nt), bar, 1.6, 0) * 0.05, 0)
        # bass
        if lay.get("bass"):
            pat = [(0, 1.5), (2, 1.0), (3.5, 0.5)] if lay["bass"] == 2 else [(0, 3.7)]
            for pos, ln in pat:
                m.add("bass", t0 + pos * beat, bass_note(mid(bass), ln * beat * 0.9) * 0.55, 0)
        # arp
        a = lay.get("arp")
        if a:
            if a == "8":
                steps, pat, g = 8, ARP8, 0.20
            elif a == "16":
                steps, pat, g = 16, ARP16, 0.17
            elif a == "4":
                steps, pat, g = 4, [0, 2, 3, 2], 0.22
            elif a == "2":
                steps, pat, g = 2, [0, 3], 0.22
            for s in range(steps):
                v = g * (1.0 if s % 2 == 0 else 0.72) * lay.get("arpvol", 1)
                nt = arp[pat[s % len(pat)]] + lay.get("arpoct", 0)
                m.add("pluck", t0 + s * bar / steps, pluck(mid(nt)) * v, pan=((s % 4) - 1.5) * 0.28)
        # drums
        kp = lay.get("kick")
        if kp:
            pos = {"1": [0, 2], "4": [0, 1, 2, 3], "d": [0], "d2": [0, 2.5]}[kp]
            for p in pos:
                m.add("drum", t0 + p * beat, kick() * lay.get("kickvol", 0.75), 0)
        if lay.get("snap"):
            for p in (1, 3): m.add("drum", t0 + p * beat, snap() * 0.14, 0.05)
        h = lay.get("hat")
        if h:
            for s in range(8 if h == 8 else 16):
                step = bar / (8 if h == 8 else 16)
                if h == 8 and s % 2 == 0: continue        # off-beat 8ths
                v = (0.5 if (h == 16 and s % 2 == 0) else 1.0) * lay.get("hatvol", 0.5)
                m.add("drum", t0 + s * step, hat(h == 8 and s == 7) * v, pan=0.25 if s % 4 < 2 else -0.25)
    pad = m.bus["pad"]; pl = m.bus["pluck"]
    wet = reverb(pad + pl)
    echo = pingpong(pl, beat) - pl
    mix = pad * 1.0 + pl * 1.0 + echo * 0.7 + wet * 1.4 + m.bus["bass"] + m.bus["drum"]
    # sidechain-style gentle duck of pad/bass is skipped; keep groove simple.
    # keep 1-4 kHz light so the voiceover sits on top (-5 dB smooth bell, 1-4 kHz)
    def eq(f):
        f = np.maximum(f, 1)
        bell = np.exp(-0.5 * (np.log2(f / 2000) / 0.9) ** 2)
        return 10 ** (-5.0 * bell / 20) * (f > 28)
    mix = np.stack([fft_filter(mix[c], eq) for c in range(2)])
    # fades: 30 ms in, smooth cosine tail out over the last `tail` seconds
    return mix

def finish(mix, total, tail_start, path, label):
    n = mix.shape[1]
    t = np.arange(n) / SR
    fin = np.minimum(1, t / 0.03)
    fo = np.where(t < tail_start, 1.0, 0.5 * (1 + np.cos(np.pi * np.clip((t - tail_start) / (total - tail_start), 0, 1))))
    mix = mix * fin * fo
    mix[:, -int(0.05 * SR):] *= np.linspace(1, 0, int(0.05 * SR))
    tmp = path + ".tmp.wav"
    gain = 0.3
    for _ in range(4):
        out = np.tanh(mix * gain * 1.0 / 0.9) * 0.9 if False else mix * gain
        sf.write(tmp, out.T, SR, subtype="PCM_24")
        r = subprocess.run(["ffmpeg", "-nostats", "-i", tmp, "-af", "ebur128=peak=true", "-f", "null", "-"],
                           capture_output=True, text=True).stderr
        I = float(re.findall(r"I:\s+(-?[\d.]+) LUFS", r)[-1])
        gain *= 10 ** ((-20.0 - I) / 20)
    out = mix * gain
    pk = np.abs(out).max()
    if pk > 10 ** (-3.5 / 20):                     # soft-limit if peaks exceed ~-3.5 dBFS
        ceil = 10 ** (-3.5 / 20)
        out = np.tanh(out / ceil) * ceil
    sf.write(path, out.T, SR, subtype="PCM_24")
    os.remove(tmp)
    print(label, "gain", round(gain, 3), "peak dBFS", round(20 * np.log10(np.abs(out).max()), 2))

# ---------------- LAUNCH: 102.857 BPM, 30 bars = 70 s, tail to 75 s ----------------
def launch_plan(b):
    prog = ["Am", "F", "C", "G"]
    ch = prog[b % 4]
    if b < 4:   lay = {"pad": 1, "arp": "8" if b >= 2 else None, "arpvol": 0.6}
    elif b < 12: lay = {"kick": "1", "hat": 8, "hatvol": 0.35, "bass": 1, "arp": "8", "arpvol": 0.85}
    elif b < 24: lay = {"kick": "4", "kickvol": 0.7, "snap": 1, "hat": 8, "hatvol": 0.5, "bass": 2, "arp": "8"}
    elif b < 27: lay = {"kick": "4", "kickvol": 0.8, "snap": 1, "hat": 16, "hatvol": 0.5, "bass": 2, "arp": "16", "padhi": 1, "arpvol": 1.0}
    else:
        ch = ["F", "G", "C"][b - 27]
        lay = {"kick": "d", "kickvol": 0.6, "arp": "4" if b < 29 else "2", "arpvol": 0.9, "bass": 1 if b < 29 else 0}
        if b == 29: lay["kick"] = None; lay["padext"] = 5.0
        if b == 29: lay["bass"] = 1
    if b == 29: ch = "Cmaj7"
    return ch, lay

# ---------------- INSTALL: 88.28 BPM, 32 bars = 87 s, tail to 92 s ----------------
def install_plan(b):
    prog = ["C", "G", "Am", "F"]
    ch = prog[b % 4]
    if b < 4:    lay = {"pad": 1}
    elif b < 8:  lay = {"arp": "4", "arpvol": 0.7}
    elif b < 28: lay = {"kick": "1", "kickvol": 0.55, "hat": 8, "hatvol": 0.25, "bass": 1, "arp": "8", "arpvol": 0.55}
    else:        lay = {"arp": "4", "arpvol": 0.6, "bass": 1}
    if b == 31: ch = "Cmaj7"; lay = {"arp": "2", "arpvol": 0.6, "padext": 5.0, "bass": 1}
    return ch, lay

if __name__ == "__main__":
    jobs = [("launch", 75.0, 70.0 / 30, 30, launch_plan, 70.0, "music-launch.wav"),
            ("install", 92.0, 87.0 / 32, 32, install_plan, 87.0, "music-install.wav")]
    for name, total, bar, bars, plan, tail, fn in jobs:
        print(name, "bar", round(bar, 4), "s, BPM", round(240 / bar, 3))
        mix = render(total, bar, bars, plan, name, 240 / bar)
        finish(mix, total, tail, os.path.join(HERE, fn), name)
