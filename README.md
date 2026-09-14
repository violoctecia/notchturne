<h1 align="center">Notchturne</h1>

<p align="center">
  Apple Music in your MacBook notch — artwork, synced lyrics, playback, calendar and clipboard.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
  <img src="https://img.shields.io/badge/dependencies-none-blue" alt="No dependencies">
</p>

<p align="center"><i><a href="README.ru.md">Русская версия</a></i></p>

![Notchturne in action](docs/demo.gif)

## What it is

Collapsed, it lives in the menu bar beside the notch: album art on the left, three bars
breathing along on the right. Point at the bars and they turn into a pause button.

Hover the notch itself and a panel grows out of it, with whatever you've turned on:

| Section | What's inside |
|---|---|
| **Player** | artwork, title, artist, a progress bar you can drag to seek, transport controls, a heart wired to the real *Favorite* state in Music, and a menu that adds the track to any of your playlists |
| **Lyrics** | line by line, following the song and highlighting where it is — scroll them yourself any time |
| **Calendar** | the current month, today circled, a dot under days that have something on them |
| **Clipboard** | the last few things you copied; click one to put it back |

The gear in the top-right corner opens the settings inside the panel: which sections to
show, how many clipboard entries to keep, and the interface language. The menu bar icon
can be hidden — quitting then lives in those same settings.

## Requirements

macOS 14 Sonoma or later, a MacBook with a notch, and Apple Music.

## Install

**Option 1 — prebuilt (easiest):**

1. Download `Notchturne.zip` from [Releases](../../releases/latest)
2. Unzip it and drag `Notchturne.app` into `/Applications`
3. Launch it with **right-click → Open** (not a double click) — the app isn't signed with
   an Apple Developer certificate, so the first launch shows a "developer cannot be
   verified" warning. Right-click → Open → confirm, and it opens normally from then on

**Option 2 — build from source** (only the Xcode Command Line Tools are needed, not Xcode itself):

```bash
git clone https://github.com/violoctecia/Notchturne.git
cd Notchturne
./build.sh
cp -R build/Notchturne.app /Applications/
open /Applications/Notchturne.app
```

<details>
<summary>Why macOS asks for permission again after an update</summary>

macOS recognises an app by a fingerprint of its contents, and that changes with every
build. So after installing a new version you'll grant Music access once more — once per
version.

If you build it yourself and often, make a certificate: **Keychain Access → Certificate
Assistant → Create a Certificate**, name it `Notchturne Dev`, self-signed root, type
**Code Signing**. `build.sh` picks it up automatically and tells you which one it used —
the fingerprint then stays put.
</details>

## Permissions

One, and it's visible in System Settings: **Automation → Music**. Calendar access is
requested only if you switch the calendar on, and never otherwise.

Nothing else — no Accessibility, no Screen Recording, no Input Monitoring. Hovering is
detected by reading the cursor position rather than intercepting events, precisely so
that no permission is needed for it.

## Where the data comes from

Playback and artwork come from Music itself over AppleScript, with no private APIs. Two
features reach the network, and both switch off in the settings; with them off the app
makes no connections at all:

| Feature | Goes to | Sends |
|---|---|---|
| Lyrics | `lrclib.net` | artist, title, album, duration |
| Artwork fallback | `itunes.apple.com` | artist, album |

Apple doesn't hand its own lyrics to third parties, so [LRCLIB](https://lrclib.net) — an
open, community-run database — is the only route available. Coverage is uneven outside
the English-language mainstream.

Clipboard history lives in memory only and disappears when you quit; nothing is written
to disk. Entries that apps mark as confidential are skipped, which is how password
managers ask to be left alone.

## Limits

- **Apple Music only for now** — see What's next.
- A catalog track that isn't in your library gets saved there first when you add it to a
  playlist — Music refuses to file a subscription track anywhere else. It takes a few
  seconds; the button shows a spinner.
- Lyrics without timecodes are shown, but nothing is highlighted: passing a guess off as
  a precise hit would be dishonest, so those you scroll yourself.

## What's next

Right now Notchturne only talks to Apple Music. **Yandex Music**, **Spotify** and
playback **in the browser** are next — the source will be picked in the same settings panel.

## License

MIT
