#!/usr/bin/env bash
# Build the launch-video footage intermediates (H.264, crf 14) in video/launch/media/ from the
# PNG sequences in video/footage/ (Task 2). Trims: banner-drive-eject stops at frame 130 (the empty
# black slab follows at ~4.4 s); swipe-tabs is sped up 1.6x; alerts-focus-moon is held 3 s longer.
# volume/brightness are cut before their exit slab and held.
# settings-appearance is not used (focus flicker at frame 6); Black->Glass comes from settings-theme-glass.
set -euo pipefail
cd "$(dirname "$0")/../footage"
M=../launch/media; mkdir -p "$M"
O=(-c:v libx264 -preset fast -crf 14 -pix_fmt yuv420p -g 10 -movflags +faststart)
for s in hover-open-music approval-dwell-allow banner-claude-finished banner-meeting calendar-hero banner-teams \
         alerts-scroll music-seek-shuffle banner-airpods banner-charger \
         settings-theme-glass settings-open-from; do
  ffmpeg -loglevel error -y -framerate 30 -i "$s/frame-%05d.png" "${O[@]}" "$M/$s.mp4"
done
ffmpeg -loglevel error -y -framerate 30 -i banner-drive-eject/frame-%05d.png -frames:v 130 "${O[@]}" "$M/banner-drive-eject.mp4"
ffmpeg -loglevel error -y -framerate 30 -i swipe-tabs/frame-%05d.png -vf "setpts=PTS/1.6" -r 30 "${O[@]}" "$M/swipe-tabs-fast.mp4"
ffmpeg -loglevel error -y -framerate 30 -i alerts-focus-moon/frame-%05d.png -vf "tpad=stop_mode=clone:stop_duration=3" "${O[@]}" "$M/alerts-focus-moon.mp4"
# volume/brightness: stop at frame 78 (the pop-up fades to an empty black slab from ~frame 82) and hold it 2 s
for s in volume-popup brightness-popup; do
  ffmpeg -loglevel error -y -framerate 30 -i "$s/frame-%05d.png" -vf "trim=end_frame=78,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=2" "${O[@]}" "$M/$s.mp4"
done
# claude-sessions (static Claude tab) held to 4.5 s for the L2 problem line
ffmpeg -loglevel error -y -framerate 30 -i claude-sessions/frame-%05d.png -vf "tpad=stop_mode=clone:stop_duration=1.5" "${O[@]}" "$M/claude-sessions.mp4"
cp closed-notch/still.png "$M/closed-notch.png"
cp settings-tabs/still.png "$M/settings-tabs.png"
