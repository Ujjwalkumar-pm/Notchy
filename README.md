# Notchy

Your MacBook's notch, finally useful.

Notchy lives in the notch at the top of your screen. It shows the small things you'd otherwise miss, without making you switch apps.

- **AI coding agent approvals.** When your AI coding agent needs permission, a card drops out of the notch. Rest your pointer on it, then click **Allow once** or **Deny**. If you'd rather answer in the terminal, just ignore it.
- **Never miss a meeting.** One minute before a meeting with a join link, a banner shows **Join**. The Calendar tab counts down to your next one.
- **Work alerts without switching apps.** Teams and Outlook messages and unread counts wait in the Alerts tab. By default, banners stay quiet during calls, Focus and full-screen video.
- **Music.** Artwork, play/pause, skip, drag to seek, shuffle and sound output.
- **Volume and brightness.** A slim pop-up replaces the big macOS box.
- **Devices.** AirPods battery, charger, and USB drives with Eject.
- **Make it yours.** Reorder or swipe tabs, Black or Glass theme, where it opens from, and how it animates.

Free and open source (GPL-3.0).

## Requirements

- macOS 14 or later
- Best on a MacBook with a notch. On other Macs it sits at the top center of the screen.

## Install

1. Download **Notchy.zip** from the [latest release](https://github.com/Ujjwalkumar-pm/Notchy/releases/latest).
2. Double-click the zip, then drag **Notchy** into **Applications**.
3. Open Notchy. Notchy isn't notarized by Apple, so the first time macOS says it can't verify it. Click **Done**, then open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. You only do this once.
4. The welcome window walks you through three steps: hover the notch, allow only the permissions you want (Calendar, Accessibility, Focus, Bluetooth), and pick your tabs.

There's a 90-second install video in the release notes.

### What Notchy changes on your Mac

- **AI coding agent integration.** Notchy adds its own entries to `~/.claude/settings.json` so your coding agent can send it status and permission requests. It backs the file up first and never edits other entries. If Notchy isn't running, the agent just asks in the terminal as usual. Turn off the coding-agent integration in **Settings → General**.
- **Start at login** is on by default. Change it in **Settings → General**.
- **Privacy.** Alerts and calendar events stay in memory on your Mac. Notchy never sends them anywhere. The only network listener is on `127.0.0.1`, for your coding agent.

## Settings

Right-click the notch and choose **Settings…**. You can also turn on a menu-bar icon, or open Notchy again from Applications.

## Uninstall

1. In **Settings → General**, turn off the coding-agent integration (this removes Notchy's entries from `~/.claude/settings.json`).
2. Right-click the notch → **Quit Notchy**.
3. Drag Notchy from Applications to the Trash.

## Build from source

Needs the Xcode Command Line Tools (Swift 6) on macOS 14 or later.

```sh
swift build                 # debug build
swift run NotchyChecks      # tests
bash scripts/bundle.sh      # release build → /Applications/Notchy.app
```

`scripts/bundle.sh` creates a local self-signed code-signing certificate the first time, so permissions survive rebuilds.

## Credits

Built by Ujjwal Kumar.

- Now Playing uses [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause).
- Some window and notch-shape code is derived from Atoll (GPL-3.0), itself derived from boring.notch (GPL-3.0); see `reference/atoll/NOTICE`.

## License

GPL-3.0. See [LICENSE](LICENSE).
