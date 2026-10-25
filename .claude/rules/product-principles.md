# Product principles

Why JellyCast for iOS exists and what every choice is tested against. This file comes before the other rules: if a rule or idea conflicts with it, this file wins. Adapted from the Android TV app (`../jellycast-android-tv/.claude/rules/product-principles.md`); the TV-specific parts (D-pad, 2 GB RAM) are left out.

## Why this app

JellyCast on the Chromecast proved that a Jellyfin client can be simple, fast and pretty at once. The iOS app brings that to the iPhone and iPad, on the same server and library.

## Core

1. A simple overview of the library.
2. Play every movie, series and episode, with as little work for the server as possible (direct play, otherwise remux, transcode only as a last resort).
3. Never stutter, never lose a tap, never make the user wait for a screen.

## Priority for every choice

**Works well > responds instantly > looks good.**

- Rather slightly less pretty and smooth than very pretty and slow. When in doubt, choose the simpler variant.
- An effect that drops frames on the device goes, however pretty it is.
- What doesn't contribute to "browsing and playing" doesn't belong in the app.

## Input

- Every tap has a directly visible effect in the next frame (pressed state, navigation, or a skeleton).
- Scrolling stays at the display's full refresh rate (120 Hz on ProMotion). Images and data arriving later never move what the user is looking at or touching.
- Back (swipe or button) returns to the item you came from, at the same scroll position.

## Straight through on tap: skeleton instead of waiting

- Navigate in the same frame as the tap. Never wait for data before the new screen appears.
- Show what is already known right away (title, year, poster from the list); the rest is a skeleton in the exact sizes of the real content, so nothing shifts when the data arrives.
- Show the skeleton only when loading takes longer than ~100 ms; no flash of skeleton for fast data.
- The skeleton is calm: flat blocks with at most a slow pulse in opacity. No shimmer.
- An error shows a message in place of the content with a "Try again" button. Never an empty screen or an endless skeleton (after 10 s without data it is an error).

## Approve the design first

- The user approves the design of every main screen before it is built. Design in Paper (via the Paper MCP), in the existing JellyCast style (`design-style.md`), for iPhone and iPad.
- Functional screens you rarely see (server, sign-in, debug) may be built simply in the existing style first.

## Images and memory

- Request every image at its display size in pixels via the Jellyfin image API (see `docs/server.md`). Never load original posters or 4K backdrops.
- One image cache, bounded in memory, with a disk cache.

## Battery and network

- Prefer direct play and hardware decoding: they cost the least battery and the least server work.
- Nothing runs in the background except playback reporting and, later, Picture in Picture or AirPlay.

## Performance budget (release build, on the device)

| Measurement | Budget |
|---|---|
| Cold start to interactive | ≤ 1 s |
| Hitches while scrolling a long list | none visible; hitch ratio < 5 ms/s in Instruments |
| Start playback (direct play or remux, LAN) | ≤ 3 s to first frame |
| Memory after 5 min of browsing | ≤ 250 MB |

Record every measurement with date and device in `NOTES.md`. Exceeding the budget is a bug and gets fixed before new features.

## Check on every change

1. Does every tap respond instantly?
2. Does the content stay where the user put it when data arrives?
3. Does the new screen appear right after the tap, with skeleton and what's already known?
4. Does this element add something to browsing or playing? If not: leave it out.
5. Is it checked on the iPhone or iPad (release) and within budget?
