[English](README.md) | [简体中文](README.zh-CN.md)

# OpenMusic

A local-first, lightweight music player for Windows and Android, built with Flutter from a single codebase.

It aims to do two things well: **make building your library painless**, and **keep two devices in sync with one tap**. Your library stays your own files on your own disk.

> **v0.5.0** — playback and library experience (playlists/favorites, metadata scraping, lyrics, setup wizard) are complete and usable day to day. LAN sync is in development; see [ROADMAP.md](ROADMAP.md).

## Download

Grab the latest build from [Releases](https://github.com/zhpy2004/openmusic/releases/latest):

| Platform | File | Notes |
|---|---|---|
| Windows | `openmusic-v0.5.0-windows-x64.zip` | Unzip and run `openmusic.exe`. No installer. Keep the folder intact |
| Android | `openmusic-v0.5.0-android-universal.apk` | **Pick this if unsure** — works on every device |
| Android | `openmusic-v0.5.0-android-arm64-v8a.apk` | Any phone from 2017 onward. Half the size |
| Android | `openmusic-v0.5.0-android-armeabi-v7a.apk` | Older 32-bit devices |

On Android you'll need to allow installing apps from unknown sources. APKs are signed with a stable key, so later versions install as upgrades.

## Features

**Library**
- Pick a folder and scan; incremental rescans only touch files that actually changed (mtime + size)
- MP3 / FLAC / AAC / OGG / OPUS / WAV
- First launch walks you through it: pick folder → scan → fill in missing covers and lyrics → done
- Corrupt or unsupported files are skipped into a "problem files" list instead of aborting the scan

**Playback**
- Queue playback with gapless transitions (media_kit / mpv)
- Shuffle, and three repeat modes (off / all / one)
- Android: notification, lock screen, and Bluetooth headset buttons (audio_service)
- Windows: system media overlay and media keys (SMTC)

**Playlists and favorites**
- Create and edit playlists, plus a favorites list
- Import and export standard M3U8 with relative paths, so playlists move to other players
- Tracks are referenced by **content fingerprint**: renaming or moving files keeps the link intact. A track whose file is temporarily missing stays in the playlist, greyed out, rather than silently disappearing

**Metadata scraping**
- Per-track scraping plus whole-library batch fill, from open data sources: iTunes Search, LRCLIB, and MusicBrainz + Cover Art Archive
- **Audio file bytes are never modified.** Covers are written as `<track>.jpg`, lyrics as `<track>.lrc`, and title/artist corrections go into a database overlay — because touching the file header changes the content fingerprint, which would break every playlist and favorite that references the track
- Batch fill only adds what's missing and never overwrites covers or lyrics you already have. When a match isn't confident enough it skips rather than attaching the wrong artwork

**Lyrics**
- Line-level LRC scrolling, current line centered and highlighted, following playback
- Tap the cover on the now-playing screen to flip to lyrics. Scroll wheel or swipe to browse freely; the focus box follows the center of the viewport, tap ▶ to start from any line, and it returns to the current line after four idle seconds
- Plain-text lyrics without timestamps display too

## Build and run

Requires Flutter 3.44+ (Dart 3.12+).

```bash
flutter pub get
flutter run -d windows        # desktop
flutter run -d <android-device>
```

Tests:

```bash
flutter test
```

On Windows the tests use the bundled `tool/sqlite3/sqlite3.dll` — nothing extra to install.

To build signed release artifacts, create `android/key.properties` pointing at your own keystore (`storePassword`, `keyPassword`, `keyAlias`, `storeFile`). Without that file, release builds fall back to debug signing so the project still builds out of the box.

## Stack

Flutter · riverpod (state) · drift/SQLite (index) · media_kit (playback, mpv backend) · audio_service (Android media session) · smtc_windows (Windows media panel)

**Design principle: files are the source of truth.** SQLite is only an index cache — delete it, rescan, and nothing is lost. Playlists and favorites are first-class data carrying UUIDs and `updated_at` timestamps, reserved for cross-device sync. A track's cross-device identity is its content fingerprint: `xxh3(file size + first 128 KB + last 128 KB)`.

## Roadmap

See [ROADMAP.md](ROADMAP.md). Next up is LAN sync: mDNS discovery, pairing codes, and selective file mirroring.

## License

[MIT](LICENSE)
