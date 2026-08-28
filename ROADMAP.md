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

### v0.6.4 — LAN sync
The feature this project exists for: **add music and build a playlist on the desktop, then get it on your phone with one tap.** Landed in three parts.

1. **Discovery and pairing** — mDNS advertise/browse for `_openmusic._tcp`; on first connection both ends show a 6-digit code derived from an X25519 key agreement, and every later request is HMAC-signed
2. **Metadata sync** — one asymmetric round trip merges playlists, favorites, text corrections and play history. Per-row last-write-wins with tombstones, ties broken by device id so both sides independently reach the same result; play history is a union
3. **Selective file sync** — tick which playlists to "keep files for locally", then compare fingerprint manifests and pull only what's missing, with HTTP Range resume. **The fingerprint is re-computed before a file is allowed to land**, so a corrupted transfer never enters the library. Tracks whose files are missing stay visible and greyed out, with a per-track "fetch from paired device" action
4. **Safety floor** — **sync never deletes files.** Deletion is a manual, on-device action. Better a duplicate than a lost track

## In progress

### Polish and release

List and search performance at 10k tracks, first-scan responsiveness on large libraries, gapless verification in the field. Bar to clear: two straight weeks as the primary player with no showstoppers.

## Known issues

- **Android: the notification's play button doesn't resume from pause.** Pause, next and previous all work, as do Bluetooth/media keys and the in-app controls. Traced on a vivo device (Android 16): the press *does* reach the app — a fresh `AudioTrack` is created and starts — but playback is stopped again about 1.4 s later. The system log shows no foreground-service restriction and no audio-focus denial, so the earlier explanation (media_kit and audio_service contending for audio focus) is **unconfirmed**. Pinning it down needs instrumentation of the Dart-side resume path.
- Scraping sources (iTunes / MusicBrainz) often return Traditional Chinese titles for Simplified Chinese libraries. Mitigated by defaulting "apply text corrections" to off; covers and lyrics still apply. A real fix needs a Simplified/Traditional converter.
- Batch lyrics fill has no similarity threshold (covers do). LRCLIB matches server-side on title + artist + duration, and lyrics are deletable sidecar files, so the risk is contained.
- List scrolling and search performance on large libraries (1000+), and Bluetooth headset media keys, are not yet measured.

## Out of scope for now

iOS / macOS / Linux, equalizer, Chromecast / Android Auto, Subsonic client mode, word-level karaoke lyrics.

## Maybe later

**Pick your own music folder on Android** (today the scanner is fixed to the system music directory `/storage/emulated/0/Music`, so anyone keeping music elsewhere can't build a library; needs SAF directory picking).

The rest, roughly by demand: word-level + desktop lyrics → Subsonic client mode → equalizer → Android Auto.
