# The Jellyfin server

What the iOS app talks to, and what the Android TV app (`../jellycast-android-tv`) already learned about it. Facts with a date were measured or checked then; recheck when a test gives reason to.

## The machine

- **Address:** `http://192.168.1.4:8096` in the home LAN, plain HTTP (no TLS). Not reachable from outside the house yet.
- **Jellyfin 10.11** (10.11.11 on 2026-10-08). The Android app uses Jellyfin Kotlin SDK 1.8.12.
- **Hardware:** Intel N150 mini PC with hardware acceleration on **Intel QuickSync** (checked 2026-10-08). It can transcode one 4K stream to SDR at about 24 fps, but seeking in a transcode is slow. Starting point for every client: **the device does the work, the server as little as possible.**
- **Storage:** the media is on an HDD that spins down when idle. The first request after a quiet period takes ~7 s (measured 2026-10-12 after ~40 min of silence); after that 50–100 ms. The Android app reads 64 KB of the file (`warmUpMedia`) while the user is still choosing, so the spin-up falls before Play instead of after.
- **Network:** Wi-Fi dips between server and client happen (2026-10-12: buffering every ~5 s on a 22 Mbps stream that later played fine). The cause is on the LAN side, not the internet.
- **Sign-in:** Quick Connect is on (Dashboard → General → Quick Connect). Accounts: the user's own account and a separate `claude` account for testing (its password is the user's, never in the repo).

## Plugins

- Default plugins only (TMDb, OMDb, MusicBrainz, AudioDB, Studio Images), plus **Intro Skipper 1.10.11.24** (installed 2026-10-12, source `https://intro-skipper.org/manifest.json`).
- Intro Skipper fills **Media Segments** (Intro, Recap, Outro, …), available via the API right after its analysis. The analysis costs hours of CPU on the N150 and keeps the HDD busy meanwhile, so it is not complete for the whole library.
- The server has no studio images.
- **Metadata order (2026-10-25):** movies and series fetch OMDb before TMDb, so `CommunityRating` is the IMDb rating and `Overview` the IMDb plot; `CriticRating` is the Rotten Tomatoes critics' score (movies only). Episodes and seasons keep TMDb first, so an episode's rating is TMDb's. Jellyfin keeps one rating and one text per item: the first fetcher with a value wins.

## The library (profile of 2026-10-11)

2073 items: 49 movies and 2024 episodes. Full table and test items: `../jellycast-android-tv/docs/playback-test-matrix.md`.

| What | Distribution | Meaning for iOS |
|---|---|---|
| Container | **mkv 1829** · mp4 242 · mov 1 · m2ts 1 | AVPlayer does not open MKV. Almost everything needs a remux (HLS) or a different player. |
| Video | HEVC Main 10 1064 · HEVC 8-bit 47 · H.264 960 · VC-1 1 | HEVC and H.264 decode in hardware on iPhone and iPad. VC-1 always transcodes. |
| Resolution | 4K 484 · 1080p 1352 · 720p 236 | |
| HDR | SDR 1773 · DV p8.1 165 · HDR10 70 · DV p7.6 21 · DV p8.6 20 · HDR10+ 17 · DV p5 5 · HLG 1 | iOS plays HDR10, HLG and DV p5/p8 in AVPlayer (in MP4/HLS); p7 only as its HDR10 base layer. |
| Audio | AC3 · EAC3 (296 items with Atmos) · AAC · DTS 157 · DTS-HD MA 172 · TrueHD 86 · FLAC · PCM | AVPlayer: AAC, AC3, EAC3 (+ Atmos), FLAC, ALAC. **No DTS and no TrueHD**: pick another track or transcode audio only. |
| Subtitles | SRT 13615 tracks · PGS 2979 · mov_text 1035 · ASS 239 · VobSub 98 | AVPlayer shows WebVTT in HLS and `tx3g` in MP4. PGS and VobSub are images: burn-in or an own renderer. |
| Size | max. 116.8 Mbps, 102 GB per file, up to 75 subtitle and 18 audio tracks | Large track lists must not slow the start. |

## API lessons from the Android app

- **Validate a server** with `GET /System/Info/Public` (name, version, id) before signing in.
- **PlaybackInfo:** always send `MediaSourceId`, send no subtitle track by default, request HLS via `main.m3u8`, and never ask for `External` subtitles. Without these four the N150 transcoded 4K video needlessly (2026-10-09).
- Send a **DeviceProfile** that describes exactly what the device plays, and show every `TranscodeReasons` in the UI or log. A transcode "because of bitrate" with no limit set was a client-side fallback, not the server (2026-10-12).
- **Transcode (checked 2026-10-23):** Jellyfin 10.11 encodes HEVC in 8 bit only (`main` is forced in `EncodingHelper`) and, with tone mapping on, maps every HDR source to SDR whatever `hevc-rangetype` the client sends. On the N150 with QSV, 4K HDR to 720p–1440p HEVC runs at 3–5× realtime, the first segment after 2.5–12 s (disk spin-up included). Without a stop report the server keeps transcoding until its ~60 s kill timer.
- **A file the player can't read** (broken MKV cues, M2TS): ask the server for a one-time remux instead of a transcode.
- **Episodes:** all episodes of a series in one request (`/Shows/{id}/Episodes`): the largest series (279 episodes) is 350 KB, 0.17 s.
- **Movies and series** are queried by type (`Movie`/`Series`, recursive over all libraries), not per library.
- **Next up and continue watching:** `getNextUp` with `DateCreated`, plus in-progress items; "touched" time decides the order. Stopping in the end credits (from the Outro segment, otherwise the last 30 s) marks an item as watched.
- **Images:** always via the image API with the `tag` (cache-safe URL), `fillWidth`/`fillHeight` at display size in pixels, `quality=85`, and `Accept: image/webp`. Never `percentPlayed` in an image URL: it breaks the cache.
- **Playback reporting:** start, progress every 10 s, pause/seek, and stop (also when the screen closes). Positions are in ticks (1 tick = 100 ns).
- **Server discovery** uses a UDP broadcast on port 7359. On iOS that needs the multicast entitlement, which the free personal team can't get: enter the address by hand.
