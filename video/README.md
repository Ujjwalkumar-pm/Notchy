# Launch-video tooling

Everything here rebuilds the Notchy launch + install videos, covers and post-copy docx.
Final outputs go to `~/Desktop/Notchy-Launch-Kit`. Needs: macOS, ffmpeg, node 22+, Google Chrome, `python3.12` (Homebrew).

## One-time setup

```bash
# 1. Python 3.12 venv (git-ignored). The default python3 may be 3.15, which cannot resolve kokoro-onnx.
/opt/homebrew/bin/python3.12 -m venv video/.venv
video/.venv/bin/pip install -r video/requirements.txt

# 2. Kokoro model files (official kokoro-onnx release "model-files-v1.0")
mkdir -p ~/.cache/hyperframes/tts/models ~/.cache/hyperframes/tts/voices
R=https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0
curl -L -o ~/.cache/hyperframes/tts/models/kokoro-v1.0.onnx  $R/kokoro-v1.0.onnx    # 325,532,387 bytes
curl -L -o ~/.cache/hyperframes/tts/voices/voices-v1.0.bin   $R/voices-v1.0.bin     #  28,214,398 bytes

# 3. Verify
shasum -a 256 ~/.cache/hyperframes/tts/models/kokoro-v1.0.onnx ~/.cache/hyperframes/tts/voices/voices-v1.0.bin
#   7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5  kokoro-v1.0.onnx
#   bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d  voices-v1.0.bin
video/.venv/bin/python -c "import kokoro_onnx, soundfile, numpy, docx"
```

Scripts fall back to the old `/tmp/kokoro-venv` and `/tmp/kmodels` only if the paths above are missing.
Override the interpreter for the shell mixers with `PY=/path/to/python`.

## Rebuild order (run from the repo root)

1. **Capture** footage: `scripts/capture-build.sh && python3 video/capture/capture.py` (needs Screen Recording permission; frames are git-ignored).
2. **Music**: `video/.venv/bin/python video/audio/make-music.py` (WAVs are git-ignored; deterministic).
3. **Launch video**: `video/launch/make-media.sh`, then `video/.venv/bin/python video/launch/vo.py`, then `video/launch/mix.sh` (builds comps, renders, mixes, exports MP4s). `SKIP_RENDER=1` re-mixes only.
4. **Install video**: `video/install/make-media.sh`, `video/.venv/bin/python video/install/vo.py`, `video/install/mix.sh`.
5. **Covers** (8 thumbnails, covers and banners + `review/covers-overview.png`): `video/covers/render.sh`. UI cutouts in `video/covers/media/` are committed; rebuild with `/opt/homebrew/bin/python3.12 video/covers/make-media.py` (needs Pillow and the footage stills).
6. **Post copy**: `video/.venv/bin/python video/copy/make-docx.py`.

The voice-selection samples (Kokoro / Tara / Sarvam rounds) are not in the repo; they live in `~/Desktop/Notchy-Launch-Kit/review/voice-samples/`.
