# Notchy launch kit - QA report (16 Nov 2026)

Nothing in the videos, covers or docx was changed. Scan sheets are in /tmp/qa-t7/ (not kept).

| Check | Result | Numbers / notes |
|---|---|---|
| Personal-data scan, 4 videos (1 frame/s, 288 frames) + 3 covers | PASS | 0 hits. Only demo data: Priya S, Rahul M, Ana K, api-server, web-app, The Demo Band, DEMO-USB, Design review, Sprint planning. Neutral gradient wallpaper. Menu-bar clock shows "Mon 16 Nov" (capture date, not personal). |
| Loudness, Launch 16:9 | PASS | -14.0 LUFS, true peak -1.4 dBTP |
| Loudness, Launch 9:16 | PASS | -14.0 LUFS, true peak -1.4 dBTP |
| Loudness, Install 16:9 | PASS | -14.0 LUFS, true peak -1.2 dBTP |
| Loudness, Install 9:16 | PASS | -14.0 LUFS, true peak -1.2 dBTP |
| Specs, Launch 16:9 | PASS | 1920x1080, 30 fps, H.264 + AAC, 70.0 s (limit 75) |
| Specs, Launch 9:16 | PASS | 1080x1920, 30 fps, H.264 + AAC, 58.6 s (limit 60) |
| Specs, Install 16:9 | PASS | 1920x1080, 30 fps, H.264 + AAC, 87.0 s (limit 95) |
| Specs, Install 9:16 | PASS | 1080x1920, 30 fps, H.264 + AAC, 87.0 s (limit 90) |
| Caption vs VO sync, 5+ points per video (whisper small.en) | PASS | Within about 1 s everywhere. Launch: "Meet Notchy" 4-5 s, approvals 10 s, "Long task" 16 s, "Never miss a meeting" 20 s, "Teams & Outlook" 28 s, "Make it yours" 55 s (9:16: 49 s), end card 62-63 s. Install: Download 5 s, Unzip 11 s, First open 17 s, Open Anyway 22 s, Step 1/2/3 at 32/36/46 s, coding agent 52 s, Settings 62 s, uninstall 72 s. 9:16 cuts match 16:9 in Install. |
| 9:16 safe areas | PASS | Captions at about y 1270-1490 (limit 1570). Notch footage starts y 250. End-card text between y 340 and 820 in launch, inside the limits. Only item in the top 250 px is the small grey "Notchy" brand tag at y ~145 (not key text). |
| Post-copy docx opens | PASS | textutil converts it; 6 sections |
| Docx vs videos | PASS | github.com/Ujjwalkumar-pm/Notchy, v1.0.0, Notchy.zip, GPL-3.0 (in launch/install end cards and docx), macOS 14 or later, "Built by Ujjwal Kumar", Open Anyway path, same feature list. |

Whisper hears the VO as "Nochi" and "Ujwal". That is the known small.en limit with the TTS respellings, so it is not scored as a fail. See open item 1.

## Open items for the owner
1. Ear-check the voice-only tracks in review/ for "Notchy" (whisper cannot confirm it). The VO uses the respelling "Oojwal" for Ujjwal; the 16:9 caption still reads "Ujjwal Kumar".
2. Check the real Gatekeeper wording on a clean macOS 15 account with the real release zip. The video shows a redrawn dialog and System Settings > Privacy & Security > Open Anyway.
3. Bump the app version from 0.1.0 to 1.0.0, build Notchy.zip, publish the GitHub Release v1.0.0.
4. Make the repo Ujjwalkumar-pm/Notchy public and the release live before posting. Open it in a private window and check the link and download.
5. Instagram captions say "link in bio". Put the GitHub link in the bio, or remove those words.
6. Optional: the 9:16 launch plays the "Volume pop-up / AirPods / Eject" captions over VO about the music controls (about 44-48 s). It is not wrong, just a looser match than the rest.

## Re-check after neutral wording (16 Nov 2026)

Owner request: no "Claude", "Claude Code" or "Anthropic" in any public asset. Changed: launch beat 2 (voice + captions), install I6 and I8 (voice + captions), LinkedIn thumbnail subline, post-copy docx (body, hashtags, alt text), README. Only the changed VO lines were re-rendered; all 4 videos, both review voice tracks, 3 covers and the docx were rebuilt.

| Check | Result | Numbers / notes |
|---|---|---|
| Durations | PASS | Launch 16:9 70.0 s, 9:16 58.6 s; Install 16:9 and 9:16 87.0 s (unchanged) |
| Loudness / true peak | PASS | Launch -14.0 LUFS, -1.4 dBTP (both cuts). Install -14.0 LUFS, -1.3 dBTP (both cuts) |
| Specs | PASS | H.264 + AAC, 30 fps, 1920x1080 / 1080x1920 |
| New VO lines, whisper small.en | PASS | L2 "Your AI coding agent needs permission while you're in another app?" (3.73 s, was 3.41 s; beat now starts 5.9 s). I6 8.04 s (was 8.94 s). I8 7.90 s (was 7.50 s). Text heard as written, except the known "Nochi" for Notchy |
| Caption vs VO sync | PASS | Launch beat 2 voice 5.9 s, caption 5.95 s. Install I6 52 s, I8 72 s, subs moved to the new word timings (quit 77.3 s, drag 79.2 s) |
| Contact sheets, 1 fps, all 4 videos | PASS | No black slabs, no captions on Settings windows, 9:16 text inside the safe band. Fixed one wrap: the 16:9 problem headline now breaks between word groups, not before "you…" |
| "Claude/Anthropic" grep: captions (comp HTML), VO text, cover HTML, docx text, README | PASS | Only hits: the `~/.claude/settings.json` path in README (2x, a technical fact users need). Footage file names (claude-sessions.mp4, banner-claude-finished.mp4) are internal and not shown |
| Remaining on-screen "Claude" | Accepted | Small UI text inside the real app footage only: the "Claude · 4 min 12 s" line in the finished banner (launch about 15-19 s), the "Claude Code integration" row and "Turn off Claude Code integration?" sheet in Settings (install about 52-62 s and 73-77 s), and the "Claude" tab switch in welcome step 3. No caption sits on these labels |
