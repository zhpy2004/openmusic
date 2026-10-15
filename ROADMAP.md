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

### v0.7.0 — Polish
Clearing the backlog and measuring at scale.

- **Fixed: the notification's play button on Android 16.** `audio_service` borrows `KEYCODE_MUTE` as an internal key for the notification's play action, and Android 16 (verified on vivo) drops it as a real mute key before it ever reaches the app — pause worked, play silently did nothing. The play control now uses the standard play/pause media key. (The old audio-focus theory was wrong; on-device logging showed the press never reached Dart.)
- **Measured at 10,000 tracks** (vivo, release build): the first scan took about 3 min 17 s and the UI stayed interactive throughout; search results refresh within 1.5 s; removing the 10k rows takes under 10 s.
- **Gapless verified on-device**: two tones played back to back with no pause, click or level jump by ear, and the audio output stream stayed the same one across the boundary.
- Smaller fixes: search no longer treats `%` and `_` as wildcards; "no matches" is no longer reported as "library is empty"; M3U8 export writes `-1` for unknown duration; notification progress updates are throttled (seeks still apply instantly); flipping between cover and lyrics no longer re-fetches or flashes; the Windows media flyout shows "stopped" when a queue finishes.

## In progress

### Field soak

Two straight weeks as the primary player with no showstoppers.

## Known issues

- Scraping sources (iTunes / MusicBrainz) often return Traditional Chinese titles for Simplified Chinese libraries. Mitigated by defaulting "apply text corrections" to off; covers and lyrics still apply. A real fix needs a Simplified/Traditional converter.
- Batch lyrics fill has no similarity threshold (covers do). LRCLIB matches server-side on title + artist + duration, and lyrics are deletable sidecar files, so the risk is contained.
- The first scan of a very large library takes minutes (about 3 min for 10,000 small files) and runs on the main isolate. The UI stayed interactive in testing, but we have no frame-level data.
- Bluetooth headset keys were exercised through the same media-key path via adb, not with a physical headset.

## Out of scope for now

iOS / macOS / Linux, equalizer, Chromecast / Android Auto, Subsonic client mode, word-level karaoke lyrics.

## Maybe later

**Pick your own music folder on Android** (today the scanner is fixed to the system music directory `/storage/emulated/0/Music`, so anyone keeping music elsewhere can't build a library; needs SAF directory picking).

The rest, roughly by demand: word-level + desktop lyrics → Subsonic client mode → equalizer → Android Auto.
