[English](ROADMAP.md) | [简体中文](ROADMAP.zh-CN.md)

# Roadmap

A single-maintainer project for personal use, kept in scope on purpose. Every milestone has to be independently usable when it lands — no stacking of half-finished features.

## Done

### v0.1.0 — Playback skeleton
Folder scanning, library list, playback queue, and system media integration on both platforms (Android notification/lock screen/Bluetooth keys, Windows SMTC). Bar to clear: both devices work as an everyday music player.

### v0.2.0 — Playlists and favorites
Playlist editing, favorites, M3U8 import/export. Tracks are referenced by content fingerprint, and playlists can hold tracks whose files are temporarily missing (shown greyed out) — groundwork for cross-device sync.

### v0.3.0 — Metadata scraping
Per-track scraping from three pluggable open sources (iTunes / LRCLIB / MusicBrainz + Cover Art Archive). Core constraint: **never modify audio bytes** — covers and lyrics go to sidecar files, text corrections to a database overlay.

### v0.4.0 — Lyrics
Line-level LRC scrolling, current-line highlight, tap-to-seek, free browsing with automatic return, plain-text fallback.

### v0.5.0 — Library setup wizard
First-run wizard (pick folder → scan → batch fill → done) plus whole-library batch fill for covers and lyrics, with conservative matching that only fills what's missing.

### v0.6.0 — Localization
English and Simplified Chinese throughout the app, following the system language by default with a manual override in Settings. Scan problems became typed objects so the service layer no longer builds user-facing sentences.

## In progress

### LAN sync (next milestone)

The feature this project exists for. Goal: **add music and build a playlist on the desktop, then get it on your phone with one tap.**

1. **Discovery** — mDNS advertise/browse for `_openmusic._tcp`
2. **Pairing** — on first connection both ends show a 6-digit code; after manual confirmation they exchange keys, and subsequent traffic is HTTP + token auth over the LAN
3. **Metadata sync** — exchange entity manifests (UUID + `updated_at`), merge per-row last-write-wins; play history is a union; playlist definitions sync in full
4. **Selective file sync** — each device chooses which playlists to "keep files for locally", then compares fingerprint manifests and pulls only what's missing, with HTTP Range resume. Tracks missing files in non-mirrored playlists appear greyed out with a per-track "fetch from paired device" action
5. **Safety floor** — **sync never deletes files.** Deletion is a manual, on-device action. Better a duplicate than a lost track

### Polish and release

List and search performance at 10k tracks, first-scan responsiveness on large libraries, gapless verification in the field. Bar to clear: two straight weeks as the primary player with no showstoppers.

## Known issues

- **Android: the notification "play" button doesn't resume from pause, and there's no lock screen control.** media_kit (libmpv manages its own audio focus) and audio_service contend for focus on the notification-triggered resume path. In-app playback controls work fine. Fixing it means unifying focus ownership, which needs repeated verification on real hardware.
- Scraping sources (iTunes / MusicBrainz) often return Traditional Chinese titles for Simplified Chinese libraries. Mitigated by defaulting "apply text corrections" to off; covers and lyrics still apply. A real fix needs a Simplified/Traditional converter.
- Batch lyrics fill has no similarity threshold (covers do). LRCLIB matches server-side on title + artist + duration, and lyrics are deletable sidecar files, so the risk is contained.
- List scrolling and search performance on large libraries (1000+), and Bluetooth headset media keys, are not yet measured.

## Out of scope for now

iOS / macOS / Linux, equalizer, Chromecast / Android Auto, Subsonic client mode, word-level karaoke lyrics.

## Maybe later

**Pick your own music folder on Android** (today the scanner is fixed to the system music directory `/storage/emulated/0/Music`, so anyone keeping music elsewhere can't build a library; needs SAF directory picking).

The rest, roughly by demand: word-level + desktop lyrics → Subsonic client mode → equalizer → Android Auto.
