#!/usr/bin/env bash
# Build the install-video footage intermediates (H.264, crf 14) in video/install/media/ from the PNG
# sequences in video/footage/ (Task 2). Holds/trims are timed to video/install/build.py:
#  welcome-2: 0.93 s lead hold so the Calendar row turns green ~1.5 s after "Each Allow button…", 3.2 s tail hold
#  welcome-3: 2.53 s lead hold so the Menu bar icon switch flips on "Switch it on here"; cut at frame 133
#             (the window fades out from frame 134 and would leave an empty desktop)
#  context-menu: frames 1-98 (menu open from frame 17, closes from ~99), held 1 s
#  settings-sidebar-pan: frames 38-135 (General -> Notch -> Tabs -> Alerts) at 1.5x; stops before About
#  settings-turnoff-sheet: frames 1-118 (sheet up from frame 35; it is dismissed with Cancel at ~124), held 0.6 s
# settings-appearance is not used (glitch frame 6).
set -euo pipefail
cd "$(dirname "$0")/../footage"
M=../install/media; mkdir -p "$M"
O=(-c:v libx264 -preset fast -crf 14 -pix_fmt yuv420p -g 10 -movflags +faststart)
f() { ffmpeg -loglevel error -y -framerate 30 -i "$1/frame-%05d.png" -vf "$2" "${O[@]}" "$M/$3.mp4"; }
f welcome-1-hover        "null"                                                                     welcome-1
f welcome-2-permissions  "tpad=start_mode=clone:start_duration=0.93:stop_mode=clone:stop_duration=3.2" welcome-2
f welcome-3-tabs         "trim=end_frame=133,setpts=PTS-STARTPTS,tpad=start_mode=clone:start_duration=2.53:stop_mode=clone:stop_duration=1" welcome-3
f context-menu           "trim=end_frame=98,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=1" ctx
f settings-sidebar-pan   "trim=start_frame=37:end_frame=135,setpts=(PTS-STARTPTS)/1.5,fps=30,tpad=stop_mode=clone:stop_duration=0.5" sidebar
f settings-turnoff-sheet "trim=end_frame=118,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=0.6" turnoff
cp closed-notch/still.png "$M/closed-notch.png"
cp settings-general/still.png "$M/settings-general.png"
cp welcome-3-tabs/frame-00160.png "$M/menubar.png"  # window already gone, menu-bar icon on
