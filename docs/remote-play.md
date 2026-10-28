# Remote play: how it works

The iPhone sees what plays on the TV apps (Android TV, webOS) under the same account, controls it, starts an item on a TV and hands over between iPhone and TV ("Play on…", "Continue on…", "Continue on iPhone"). Everything below is built in the three apps (2026-10-23/24) except "Waking an LG TV". Decisions and what was checked per step: `NOTES.md`, the "Remote play" entries.

## How it works

The Jellyfin server is the hub, not the local network. Every signed-in app is a *session* on the server. The iPhone reads the sessions of its own account and sends commands to them; the server passes the commands to the TV app over that app's WebSocket. This is the standard Jellyfin remote control that the official clients use, so it needs no discovery, pairing or LAN scanning, and works for every app the same way.

Server: Jellyfin 10.11 (see `server.md`).

**Reading** (iOS):
- `GET /Sessions?activeWithinSeconds=…`, filtered on `UserId` and `DeviceId` by the app, returns per session `DeviceName`, `Client`, `DeviceId`, `NowPlayingItem`, `PlayState` (`PositionTicks`, `IsPaused`, `AudioStreamIndex`, `SubtitleStreamIndex`, `CanSeek`), `SupportsRemoteControl` and `LastPlaybackCheckIn`.
- `controllableByUserId` drops every session without `SupportsRemoteControl`, so a TV app that is not controllable would not show at all.
- Live updates: poll while the screen is visible, or open the iOS app's own WebSocket (`/socket`) and send `SessionsStart` so the server pushes `Sessions` messages. The app polls every 5 s while in the foreground.

**Controlling** (iOS sends, the TV app executes):
- `POST /Sessions/{id}/Playing/{command}`: `Pause`, `Unpause`, `PlayPause`, `Stop`, `Seek` (with `seekPositionTicks`), `NextTrack`, `PreviousTrack`.
- `POST /Sessions/{id}/Command` with `SetAudioStreamIndex` and `SetSubtitleStreamIndex` (`-1` is off).
- `POST /Sessions/{id}/Playing?playCommand=PlayNow&itemIds=…&startPositionTicks=…&audioStreamIndex=…&subtitleStreamIndex=…` starts an item. "Continue on…" sends the tracks the iPhone plays (server stream indexes, `-1` is subtitles off); the TV starts with them. "Continue on iPhone" takes the TV's `AudioStreamIndex` and `SubtitleStreamIndex` from its `PlayState`. The Android TV app reports a track chosen in its own menu too, mapped back to the server index.

**Being controllable** (TV apps):
- `POST /Sessions/Capabilities/Full` with `PlayableMediaTypes: ["Video"]`, `SupportsMediaControl: true` and the supported commands.
- Keep the WebSocket `/socket` open (answer `ForceKeepAlive` with `KeepAlive`, reconnect after network loss and when the app returns to the foreground) and handle the incoming `Playstate`, `GeneralCommand` and `Play` messages.

## Live Activity (built 2026-10-28)

While the app runs, what plays on the TV the TV bar shows is also a Live Activity on the lock screen and in the Dynamic Island (`Feature/LiveActivity`, the widget extension `JellyCastLiveActivity`). It follows every poll; its buttons (play/pause, ±10 s) send the same commands as the now playing screen. With no push server it can't be updated while the app is suspended: the progress runs on by itself and after the expected end the activity shows it is out of date. Details in `NOTES.md`.

## Waking the Chromecast (built)

- **The Android TV Remote protocol (v2)** that the Google TV app and Home Assistant use: TLS on port 6467 for a one-time pairing (a code shown on the TV), then port 6466 for commands. The iPhone wakes the Chromecast (the TV follows through HDMI-CEC) and opens a JellyCast link (`jellycast://play?item=…&start=…&audio=…&subtitle=…`) that the Android TV app handles by opening the player. Then the server route above takes over.
- Not Cast Connect: it needs a Google Cast console registration and probably a Play Store app.

## Waking an LG TV (not built; written down 2026-10-23)

What it would take to give the LG TVs (C2, CS) the same "asleep · turns the TV on" as the Chromecast, on the home network. Nothing of this is checked on the TVs yet; the points marked **check** are the risks.

**Two parts, because an LG is the TV itself**

1. **Turn the TV on from standby: Wake-on-LAN.** A "magic packet" (UDP, port 9, the TV's MAC address 16 times) wakes the network chip of a TV in standby.
   - TV settings: *Turn on via Wi-Fi* / *TV On With Mobile* (Settings → General → Devices → External devices, the name differs per webOS version) and *Quick Start+* on. Without them the network is off in standby.
   - The MAC address: read it once while the TV is on, through the local API below (`ssap://com.webos.service.connectionmanager/getinfo`), or from the router. Wired and Wi-Fi have different MACs; use the one the TV is connected with.
   - **Check, the main risk:** a magic packet is normally a broadcast (`255.255.255.255` or `192.168.1.255`). iOS only lets an app send broadcast or multicast with Apple's `com.apple.developer.networking.multicast` entitlement, which needs the paid developer account and an approval from Apple. Options without it, in order: (a) a unicast magic packet to the TV's IP (works on many routers for a while after the TV went to standby, because the router still knows the MAC; not reliable after hours), (b) the Jellyfin server sends the packet (a small endpoint or plugin; the server may broadcast, see option 2A in the conversation of 2026-10-23), (c) the paid account plus the entitlement.
2. **Start JellyCast with the item: the webOS local API (SSAP).** A WebSocket on the TV, `wss://<tv>:3001` (webOS 23 and newer require the secure port; self-signed certificate) or `ws://<tv>:3000` on older ones.
   - **Pairing, once per TV:** send a `register` request with a manifest listing the permissions (at least `LAUNCH`, `CONTROL_POWER`, `READ_NETWORK_STATE`). The TV shows a prompt; after "Allow" it returns a `client-key`, which the iPhone stores and sends with every later `register` (then no prompt).
   - **Launch:** `ssap://system.launcher/launch` with `{"id": "nl.jellycast.webos", "params": {"itemId": "…", "startMs": …}}`.
   - **Turn off** (for "Continue on iPhone"): `ssap://system/turnOff`.
   - **Check:** that a Developer Mode app can be launched by id like a store app. Also: Developer Mode expires (the session lasts about 50 hours unless extended); when it lapses the app can't start, and then the launch fails.

**In the webOS app**

- Read the launch parameters on a cold start (`webOSSystem.launchParams` / `PalmSystem.launchParams`, a JSON string) and on a relaunch while running (the `webOSRelaunch` event on `document`), and open the player with the item at `startMs`, like `jellycast://play` on Android.

**In the iOS app**

- A second pairing flow ("Pair LG"): find the TV (its IP from the JellyCast session; discovery with SSDP would again need the multicast entitlement), connect over SSAP, show "Allow on the TV", store the client key and the MAC.
- Wake route for a paired LG: magic packet (one of the options above), wait until the SSAP port answers (a few seconds), `register` with the client key, `launch` with the item. The same 8 s deadline and the reachability probe (on port 3001) as for the Chromecast; the HDMI-CEC trick isn't needed, because the LG is the TV.
- "Continue on iPhone" on an LG: `turnOff` after the stop.

**Estimate**

The SSAP part (pairing, launch, turn off, launch parameters in the webOS app) is about the size of the Chromecast work, and simpler: plain JSON over a WebSocket, no client certificate. The open question is the magic packet; decide on (a), (b) or (c) first, ideally by trying a unicast packet on the C2 from the Mac (`wakeonlan -i 192.168.1.137 <mac>`) after a night in standby.

## Later: shared names and shared pairings (discussed 2026-10-24)

Today names and pairings live on each iPhone or iPad: every device pairs a Chromecast with its own code, and names given on a phone stay on that phone. That keeps households apart (a device that didn't pair a bedroom TV can't turn it on), but setting up several devices is a lot of work.

- **Names, for everyone, with no code:** Jellyfin keeps a custom name per device (Dashboard → Devices), and the sessions carry it (`HasCustomDeviceName`). Every iPhone then shows it. Still to check: that a sleeping paired TV picks up the new name too (it now keeps the name from pairing).
- **Sharing a pairing, option 1, advised against (decided 2026-10-24):** store the client certificate and its private key in Jellyfin's per-user storage (display preferences for client `jellycast`), so every device of that account uses one identity and pairs once per account. Don't build this: the private key would sit unencrypted in Jellyfin's database, and anyone who can sign in as that user could turn the TV on without ever pairing, which gives away what pairing protects. For a shared pairing, use option 2.
- **Sharing a pairing, option 2, "not now":** a Jellyfin plugin that pairs once and wakes the TV itself; the key never leaves the server, it can decide per user which TVs they may turn on, and it works away from home over the existing WireGuard. The most work.

## Open questions

1. How the TV bar shares the space with the download accessory? (The Live Activity is built, see above.)
2. Two sessions at once (both TVs): list, or the most recent one first?
3. ~~Should the now playing screen open by itself when the app starts while something plays?~~ Yes, once per open (cold launch or back to the foreground), on the first answer within 5 s, and never while the app is in use; otherwise the TV bar. Details in `NOTES.md` (2026-10-28).
4. After "Play on…": does the iPhone automatically follow that device?
5. AirPlay (the route button in the player) is not checked on direct play and transcode.

## Out of scope

- The iPhone as a target that other devices control.
- Casting to Google's default Cast receiver: our own TV apps play instead.
- Remote play outside the house (the server is LAN only).

## Testing

- LG: the C2 and the CS (the rule to leave the CS alone was lifted on 2026-10-23).
- Android TV: on the Chromecast with Google TV.
- iOS: on the iPhone; the simulator is fine for UI, the sessions are real.
