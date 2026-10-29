# NOTES

Decisions, open questions and findings on the devices. Newest first in each section.

## Status (2026-10-25)

Finished: sign-in and the library cache, Home, Library with search, series page, movie detail, the player (AetherEngine: the original file, no server transcode unless a lower quality is chosen), streaming quality, info tabs with the AI chat, remote play with the TV apps (`docs/remote-play.md`), the iPad layout, downloads (Compact by default, Original, offline start, progress synced afterwards, "Download next 5") and lists L1 (`docs/playlists.md`): make and order lists of movies and episodes and play them on the iPhone. Every decision is under Decisions below.

Not checked on a device yet:

- The Mac as "Designed for iPad" (2026-10-25): builds with `-destination 'platform=macOS,arch=arm64,variant=Designed for iPad'`, installed by hand in `/Applications/JellyCast.app` (`Wrapper/JellyCast.app` plus a `WrappedBundle` symlink) and it launches. Same 7-day profile as the iPhone. Playback, downloads and remote play on the Mac are not checked.
- The iPad layout on the user's iPad (the install was refused while Developer Mode was off).
- "Continue on iPhone" from the now playing screen of a TV.
- AirPlay on direct play and on a transcode.

Not built, worth knowing for later:

- **Lists on a TV (L2):** the TV apps take only the first item of a play command and need a queue. Plan: `docs/playlists.md`.
- **Compact downloads with HDR:** Jellyfin 10.11 forces 8-bit HEVC and tone-maps every HDR source, so this needs a newer server or another route.
- **A 5.1 track (E-AC-3) in Compact**, for the iPad with headphones that do spatial audio.
- **Waking the LG TVs** from the iPhone: worked out in `docs/remote-play.md`, not built.
- **Shared TV names and pairings** across devices: options in `docs/remote-play.md`.
- **Paid Apple Developer account** (€99/year): not yet, the user wants the app finished first (2026-10-24). Until then the expiry warning on the Downloads tab covers trips.

## Open questions

### Playback engine: what the spike did not cover

The user checks battery use over a full film, PiP and AirPlay on the iPhone.

### Signing

- The free personal team (`QML5BA5PYA`) works for both devices, but an installed build stops launching after 7 days and needs a reinstall from Xcode. A paid Apple Developer account (€99/year) gives a year and TestFlight. The user decides. Offline use on a trip makes the 7-day limit a real problem: an expired build can't be reinstalled without a Mac.
- The multicast entitlement is not available on the free team; server discovery works around it with a unicast sweep (see Decisions).

## Decisions

### TV and download pill in the iPad's top bar (2026-10-29)

- **Asked by the user:** the full-width TV bar along the bottom fits a phone but not an iPad, least of all in landscape, where the tab bar sits at the top. Compared options (corner card, top-bar pill, side panel, narrow capsule); a corner card was dropped because the mini player can show at the same time.
- On the iPad (`layout.isRegular`) the bottom accessory is off; what plays on a TV, else the running download, is a toolbar item at the top right, left of each screen's own items (`topBarPill()` in `TopBarPill.swift`, added in `routes` to every tab root and pushed screen). TV: still, title and a progress line; paused: a pause sign over the still. Download: the state icon and title. Below 1000 pt wide (portrait) only the still in a progress ring, or the download icon. A tap opens the now playing screen or Downloads. The iPhone keeps the bar.
- Library hid its navigation bar everywhere; on the iPad it now shows, or the pill had no place there.
- The mini player no longer moves up for the TV bar on the iPad.
- Checked in the iPad Pro simulator against the real Chromecast session: Home landscape (title pill) and portrait (ring), Library, a series page, a tap opening now playing. Not checked: the download pill, the paused state, closing now playing still slides down instead of towards the pill. Installed on the iPad and the iPhone 18 Pro Max (the iPhone 14 was unreachable).

### Playing on in the background (2026-10-28)

- Leaving the app while a video plays keeps it playing: in a PiP window when the video was on screen (full or mini player), as sound otherwise; locking the screen keeps the sound going. Back in the app the video goes on where the sound is.
- Why it stopped before: iOS pauses an AVPlayer whose layer is on screen when the app leaves, and PiP only existed on the native routes. Now the native layer is detached from its player in the background (unless PiP is open) and put back on return; PiP also runs on the software route through the engine's `softwarePiPSource` (sample buffer PiP). A paused play the engine tore down after its 15 s grace window is reloaded at its position on return (`needsForegroundVideoRestore`).
- PiP first: the native layer is only detached a second after the scene went to the background, when no PiP window started in that time. Detaching it right away beat the automatic PiP start on the iPhone (found by the user: a swipe home sent the video to the Dynamic Island as sound). When iOS paused the player in that second, it is played again. Locking the screen therefore has up to a second of silence.
- PiP never attached on the iPhone (log: "PiP possible false, route remoteBypass"): it was set up when `$videoRoute` sent, which is before the engine stores the route and before the native layer exists. It now also attaches on `$currentAVPlayer`, and every engine `@Published` is read a turn after it sends, the lock screen state included (it showed the previous play/pause state).
- Checked by the user on the iPhone 18 Pro Max (2026-10-28): playing on in the background and on the lock screen, and a swipe home opens PiP (remote bypass route).
- The lock screen, Control Center and Dynamic Island show the play (`SystemNowPlaying`): image (backdrop or episode still), title, series and "S1 · E8" or the year, progress, play/pause, ±10 s and scrubbing; headphone buttons work too. Written to the shared `MPNowPlayingInfoCenter` on every route, not the engine's `MPNowPlayingSession`, so both routes behave the same.
- Order in the Dynamic Island and on the lock screen: playing in the app, then the TV Live Activity, then nothing. The TV's activity ends while the app has a play and comes back when it closes.
- The TV remote screen's volume button trick set the audio session to ambient and turned it off afterwards, which stopped a play in the app from going on in the background. It now puts the player's category back.
- Built and checked to start in the simulator; PiP, the lock screen and the background can only be checked on a device. Installed on the iPhone 18 Pro Max and the iPad (the iPhone 14 was unreachable). Still to check: auto PiP on both routes (an MKV with DTS for the software route), locking during play, the lock screen buttons, the next episode starting in the background, and the TV activity coming back after closing the player.

### Live Activity for a TV (2026-10-28)

- While the app runs and the TV bar shows a TV, that playback is a Live Activity: lock screen (image, series or movie, "S1 · E8 · title", "Playing on chromecast", a progress bar and remaining time that run by themselves, play/pause and ±10 s) and the Dynamic Island (compact: the brand mark and a progress ring; minimal: the ring; expanded: image, title, episode line, progress, play/pause). One activity, for the TV the TV bar shows; another TV ends it and starts a new one. It ends when the session is gone after an answer, on sign out and when Live Activities are off in Settings.
- New target `JellyCastLiveActivity` (widget extension, `nl.jellycast.ios.LiveActivity`, embedded in the app). Its own folder `JellyCastLiveActivity/`; `RemotePlaybackAttributes.swift`, `RemotePlaybackIntents.swift`, `BrandMark.swift`, `JellyCastColors.swift` and `Localizable.xcstrings` from `JellyCast/` are members of both targets (membership exception set in `project.pbxproj`).
- **App Group `group.nl.jellycast.ios` works with the free personal team** (provisioned with `-allowProvisioningUpdates`, both targets). The app writes the item's image (216 px wide JPEG) to the group container and the activity reads it; without the container it would show the brand mark.
- No push server, so the app can only update the activity while it runs (every 5 s poll, and straight away after a command). In between the progress runs on from the last answer with `ProgressView(timerInterval:)`/`Text(timerInterval:)`. The stale date is the expected end of the item plus a minute (a pause: 30 min after the last answer); stale, the activity shows "Open JellyCast to update", a static bar and no buttons.
- The buttons are `LiveActivityIntent`s; they run in the app (also when the system has to launch it), update the activity at once and send the command through `RemoteSessions.send`, or straight to the server with the stored session when the app wasn't running.
- On the lock screen with the iPhone locked or in always-on, iOS shows the remaining time as "45:--": seconds are hidden in that state by the system.
- Checked: the simulator (lock screen with the real Chromecast session and its image, compact Dynamic Island) and the iPhone 18 Pro Max (lock screen with The Last of Us on the Chromecast). Not checked: the expanded Dynamic Island (a long press in the simulator opened the app), the buttons (not pressed, the TV was in use), going stale, the next episode updating it, a background launch by a button, the iPad (installed, no Live Activities on iPad).
- DEBUG launch argument `-liveActivityPreview` starts the activity with sample data and stops real updates, for screenshots.

### Swipe down in full screen leaves full screen (2026-10-28)

In full screen (iPhone landscape, iPad video only) a swipe down returns to the regular player, the same as the full-screen button: the iPhone turns back to portrait, the iPad shows the info panel again. The video springs back instead of sliding away. From the regular player a swipe down still minimizes to the mini player.

### Now playing on a TV opens when the app opens (2026-10-28)

- Opening the app (cold launch or back to the foreground) while a TV plays opens that TV's now playing screen, as if the TV bar was tapped. The decision is taken once per open, on the first successful sessions answer after opening, and only if that answer came within 5 s; on a cold launch it waits for the splash to finish. A later answer, a TV that starts while the app is in use, or the screen being closed leaves it to the TV bar until the next open.
- Not when the app's own player plays (full or mini player, also PiP), not while any sheet, cover or alert is presented (checked on the UIKit root, so sheets of child views count too), and not when the remote screen is already open. With two TVs it takes the one the TV bar shows (the most recent). The rule is `NowPlayingAtOpen.session`; the wiring is `showTVNowPlayingAtOpen` in `MainView`.
- Checked on the iPhone and the iPad: cold launch with the Chromecast playing opens its now playing screen. Not checked on a device: back to the foreground, closing it staying closed, and the cases that should skip it (tapping isn't possible from the Mac).

### Home as one tile grid (2026-10-28)

- Home is a YouTube-style grid of 16:9 tiles instead of the hero and the horizontal rows (Up next, New, Not started). No headings, no filters: scroll, tap, long press.
- Order (`LibraryIndex.homeFeed`): Continue watching (`continueWatching`), then New (`newEntries`, last 30 days), then Not started: series (`notStartedSeries`), then unwatched movies (`notStartedMovies`), each newest added first. Each movie or series shows once, in the first group it is in; an episode counts as its series.
- Tap does what the old cards did: a Continue watching tile plays (as the Up next cards did; the hero's backdrop opened the page, its frame played), a New or Not started tile opens the series page or movie detail.
- iPhone: no navigation bar on Home; the grid starts under the status bar and the profile button sits on the first tile. iPad: the top tab bar and the profile button in the toolbar stay. iPad landscape: 3 columns, the first tile spans 2 columns and 2 rows, its image cropped so its bottom lines up with the two tiles beside it.
- Title and meta are one line each, so every tile in a row has the same height.
- iPad landscape (2026-10-29, asked by the user): the first tile's image frame now reaches down to the bottom of the lower tile beside it, so the images line up at the top and the bottom; the 16:9 image sits in it with thin black bars above and below instead of being cropped. Its title starts at the same height as the lower tile's; its meta ends a little lower (larger font).
- The "All" link of New to the library sorted by newest went with the row.
- Found on the iPhone 18 Pro Max: measuring the top safe area from a background view of Home fed back into Home's own height and SwiftUI never settled (watchdog kill at launch, 0x8BADF00D). Not on the iPhone 17 simulator or the iPad. `RefreshableScrollView(padsSafeAreaTop:)` now pads the content by the inset it measures itself.
- No unit test target exists yet, so `homeFeed` has no test.

### Rating site setting (2026-10-25)

- Settings → Ratings picks IMDb (default), Rotten Tomatoes or TMDB for the rating next to a title and every title and person link. The server holds one community rating and one text per item, so the server was changed instead of the app fetching from the sites itself (that would need an API key per user): OMDb before TMDb for movies and series, then a full metadata refresh. Texts are IMDb's whatever the setting.
- What each choice can show follows from the server (`docs/server.md` → Plugins): IMDb rating for movies and series, Rotten Tomatoes only for movies, TMDB only for episodes. Rotten Tomatoes has no id in Jellyfin, so its links are searches.
- Where OMDb has no rating for a title, the TMDb value stays and is shown as IMDb's; rare, not distinguishable in the data.

### App Review on Jellyfin's demo server (2026-10-25)

- App Review signs in on `https://demo.jellyfin.org/stable` (Jellyfin 12.3, only freely licensed films), approving the Quick Connect code in a browser as user `demo` with an empty password. Steps for the reviewer are in `../store-assets/review-instructies.md`, for others in the README.
- The bare `https://demo.jellyfin.org` fails: it redirects to `/stable/web/`, and the app reads that HTML as "not a Jellyfin server". The official clients follow the redirect and strip `/web/`; JellyCast doesn't yet.
- Quick Connect sign-in on the demo works on the iPhone (checked by the user). Browsing and playback on Jellyfin 12 are not checked yet.
- Still missing: sign-in with a password. Reviewers expect a username and password; the browser step works around it.

### License: PolyForm Shield, with a CLA (2026-10-25)

- The app goes in the App Store for a small price, with the source public. PolyForm Shield 1.0.0 allows forking, changing and building for your own devices, and forbids any competing product, free or paid, in any store. MIT (until now) would have let anyone sell a copy; the Android TV and webOS apps stay MIT.
- The name, logo and app icon are kept out of the license, so a copy can't use the name either.
- Contributors agree to `CLA.md` in their first pull request; it grants the right to ship their work in the paid app and to relicense it later, for example to MIT. Opening up later is always possible; the versions released under Shield stay under Shield unless they are relicensed explicitly.
- Must be in place before the repository goes public: a version published under MIT stays MIT.
- Not done yet: a licenses screen in the app (LGPL and MIT ask for the notices to travel with the binary).

### Now playing screen follows the TV, not the session (2026-10-25)

- After "Next episode" the screen said the TV had stopped while the TV bar already showed the next episode: the screen held on to one server session id, and the next item can come back under another session. It now follows the TV's device id and takes over its new session; after a next episode or play command it asks the server once more 2 s later, so the gap between two items doesn't stay on screen until the next poll.
- Checked by the user on the iPhone with a TV on 2026-10-25: the screen moves on to the next episode.

### Lists L1: Jellyfin playlists, out of the way (2026-10-25)

- Lists are the server's playlists (`/Playlists`), so they need no storage of our own. The user wants them out of the way, because watching a set of titles in a row is rare: no tab and no row on Home. They open from the Library filter menu ("Lists"), and "Add to list…" is an action in the long-press drawer (movies, series and episodes, plus seasons on the series page). On the series page and in the player the drawer gets the navigation only while the page is inside the tabs, so the player's episode rows have no "Add to list…".
- A series or season is added as its episodes of that moment; the server expands a series itself, and a season is sent as its episode ids from the library index.
- Moving an entry (`/Playlists/{id}/Items/{entryId}/Move/{index}`) answers 400 with the API key and works with a user's token.
- Continue starts at the first item not fully watched. The player keeps the list as a `PlayQueue`: its next item comes in place of the next episode, at the end and on the "Next ·" pill; tapping another item of the list in the player keeps the list, anything else drops it.
- Rows move by holding and dragging (a list with `onMove`, outside edit mode). A row is a tap gesture, not a button: a button takes the long press and the drag never starts.
- Checked in the simulator on 2026-10-25 as user claude: create, add a movie, an episode and a season, move, swipe to remove, delete the list, Continue, and the list going on from Friends S10 E17 to S9 E1.

### Subtitles: only the cues on screen, and tracks follow a hand-over (2026-10-25)

- The pile-up was ours: the overlay drew every cue in `engine.subtitleCues`, which holds the decoded cues around the play position, not only the current one. It now draws the cues whose start and end enclose `clock.sourceTime`, as the AetherEngine README prescribes.
- "Continue on…" sends the audio and subtitle track that play now; "Continue on iPhone" starts with the TV's. Direct play maps between the engine's track ids and the server's indexes by order among the file's own tracks (the server also lists external subtitle files).

### Subtitle list: your languages first, then A–Z (2026-10-25)

- The server user's subtitle language, then audio language (`SubtitleLanguagePreference`, `AudioLanguagePreference`; for "han" Dutch, English) come first; the rest is sorted by name in the app's language. Within a language: plain, then SDH, then forced.
- The label is always the language. A track name from the file only shows underneath when it adds something ("Simplified"); names that repeat the language, SDH, forced or the format, release names on every track and names over 40 characters are dropped. SDH and forced become a small mark (from the file flags or the name, e.g. a track only called "SDH").
- The format (SRT, ASS) is gone; image subtitles (PGS, VobSub) are marked "Image", because the size and background settings do not apply to them.
- Tracks that still look the same get a number ("Spanish 2"): Netflix releases carry two Spanish and two Portuguese tracks (Spain/Latin America, Portugal/Brazil) without saying which is which.
- Same logic in all three apps (Android `SubtitleEntries.kt`, webOS `trackLabels.ts`, iOS `SubtitleOrder.swift`).

### Long press opens a drawer (2026-10-25)

- The system context menu is replaced by a drawer from the bottom (`actionDrawer`, `Core/DesignSystem/ActionDrawer.swift`): the item on top (poster, or still for an episode), then the choices as sheet rows, the sheet as tall as its content. A choice runs once the drawer is gone, so play, navigation and the download or "Play on" sheet don't collide with it.
- The long press is a `highPriorityGesture(LongPressGesture)` (0.4 s, with a haptic). `onLongPressGesture` and a UIKit long-press recognizer both let the button under it fire on release as well (it opened the movie); the high-priority one doesn't, and a short tap and scrolling from a card still work. Checked in the simulator.
- Watched choices follow one rule (`WatchedActions`): Mark as watched while not fully watched, Mark as not watched once watched or begun, so something in progress gets both. Same for a series by its progress.
- "Open" became "Go to movie" / "Go to series". Continue watching items keep the full set.
- Episodes on the series page and in the player's episode list open the same drawer with only the two watched choices.

### Feedback round: player, long press, home, library (2026-10-24)

Asked by the user with concrete layouts, built straight away and shown as screenshots instead of a Paper design first.
- **Player:** the ±10 s buttons are gone; a double tap on the right half of the video jumps 10 s forward, on the left half back (`TapToSeekLayer`). Further taps on the same side add 10 s each, as in YouTube, and the seek runs once 650 ms after the last tap, so a streamed file is asked for one position. The first tap of a double tap still toggles the controls at once (no delay on a single tap); the second undoes it. VoiceOver keeps "Back/Forward 10 seconds" as actions. Checked in the simulator with logging: two taps 35 ms apart seeked from 51.5 s by +10 s.
- **Long press everywhere** (`mediaContextMenu`): play or continue (a series plays its next episode), play from the beginning when in progress, play on a TV, watched/not watched (hidden offline), download/remove/cancel (movie and episode; a series downloads with Download next on its page), open the page or go to the series, IMDb. On Home (hero, Up next, New, Not started), Library tiles, search episodes and the person page. `LibraryStore` is now in the environment for it. Left out: favourites (nothing in the app shows them yet).
- **Home hero:** the round play button is replaced by the same continue frame as Up next (still or backdrop with progress), centred on the backdrop with the play button on it, a thin border and a shadow. One shadow on one hero frame, not a shadow per card.
- **Library:** no title or navigation bar; posters in a grid on the iPhone too (three across, title and year under each, progress and the watched mark on the poster). The search field floats above the tab bar with a filter button beside it: kind, status, genre and sort in one menu. What narrows the grid shows as chips with a cross at the top. The person page uses the same grid. The placeholder Search tab is gone, since search now sits in Library at thumb height.
- **Settings:** the engine spike screen and its code (`Feature/Spike`) are removed.

### Downloads D4: series (2026-10-24)

- **Download next:** a round button in the series page's button row (`DownloadNextButton`) takes the next 5 unwatched episodes from where the series stands (`progress.next`, or the first episode of a series not started; specials left out), skipping what is already on the device or queued. A tap fetches each episode's plan, then a confirmation shows the range, the size and the free space ("S1 · E3 – S1 · E6 · about 7.66 GB · Free 435 GB"). As many as fit are queued, in order. Filled in once all are there.
- **Watched downloads** go a day after they were watched (`DownloadSettings.removesWatched`, on by default; decided 2026-10-24). Only a watch after the download counts, so a movie downloaded to see again stays. Checked after every library sync and at launch (`DownloadStore.tidy`).
- **Keep series ahead** (`keepsSeriesAhead`, off by default): a series downloaded with Download next keeps its next 5 episodes; at home, after a sync, the missing ones are queued. Removing the whole series in the Downloads tab stops keeping it.
- Both settings in Settings → Downloads.
- Checked in the simulator: the button on Carrie (E2 downloaded, in progress) offered E3–E6, 4 episodes. Not confirmed there, to spare the server four transcodes. **Confirmed by the user on the iPhone (2026-10-24):** Download next queues the episodes and they convert one at a time. Not checked: removal after a day, keeping ahead after watching.

### Downloads D3: watch progress offline (2026-10-24)

- A download plays without playback reports (no server, no session). Its position goes to `OfflineProgress` instead: every 10 s, on pause and on stop, saved as `Downloads/progress.json` with the time it was watched, so it survives the app being killed in airplane mode.
- The library shows these positions on top of the cached and the synced copy (`LibraryStore.applyingOfflineProgress`), only where they are newer than the server's `LastPlayedDate`.
- **Sending:** after every successful server check (launch, return to the app, network back) and right after stopping a download when the server answers. Per item: `GET /UserItems/{id}/UserData`; if the local time is newer than the server's `LastPlayedDate`, `POST /UserItems/{id}/UserData` with position, played and `LastPlayedDate` = the time watched (checked with curl on 10.11.11: the server keeps that date as given; a playback report would stamp it with now). An older local position is dropped, so watching further on a TV afterwards wins. The library refreshes when anything was sent.
- Checked in the simulator (user "claude", Carrie 1x2): played the download offline, killed the app at 0:50; relaunched offline, the position was kept; relaunched online, the server had 0:50 with the time watched and the local list was empty. A local position older than the server's was not sent and was dropped.
- Not checked: on the iPhone in airplane mode with the TV app showing the position afterwards.

### Downloads D2: offline (2026-10-24)

- **Playing a download offline** already worked from D0 (`PlayerSession.loadDownloaded`); the user checked it on the iPhone: download an episode, close the app, airplane mode on, open the app, play from Downloads.
- **Reachability:** `LibraryStore.isServerUnreachable` comes from the server check and, unlike `serverProblem` (the alert), stays until a check succeeds. It is checked again on every network change (without an alert), so the app goes offline and back by itself. `DownloadStore.canReachServer` uses it too; before, dismissing the alert made downloads look possible.
- **Offline start:** when the first server check fails, Home is still showing and something is downloaded, the app switches to Downloads instead of showing the alert. Otherwise the alert shows as before; with downloads it now says only downloads play.
- **Dimming** (`availableOffline(_:)`, environment `isOffline`): offline, a movie or episode that isn't downloaded, or a series without a downloaded episode, is shown at 35% and ignores taps. On Home (hero, Up next, New, Not started), Library (rows, tiles, episode search results), the series page's play button and every episode row.
- **Build expiry:** `BuildExpiry` reads `ExpirationDate` from `embedded.mobileprovision`; Downloads shows "This app opens until …", and from 3 days before as a warning to reinstall from the Mac before a trip. Nothing in the simulator (no profile).
- **Fix after the user's test on the iPhone:** opened in airplane mode, everything stayed available until a pull to refresh. The first check ran in the scene phase task, so a phase change at launch could cancel it after it was already counted as done. It now runs once in its own task and only counts when it wasn't cancelled; the scene phase check skips the first activation. No network on the device (`NetworkMonitor`) counts as offline at once, without waiting for the server.
- Debug launch arguments: `-simulateServerUnreachable YES` and `-buildExpiresInDays <n>`.
- Checked in the simulator with both: the app opened on Downloads without an alert, with the warning; Home, Library and the Carrie series page dimmed everything but Runner and Carrie 1x2; a tap on a dimmed card did nothing.

### Downloads D1: interface (2026-10-24)

Design approved by the user (Paper, page iOS, section 9). Built from the spike, which is gone from Settings.
- **`DownloadStore`** (`Core/Downloads`): the list and the queue, one download at a time, saved as `Application Support/Downloads/index.json` next to one folder per item. At launch it adopts folders the list doesn't know (the spike's files, matched through the library), sets interrupted downloads back in the queue and goes on; a running Original in the background session keeps running. Speed and time left are measured from the first progress of a run, so a resumed download doesn't claim it is almost done.
- **Choice:** `DownloadPlan` estimates Compact at 4.9 Mbit/s × runtime (measured) and takes the original's size from `MediaSources.Size`; Compact unless the original is no bigger. A movie asks in the sheet (Compact, Original, free space, time); an episode starts at once with that choice, a long press opens the sheet. Free space counts what the queue still needs.
- **Compact** runs the spike's segment loop (`CompactDownloader`) inside a `BGContinuedProcessingTask` and waits for the server when the network drops; **Original** uses the background session (`OriginalDownloader`), paused with resume data.
- **Interface:** the round button with five states in the movie's button row, in the player's info and in every episode row (not on the series page's own row: "Download next 5" is D4); the Downloads tab (in progress with "Pause all", then per movie or per series with size and watch state, swipe to remove; a series opens its downloaded episodes); the running download in the bottom accessory on the other tabs when no TV session shows there. Downloading is offered when the library's server check reaches the server, rechecked on a tap. The first version asked whether the server's address is in the device's own subnet, which refused downloads at home on the user's iPhone (2026-10-24): a host name or VPN address never matches.
- Dutch strings added to the catalog by hand (xcodebuild doesn't extract them), with plurals for movies, episodes and not watched.
- Checked in the simulator against the server: Runner (4K SDR) as Compact, 3.48 GB, converted at the sheet's estimate; the app relaunched halfway went on by itself; Carrie 1x2 started with one tap, queued behind it and began when Runner was done; Runner played from `compact.mp4`. Not checked: an Original from the sheet, pause and remove from the menu, the accessory on the iPad.

### Download spike D0 (2026-10-24)

Settings → Developer → Download spike (`Feature/Spike/DownloadSpike*`, `OriginalDownloader`). A finished download plays from disk wherever the item is played (`PlayerSession.loadDownloaded`), without any server call, reports or segments.
- **Compact:** the player's HLS transcode request (HEVC + stereo AAC, 1920 wide, 5 Mbit/s), the fMP4 init segment and every media segment appended in order into one `compact.mp4`. That file is a valid fragmented MP4: ffprobe reads it whole, seeking works, and AetherEngine plays it as a `file://` URL. The server answers each segment once it is converted; the 3 s segments run back to back.
- **Resume:** progress (next segment, bytes) is saved after every segment. After the app was killed halfway, a new transcode fetched from that segment on and the file has no gap in its timestamps (checked with ffprobe: 0 gaps over 1 h 37). A transcode started at a segment uses that segment's time, so the parts fit.
- **Measured (simulator on the home LAN):** Busboys (1080p SDR, 97 min, original 1.9 GB): Compact 3.54 GB (4.9 Mbit/s) in ~9.5 min, ~10× realtime. **The Compact was bigger than the original**, so the rule "Original when it isn't bigger" is needed. The original came in 47 s at 317 Mbit/s with the background session. Earlier by curl: Solo (4K HDR10) to 1080p started at ~6.6× realtime; the output is 8-bit `bt709`, so HDR is tone-mapped to SDR as expected.
- **Original:** `GET /Items/{id}/Download` with a background `URLSession`, one task, the file moved out in `didFinishDownloadingTo`. The engine plays it from disk too.
- **Background for Compact:** a `BGContinuedProcessingTask` (identifier `nl.jellycast.ios.download.*` in `BGTaskSchedulerPermittedIdentifiers`) is submitted at the start. The simulator has no `BGTaskScheduler` ("not available on this platform"), so whether it keeps going with the screen locked is for the iPhone.
- **On the iPhone (the user, The White Lotus 2x6):** the download starts, and in the background iOS shows it in the Dynamic Island, so `BGContinuedProcessingTask` works on the free team. With airplane mode on it stopped and stayed in the list, but after the network came back it did not go on by itself; Pause and Resume did.
- **Fix:** a segment that gets no bytes for 20 s (60 s for the first one of a transcode, disk spin-up) or a network error puts the job in "Waiting for the network"; every 3 s the app checks that the device is online and the server answers, then starts a new transcode from the next segment. The Dynamic Island subtitle says "Waiting for the network" meanwhile. Checked in the simulator with `-downloadSpikeDropAt 40` (a simulated dropped connection): it went on within a second and the file has no gap. Not installed yet: the user's download was still running.
- **Airplane mode playback works** on the iPhone (the user, 2026-10-24).
- **After a restart the list was empty** while the files were still on disk (the job list lived only in memory). The spike screen now rebuilds it from `Application Support/Downloads` at launch: a finished `compact.mp4` or `original.*` is Done, a `compact.part` with its progress is Paused and can resume. The title comes from the library, or from the `name.txt` saved next to the file; the footer shows what the downloads use. Checked in the simulator after a relaunch.
- **D0 done (the user, 2026-10-24):** the restored list and the automatic resume work on the iPhone; next is D1, the interface.
- Still open: a 4K HDR film as Compact (time, colours), and both kinds playing in airplane mode. Whether iOS expires the background task while it waits for the network is open.

### Now playing on a TV: compact header, skip, Chromecast volume (2026-10-24)

- The header rolls up into a bar (title, pause, progress) once a tab scrolls up and comes back at the top or on a tap on the bar. It is one view whose height animates (0.4 s, longer than the 250 ms rule, because the user asked for a smoother feel).
- "Skip intro/recap/preview" on the TV uses the same media segments and rule as the iPhone player, seeking the TV to the segment's end.
- Chat answers render Markdown (blocks parsed in `MarkdownBlocks`, inline via `AttributedString`), no dependency; the system prompt now allows Markdown.
- **Chromecast volume:** while the screen is open for a paired Chromecast, a second remote connection (port 6466, feature flag 64 for volume) stays open; −/+ send `KEYCODE_VOLUME_DOWN/UP` (25/24), which the Chromecast passes on over HDMI-CEC like its own remote. The iPhone's volume buttons do the same: iOS has no API for them, so a hidden `MPVolumeView` and KVO on `outputVolume` read each press and undo it (ambient, mixing session; the phone's volume is restored on leaving). The TV's `RemoteSetVolumeLevel` (field 50: max 6, level 7, muted 8) shows as a bar for 2 s in place of the device name. **Confirmed by the user on 2026-10-24:** the volume works on the Chromecast from the iPhone. Still unknown: whether the level bar shows the TV's volume or only the Chromecast's own (the simulator's pairing was replaced by the iPhone's, so it can't be checked from here). LG volume is left out for now (needs the SSAP pairing).

### Info tabs and AI chat (2026-10-24)

Designed in Paper (page iOS, option 8) and approved by the user, built without "known for" for now.

- Under the summary: tabs Episodes + Cast for an episode, Cast + Related for a movie, plus Chat once an API key is set. An episode also shows "About {series}" with the series IMDb link and TMDB rating.
- Cast: actors with age, birthplace and a short biography from the server's person items (one batch `/Items?ids=` request), then the makers under a divider. Episodes carry directors, writers and guest stars; producers (and often the actors) come from the series. The server knows no creator. "Known for" needs TMDB and a real IMDb rating needs OMDb; both left out.
- Chat: the user's own API key (Claude or ChatGPT), stored per provider in the Keychain (this device only). Claude via the Messages API with `claude-opus-5-5` and server-side fallback; ChatGPT via Chat Completions with the model picked from `/v1/models` because the names change often. The system prompt holds the series overview, the episodes up to the current one, and the cast; with "No spoilers" on, the model is told not to reveal anything after the current episode. One conversation per series or movie; "New conversation" clears it.
- Web search (on by default, toggle in Settings → AI chat): Claude gets the `web_search_20260209` server tool (at most 5 searches per question, a paused turn is resumed up to 3 times); ChatGPT moved to the Responses API with the `web_search` tool, because Chat Completions only searches with separate search models. Sources from the citations show as links under the answer. With search on, the system prompt says to search only when needed and to leave out what search results reveal about later episodes. Not yet tried with a real key.
- Replies are streamed (Claude: Messages SSE, rebuilding the content blocks so the turn can be sent back unchanged; ChatGPT: Responses SSE), so each search query, the sites found and the answer show while they arrive.
- Signing in with a ChatGPT or Claude subscription instead of a key is not possible for third-party apps today; revisit if that changes.

### iPad layout (2026-10-24)

Designed in Paper (page iOS, artboards "iPad — …", rules in "iPad — regels en gedrag") and approved by the user. The user's iPad is an iPad (A16), 820 × 1180 pt.

- **Regular vs compact:** `EnvironmentValues.layout` (`LayoutMetrics`) is regular only when both size classes are regular. A large iPhone held sideways is regular in width but compact in height and must keep the iPhone layout (full-screen player). A narrow iPad window (Split View, Slide Over) gets the iPhone layout too.
- **Regular sizes:** margin 32 pt, running text at most 640 pt wide, Up next cards 300 pt, posters 150 pt, cast 88 pt, hero logo up to 420 × 120 pt.
- **Hero:** 16:9 under the status bar, never taller than 55% of the window (`HeroFrame` layout); on the iPhone in portrait that never applies.
- **Library:** a poster grid (`LibraryTile`, adaptive columns of at least 150 pt) and the kind picker beside the chips.
- **Series page:** in landscape two panes: the hero, buttons and overview on the left (440 pt), seasons and episodes scrolling on the right. Episode rows get a 192 pt still and two lines of the overview.
- **Info panel** (`ItemInfoPanel`): `InfoPanelArrangement.column` or `.split`. The column keeps the text at 640 pt and, from 1100 pt wide, puts the cast beside it as a list (`CastList`, "All N cast members" expands). The split puts the header (video or TV status) and the summary on the left (64.5%), episodes, cast and related titles on the right.
- **Player:** on the iPad landscape is the split, portrait the column; the full-screen button no longer turns the screen there but switches to the video alone and back, in either orientation.
- **Now on TV:** the same split in landscape.
- **Mini player:** 320 pt, 480 pt large; 16 pt above the bottom, because the iPad draws the tab bar at the top.
- **Checked in the iPad (A16) simulator**, portrait and landscape: Home, Library (6 columns landscape, 4 portrait), series page (two panes), movie detail (cast beside the text), player split with episodes and cast, video only and back in both orientations, mini player at 320 pt. A `LazyVGrid` inside the library's `LazyVStack` stayed empty after switching to Series, so the grid is built as rows of its own. Installed on the iPad. The TV bar sits at the bottom on the iPad too, but about 89 pt above the edge, so the mini player moves up 88 pt (not 56) while it shows. Now on TV checked on the iPad itself against the LG (portrait column, landscape split with controls left and episodes and cast right); `devicectl device capture screenshot` and `devicectl device orientation set` work on the iPad, tapping does not.

### Layout pass: tab bar, sheets, swipe to close (2026-10-24)

- Tab bar: Home, Library, Downloads and a separate round Search button, so it has the same full width with and without the TV bar (with two tabs it hugged its items and stretched once the TV bar showed). Downloads and Search are placeholders for now. On iOS 27 a `Tab(role: .search)` only stands apart as its own circle with `.tabViewSearchActivation(.searchTabSelection)`.
- Audio and subtitles sit behind one button (`speaker.wave.2.bubble`) that opens the same sheet in the player and for a TV; quality is a sheet too. SwiftUI's `Menu` reports no open state, so with menus the controls faded while a menu was open; with sheets the player keeps its controls up until the sheet closes.
- "Play on…" is the TV circle under the title everywhere: movie detail, the player (it also stays in the player's top bar) and the now playing screen of a TV, where it replaces "Continue on iPhone" and offers this iPhone or another TV (the first TV then stops).
- The now playing screen of a TV closes with the player's swipe (`SwipeToClose`): it follows the finger, shrinks and slides away.

### Audio in the original language (2026-10-23)

Dubbed releases (Italian, French, Spanish; ~120 files, e.g. Star City, The White Lotus) mark the dub as the default track. Jellyfin keeps no original language, so `OriginalLanguages` asks Wikidata: IMDb id (an episode uses its series) → P364 → ISO 639-1, one SPARQL request without a key, 2.5 s timeout, cached per IMDb id. `AudioLanguage` then starts on the first of: original language, English, Dutch, else the default track (commentary never). The original file switches the engine's track before `play()`; a transcode asks the server for that track. Same rule as the Android TV app. Checked in the simulator: The White Lotus S3E1 (Italian default) switched to the English track.

### Remote play 3: continue on a TV from the player (2026-10-23)

- A TV button among the player's top buttons (before AirPlay) opens the Play on… sheet as "Continue … on": the same TVs, no "This iPhone", starting at the player's position. Choosing one starts it there (server route, or wake route for a paired Chromecast) and closes the player on the iPhone. The player is a full-screen cover, which didn't get `RemoteSessions` from the environment; `MainView` passes it in.
- Checked in the simulator: the button, and the sheet with "Continues from 9:04". Handing over to the TV is not checked from the simulator (its pairing was replaced by the user's iPhone).

- **The other way round (user's wish):** "Continue on iPhone" next to IMDb on the now playing screen stops the TV through the server, turns a paired Chromecast off with Power when it reports it is on (the TV follows over HDMI-CEC), and starts the iPhone player at the TV's position. The player opens half a second later, because two full-screen covers can't swap in one go. Not checked on a device yet.

### Remote play 2a and 2b: play on a TV, wake the Chromecast (2026-10-23)

- **2a:** "Play on…" (TV button next to play on the movie detail and series page) lists TV apps that take commands. The TV apps keep the command WebSocket for as long as the app is in front and open the player on "play now". The WebSocket keep-alive does **not** update a session's `LastActivityDate` (an idle TV app stayed at the same time for 95 s), so the TV apps report their capabilities every minute and the iPhone lists a TV while it reported in the last 150 s. When the Android app goes to the background the server drops its session.
- **2b (Chromecast only):** the Android TV remote protocol v2 (the one the Google TV app and Home Assistant's androidtvremote2 use), written by hand in `Core/AndroidTV`: a self-signed RSA certificate made on the phone and kept in the Keychain, TLS with Network.framework, varint-framed protobuf. Pairing on port 6467 (the TV shows a 6-character hex code; the secret is SHA-256 over both RSA moduli and exponents plus the code after its check byte), then port 6466: answer configure/set-active/pings, send `KEYCODE_WAKEUP` when the TV reports it is off, then an app link `jellycast://play?item=…&start=<ms>` that the Android app opens (singleTask, `parsePlayLink`).
- Checked against the real Chromecast from the simulator (user filter off locally): pairing worked (code read from the TV with `adb screencap`), and with JellyCast in the background "Play on" started The Gentlemen on the TV; stopped right away. **Not checked:** waking from standby (the TV was on), and pairing from the user's iPhone (each phone pairs with its own certificate).
- **TV stayed off (found by the user):** when only the LG was turned off, the Chromecast stayed awake (its CEC setting `power_state_change_on_active_source_lost` is `none`), JellyCast stayed open, and a play through the server started without any HDMI-CEC message, so the TV stayed off. Opening a link sends nothing either; Home does (One Touch Play: `<Text View On>` + `<Active Source>`, seen in `dumpsys hdmi_control`), also when the Chromecast is already awake. So for a paired Chromecast the iPhone always takes the remote route: wake if asleep, Home, wait 0.7 s, then the link. Keys sent right after the handshake were lost: the TV registers its `virtual-remote` input device only then, hence a 0.6 s wait. Checked from the simulator with the TV on: Home arrived, One Touch Play went out, the link opened the film.
- **Waking from standby (found by the user):** asleep, the Chromecast's remote service took the connection but ignored `KEYCODE_WAKEUP`; the link only ran once the user pressed power (logcat `AtvRemote`, 23:00). It now sends `KEYCODE_POWER` (26), as Home Assistant does, and only when the TV reports `RemoteStart.started == false`. **Confirmed by the user on 2026-10-23:** from standby the Chromecast and the TV turn on and JellyCast starts the film, with "Turning on …" on the iPhone meanwhile. The iPhone shows "Turning on …" above the tab bar while it works, and a failure on any screen. A Chromecast keeps one pairing per client name ("JellyCast iPhone"): pairing the iPhone dropped the simulator's.
- **Away from home (found by the user, on mobile data with WireGuard):** the sleeping Chromecast was listed, a tap waited very long and then failed. Waking needs a direct connection from the phone to the TV, which this VPN doesn't route. The wait came from a bug: on a timeout the NWConnection wasn't cancelled, so the task waited for the system's own TCP timeout. Now cancelling ends the connection, connecting gives up after 3 s and the whole wake (wake, Home, link) after 8 s. And when the sheet opens, each paired TV gets a 1.5 s TCP probe on port 6466; one that doesn't answer isn't listed, with the note that the Chromecast can only be reached from the home network. That also holds while JellyCast on it is open (the user expected it gone away from home): a paired TV always takes the remote route, so it only shows once the probe reached it.
- **Forget and pairing names:** a long press on a paired TV in the sheet offers "Forget pairing" (removes it from this phone only; the TV keeps trusting the certificate, which does no harm). New pairings use a name per device, "JellyCast iPhone 3F2A" (model plus the start of the device id), because the simulator's pairing was dropped when the iPhone paired with the same name. **Assumption, not checked:** that the TV keeps one pairing per name, not one in total; checking it could break the user's working pairing. The iPhone's existing pairing (name "JellyCast iPhone") keeps working.
- Paired TVs live in `UserDefaults` with their address, updated from the session when the TV's IP changes; names given on the phone are kept per device id.

### Remote play 1c: choose what plays next (2026-10-23)

- The now playing screen has a next episode button (series only, in the top bar) and plays a tapped episode or movie on the TV (`POST /Sessions/{id}/Playing?playCommand=PlayNow&itemIds=…&startPositionTicks=…`), continuing where it was, as the user chose. On a TV that can't be controlled a tap still opens the item's page.
- Seen while checking: the CS (old build) plays Blow and shows the watch-only screen, as meant.

### Remote play 1b: control the TV (2026-10-23)

- **A TV that stops without a stop report** (app closed, crash, install, TV off, Wi-Fi gone) stayed "playing" on the server, so the iPhone never cleared it (found by the user on the Chromecast). Our TV apps report every 10 s, also while paused, so a session that hasn't checked in for 30 s now counts as stopped (`RemoteSession.isSilent`). This uses the phone's clock against the server's `LastPlaybackCheckIn`; the Mac and the server were 4 s apart.
- When a session reports `SupportsRemoteControl`, the now playing screen shows the controls from the Paper design "Nu op tv (bedienen, fase 1b)": close, device, audio and subtitles, stop; back 10 s, play/pause, forward 10 s; a bar to drag. Without it the screen stays as in 1a.
- Commands: `POST /Sessions/{id}/Playing/{Pause|Unpause|Stop|Seek}` and `POST /Sessions/{id}/Command` with `SetAudioStreamIndex`/`SetSubtitleStreamIndex` (`JellyfinClient.send`). The screen shows the result right away and takes the TV's own report 0.8 s later.
- The audio and subtitle menu shows only for direct play: the Android TV app can only switch tracks that are in the stream.
- The layout is checked in the simulator against a real session with "controllable" switched on locally; no command was sent, because the Chromecast didn't have the new build yet and the user was watching on it.

### Remote play 1a: see what plays on the TV (2026-10-23)

- How it works: `docs/remote-play.md`. While the app is in the foreground it asks the server every 5 s which sessions of this user play something (`GET /Sessions?activeWithinSeconds=300`), leaving out this device (`JellyfinClient.playingSessions`, `RemoteSessions`).
- **Not `controllableByUserId`:** that filter also drops sessions without `SupportsRemoteControl`, which are all of our TV apps until phase 1b. The app filters on `UserId` and `DeviceId` itself. Admin accounts get every user's sessions back; a non-admin one is not checked yet.
- The position runs on from `LastPlaybackCheckIn` while not paused (at most 30 s ahead), so it moves every second between the TV app's reports.
- **TV bar:** the system's `tabViewBottomAccessory(isEnabled:)`, which needs iOS 26.1; on 26.0 there is no bar. When the tab bar collapses, the bar shows only the title. The mini player moves up when the TV bar shows.
- **Now playing screen:** the player's portrait layout with the device's status where the video would be, then `ItemInfoPanel`. Choosing another episode or movie there opens its series page or movie detail; it doesn't play on the phone. When the playback stops, the screen stays with "Stopped on …".
- Checked in the simulator against the real Chromecast session (the simulator's account differs from the TV's, so with the user filter switched off locally for the check): the bar, the screen, the position and the badges, and the switch to the next episode while the screen was open. Not checked yet: the "Stopped on …" state, pause, the LG app, two TVs at once, and the iPhone itself.

### Quality labels with bitrates, and what Auto picked (2026-10-23)

- Levels are named by their bitrate cap, with the resolution after it: "5 Mbit/s · 1080p"; the original shows the file's own bitrate: "Original · 19.9 Mbit/s" (`StreamLevel.name`, `resolution`, `label(sourceBitsPerSecond:)`, `Format.megabits`). Where there is no room, the short name is the resolution or "Original" (`shortName`).
- **Player:** while Auto is active, "Auto · 1080p" sits next to the time, so what Auto picked shows without opening a menu. The gear menu has "Auto · Original" on top and a "Connection · Measured 238.6 Mbit/s" section: what this play measured (kept up to date while the original file streams), else the last measurement on this network.
- **Settings:** the pickers read "Auto, up to 5 Mbit/s · 1080p".
- Built in two sessions at once in the same checkout and merged here. Checked in the simulator: the label, the menu and the settings.

### Local network as its own streaming quality (2026-10-23)

- **Settings → Streaming quality** now has three rows: Local network (default Original), Wi-Fi (default Auto) and Mobile data (default Auto up to 1080p).
- **Local** means the server's IPv4 address falls in the subnet of one of the device's own interfaces (`LocalNetwork`, `getifaddrs`, the same check server discovery uses). It wins over metered: a server in the hotspot's subnet is still local. A VPN tunnel (point-to-point interface) doesn't count, so the home server reached through a VPN on mobile data is Mobile data. A server address that is a host name, not an IP, never counts as local (it would need a DNS lookup); the user's server is `192.168.1.4`.
- Checked in the simulator (the Mac is on the home LAN): "Now on: Local network".

### Buffering, slow-connection hint and messages (2026-10-23)

- **Stall:** when the engine waits for data mid-play (`isBuffering`), a spinner with "Waiting for the connection" shows over the video; with the controls up, the play button turns into the spinner. The mini player shows its spinner too.
- **Buffer length:** the time line reads "0:08 / 24:52 · 4:57 buffered", and the progress line has a lighter band up to there. It is what the engine holds ahead (`clock.bufferedPosition`) plus, for the original file, what our `StreamCache` holds without a gap after the engine's read position, at the file's average bitrate. Updated every second.
- **Buffer on a transcode:** the engine plays a server transcode as remote HLS straight into AVPlayer and reports no buffer on that route (`bufferedPosition` follows the playhead), so the label stayed at 0:00. There the buffer is AVPlayer's loaded range around the play position (`loadedTimeRanges`). Checked in the simulator: White Lotus 3x2 at 720p (server: Transcode, 1280 HEVC) shows 1:18 buffered.
- **Slow-connection hint:** based on the buffer, not on stalls. While playing, a connection that keeps up grows the buffer (or holds it at its cap); one that doesn't lets it run down. When the buffer runs down by 5 s or more over 30 s of playing and is below 60 s, a pill shows for 10 s: "Slow connection · 1080p under the gear plays smoother", or "The connection can't keep up with this file" when nothing lower is offered. A pause, a seek or the end of the file coming into the buffer starts the window anew; at most one hint per 5 minutes. The quality still never changes by itself.
- The first version counted stalls (`isBuffering`, two within a minute or one over 5 s) and hinted almost every play on the home Wi-Fi while the buffer grew ~20 s a second: AVPlayer briefly waits on every start, resume and ±10 s skip, so those counted as stalls (the user, 2026-10-23).
- **Playback errors:** a failed load or an engine error halfway shows a message in the video area with "Try again" (on from the position where it stopped) and, when the original won't play and a transcode would shrink it, "Play via the server · 1440p". The engine's own text goes to the log, not to the user. The mini player shows a warning sign. A player that can't start at all shows an alert.
- **Offline / server unreachable:** with a cached library, Home and Library show a glass banner ("You're offline." or "The server can't be reached right now.", "Updated 2 hours ago"); a tap retries, and it retries by itself when the network comes back. The banner stays during a retry and goes once a sync succeeds.
- Checked in the simulator: the buffer label and band on Friends 10x9, the error screen on Friends 10x8 (no streams). The stall spinner, the hint and the offline banner need a slow or missing connection; to check on the iPhone (Wi-Fi off, or a weak spot).
- In the simulator the player controls sometimes don't show over a 4K software-decoded item (Ted Lasso 1x5); the previous build does the same, so it is not from this change.

### Downloads on hold (2026-10-23)

- M4 (downloads, offline mode, progress sync) is put on hold at the user's request, now the interface and playback are done. Nothing of it is built: no Downloads tab, no download buttons, no "Voor onderweg" row. The paid developer account and the Compact format only matter once M4 is picked up again.

### Home tab, fixed tab bar and own pull-to-refresh (2026-10-23)

- Watch is now **Home** (`house`), Library uses `square.stack`, as in Apple's own media apps.
- The tab bar no longer minimizes on scroll. With two tabs and no bottom accessory it shrank to one lone bubble on the left, which looked broken; Apple's apps only minimize when an accessory (now playing) takes over.
- Player controls hide after 3 s of playing without a touch, also right after the start and after resuming from pause (YouTube and the system player use about 3 s). Before, they only hid after a tap, so a play started without touching stayed covered.
- Home has its own pull-to-refresh (`RefreshableScrollView`): the content runs under the bars, so the system refresh control sat hidden behind the hero. A glass circle in the navigation bar row fades in and turns with the pull, turns accent with a light haptic once far enough, and shows a spinner while the content stays pushed below it (at least 600 ms). Library keeps the system control.

### Search lives in Library (2026-10-23)

- The Search tab is gone; the tab bar has Home (then Watch) and Library, leaving room for a later tab. Search was the library with a text field, so the field now sits at the top of Library.
- Typing narrows the library list itself, so type, genre and sort keep applying; People (from the server) and Episodes come below the titles. Starting a search clears the watch-status filter, because "Not watched" would hide what was already seen.
- Genres moved from tiles on the empty search screen to a Genre chip next to the status chips, a menu with a count per genre. The separate genre screen is gone.

### Streaming quality (2026-10-23)

- **Settings → Streaming quality**, one choice per network (since the same day also Local network, see above): Auto, Auto up to 1440p/1080p/720p, Original, or a fixed 1440p (~10 Mbit/s), 1080p (~5) or 720p (~2.5). Defaults: Wi-Fi Auto, mobile data Auto up to 1080p. A metered network (`NWPath.isExpensive`, so also a personal hotspot) counts as mobile data.
- **Auto picks once, at the start, and keeps it.** A Jellyfin transcode has one variant and a switch restarts ffmpeg, so there is no adaptive switching. It takes the highest level whose bitrate the connection carries with 1.3× headroom, from the warm-up measurement (fresh for 10 minutes, cleared when the network changes) or from three chunks fetched at Play. A level that would not shrink the file plays the original (no transcode for nothing).
- **Player:** a gear menu (Auto, Original and the levels that make sense for the file) plays on at the same position; the choice holds for the rest of the play, next episodes included. The quality never drops by itself; the stall pill that offered one step down was removed on 2026-10-23 at the user's request.
- **Transcode request:** `POST /Items/{id}/PlaybackInfo` with a device profile for HLS fMP4, HEVC and stereo AAC, plus `&MaxWidth=` on the returned `TranscodingUrl`. A transcode carries one audio and at most one subtitle track, so picking another one requests a new transcode at the same position. Text subtitles come as the server's WebVTT rendition; image subtitles are burned in. Injecting the subtitle as an engine sidecar (`externalSubtitles`) showed nothing on the remote-HLS route: AVPlayer only fetched segment 0.
- The stop report carries the server's `PlaySessionId`, which ends the transcode (checked: 0 active encodings after switching back to Original).
- Checked in the simulator against the server: South Park 29x3 (1080p) at 720p → HEVC 1280×720 at 2.4 Mbit/s over QuickSync, `PlayMethod` Transcode; Auto on the LAN goes back to the original; subtitles shown. Still to check on the iPhone: mobile data and HDR content looking right as SDR.

### Player polish after the second round (2026-10-23)

- The movie detail's play button is a large round transparent button (84 pt, thin white ring) instead of the accent capsule.
- The mini player has two sizes, switched with a pinch and kept between plays: 200 pt in the corner, or the full portrait width (minus 16 pt margins). In landscape the large size keeps the portrait width.
- No layer at all behind the player controls any more; the icons carry a soft shadow so they stay readable on light scenes. The round backgrounds of the three transport buttons stay.
- Checked in the simulator: the new button, swipe down, pinch to large and back while playing.

### Mini player, movie detail and IMDb people (2026-10-23)

The user's feedback after the first build on the iPhone.

- **Mini player:** the play now lives in `NowPlaying` (owned by `MainView`), not in the player screen. A swipe down minimizes it to a 16:9 player of 200 pt above the tab bar, bottom right; the video keeps playing, a tap opens the full player again, × ends the play. The engine's surface moves between the two views (`AetherPlayerSurface` binding hands the layer over). "Continue" above the tab bar is hidden while something plays. Reporting and next-episode handling run in `NowPlayingObserver`, which lives as long as the play.
- **PiP back in the app:** when the app comes to the front again, a running Picture in Picture stops, so the video returns to the player or mini player it came from.
- **Movie detail = the player's info:** the backdrop takes the place of the video (16:9 right under the status bar, at most 55% of the height, also in landscape for now) with Play/Continue on it; below it the same `ItemInfoPanel` as in the player, plus the mark-watched button next to IMDb. A movie in a row opens its detail instead of playing. The series page is unchanged.
- **Cast → IMDb:** a tap on a person fetches their `ExternalUrls` and opens the IMDb page (the app via its universal link); without a link it opens an IMDb name search.
- **Controls:** the dark layer over the whole video is gone; only the top and bottom edges darken for the icons.
- Checked in the simulator: detail page, play, swipe down to the mini player while playing, back to full size without a gap in playback, × closes, a cast tap opens imdb.com. PiP returning cannot be checked in the simulator.

### YouTube-style player (2026-10-23)

Designed in Paper first (artboards "Speler portret (film)", "Speler portret (aflevering)", "Speler landscape", "Speler — gebaren en gedrag") and approved by the user.

- **Portrait:** the video sits at the top under the status bar, the info scrolls below it: title, meta line, tech badges from the file, overview, an IMDb button (a universal link, so the IMDb app opens when installed; the user chose IMDb only, not TMDB, Letterboxd or Trakt), episodes, cast, collection and related movies. A tap on an episode or movie plays it in the same player.
- **Controls:** no close button; PiP, AirPlay and tracks top right, ±10 s and play/pause in the middle, time bottom left, full screen bottom right. In portrait the progress line runs along the bottom edge of the video.
- **Full screen:** the button turns the screen to landscape and holds it (`OrientationLock` through an app delegate) until the device is held the same way; turning the phone works as well.
- **Swipe down** on the video (portrait and landscape) shrinks and closes the player; the cover has a clear presentation background so the app shows through while dragging.
- **Episodes:** the one before and the next four, across season ends, from the cached library.
- **Collection:** the library sync now also asks `ProviderIds` and keeps `TmdbCollection` on `Movie`; movies sharing it are shown in release order, titled by the part of their names before the colon ("The Lord of the Rings"). No Jellyfin collections (BoxSets) are needed; the server has none ("Automatically add to collection" is off).
- **Related:** `/Items/{id}/Similar` re-ranked on what a movie really shares: at least two people (cast or crew), scored 2 per person plus 1 per studio, then grouped per collection in release order. For Fellowship this gives the three Hobbit films and drops Ready Player One and The Ministry of Ungentlemanly Warfare, which the server listed first and which share nothing. No plugin needed.
- Double tap to skip ±10 s was left out: it would delay every single tap on the video.
- Checked in the simulator: Fellowship (badges, cast, collection, related), The Pacific 1x2 and 1x3 (episode list, switching), full screen and swipe down in both orientations. Still to check on the iPhone: the drag feels smooth, PiP and AirPlay buttons, rotation lock against the real device orientation.

### Server discovery (2026-10-23)

- Same protocol as Android: "who is JellyfinServer?" over UDP to port 7359, the server replies with `{"Address","Id","Name"}`. Broadcast needs the multicast entitlement, so `ServerDiscovery` sends the question unicast to every host in the subnets of the active IPv4 interfaces (at most a /22), then listens 2 s. Each found server gets a `System/Info/Public` check for its version.
- The sign-in screen lists found servers above the address field; a tap connects. "Search again" when nothing is found.
- Checked in the simulator: finds "home server" (192.168.1.4:8096, 10.11.11) and a tap leads to the Quick Connect code. Still to check on the iPhone: the Local Network permission prompt (the first sweep before "Allow" finds nothing; "Search again" afterwards) and that unicast UDP is allowed without the entitlement.

### M3 player (2026-10-23)

- **Reporting** as on Android: start, progress every 10 s and at once on pause, resume and seek, stop on close or next episode. One serial queue (`PlaybackReporter`); no progress after a stop; stopping in the Outro segment (or the last 30 s without one) marks the item played after the stop report. The position is shown locally at once and the library syncs after the reports are sent. Checked in the simulator against the server: DirectPlay session, pause, saved position 48:40, episode marked played.
- **Segments:** "Skip intro / recap / preview" while one plays, "Next episode · S3 · E2" in the credits; at the end of an episode the next one starts by itself. Checked on The White Lotus 3x1 (intro 0:06–1:44).
- **Start strategy:** AVPlayer only buffers ~4 s ahead and AetherEngine does not expose a longer buffer, so the original file now runs through our own `StreamCache` (2 MB chunks in a sparse part file in Caches) served to the engine by `LocalStreamServer` on 127.0.0.1 with byte ranges. Opening a movie or series warms up the first, second and last chunk (disk spin-up, MKV cues, throughput; the first fetch is left out of the measurement). On Play: connection ≥ 1.3 × the average bitrate starts right away; slower loads `runtime × (1 − T / 1.3B) + 30 s` ahead with a countdown and "Start now" (design "Speler: vooruit laden"). While playing the cache stays up to 5 minutes (at most 1.5 GB) ahead of the read position. The part file is deleted after playback and at launch. "Lower quality" (server transcode) came later; see Streaming quality.
- A deadlock in the first version: waiters on a chunk resumed before the fetching task had stored it, so the prefetch loop spun on the actor and the fetch never finished. The fetch task now stores the chunk itself.
- **PiP** around the engine's AVPlayerLayer (native route only) and an **AirPlay** route button. Neither can be checked in the simulator; to test on the iPhone, as are the subtitle cases from the spike.
- Loopback simulator throughput was 200–250 Mbit/s; the slow path was checked by forcing the peak factor, then set back.

### M2 screens as built (2026-10-23)

- **Tabs:** Kijken, Bibliotheek and Zoeken (search role), the tab bar minimizes on scroll, and the bottom accessory shows "Verder <title>" for the most recent item in progress or next episode. Settings (server, account, library status, timings, engine spike, sign out) sit behind the profile button on Kijken.
- **Kijken** hero runs edge to edge without rounded corners, like the YouTube app (the user's request, also changed in Paper). Below it: Volgende, Nieuw (30 days, grouped per series, "Alles" opens Bibliotheek sorted by newest) and Nog niet begonnen. "Voor onderweg" waits for downloads (M4).
- **Everything is derived from the cached library** (`LibraryIndex`): continue watching, next episode per series, new entries, season progress, watch status. Only the movie tech line, people search and a person's titles ask the server.
- **Marking watched** (movie, episode via long press, whole series) shows at once and is rolled back if the server refuses.
- **Images:** one `ImagePipeline` with a 150 MB memory cache and a 400 MB disk cache; URLs carry the image tag, so cached responses are used without asking the server.
- **Search field:** with `Tab(role: .search)` the field did not move to the bottom on the iOS 27 simulator; it sits under the title, always visible. Recheck on the iPhone.
- **Player:** a plain AetherEngine player (play/pause, ±10 s, scrubber, audio and subtitle menu) that resumes at the saved position. It does not report progress to the server yet, so watch state only changes when another client or a manual mark updates it. Reporting, start strategy, segments and PiP are M3.
- **Language:** `Localizable.xcstrings` (English keys, Dutch translations, plurals for seasons, titles and new episodes) and `Genres.xcstrings`, which also translates the server's English TMDb genres; combined genres such as "Sci-Fi & Fantasy" are split. Overviews stay in the server's metadata language (English).

### M2 scope after the design review (2026-10-23)

The user reviewed the iOS artboards in Paper (Kijken, Bibliotheek, Seriepagina, Filmdetail, Downloads, Speler: vooruit laden).

- **Accent:** the main action of a screen is one filled accent button (Verder, Afspelen, Download), as designed; `design-style.md` follows the designs.
- **Zoeken** was designed afterwards (artboards "Zoeken (leeg)" and "Zoeken (typen)") and approved the same day: recent searches and genre tiles when empty; results grouped as Series, Films, Mensen while typing; the search field at the bottom as in iOS 26. People come from the server, so that part needs a connection. Server genres are English and overlap ("Science Fiction", "Sci-Fi & Fantasy"); the app translates and merges them.
- **Downloads stay out of M2:** no download buttons, no Downloads tab; the bottom accessory only shows "Verder <title>". They arrive with M4.
- **Language:** Dutch and English from the start through the string catalog, following the iPhone's language. The designs are the Dutch text.

### Sign-in and library cache (M1, 2026-10-23)

- **Sign-in:** the user types the server address (`192.168.1.4:8096` is enough; `http://` is added), the app checks it with `/System/Info/Public`, then shows a Quick Connect code and polls every 2 s for up to 10 minutes. The session (server, user, token) is in the Keychain, this device only.
- **Library:** movies, series and episodes in three parallel `/Items` requests (recursive, user data, one image tag per type), mapped to our own `Movie`, `Series` and `Episode`. Every launch shows the cached copy first and then syncs the whole library again: 0.6 s for 28 movies, 23 series and 1335 episodes, so an incremental sync isn't worth it yet.
- **Cache:** one JSON file, `Application Support/library.json` (1.2 MB), excluded from backup, tied to server and user, deleted on sign-out. A 401 signs the user out.
- **Cold start** on the iPhone 18 Pro Max (Debug build): app start to list 67 ms, of which reading the cache 20 ms; the sync after it 545 ms. In the simulator 176 ms and 45 ms. A Release build will only be faster.
- **Offline** (Wi-Fi off): the cached library stays, with the message "The server can't be reached (-1009)". The error code is not meant for the user; to be reworded with the M2 screens.
- `LibraryScreen` is a plain debug list until the M2 designs are approved; the engine spike is in its menu.

### Playback engine: AetherEngine 7.36.0 (2026-10-23)

Spike on the iPhone 18 Pro Max (iOS 27.0.1, Debug build, home LAN), 22 items from the test matrix; the raw run is `Documents/spike-results.jsonl` in the app. AetherEngine remuxes the original file (`static=true`) on the device into HLS for AVPlayer, so the server does no work.

- **21 of 22 play.** Friends 10x8 (no video, no audio) fails to open with a demuxer error and does not crash, as intended.
- **Video:** hardware decode for H.264, HEVC SDR, HDR10, HDR10+, HLG and Dolby Vision P5, P7 (Game of Thrones 8x6, Ready Player One), P8.1 and P8.6, each output in its own format. VC-1 (Blow) decodes in software and plays.
- **Audio:** EAC3 (Atmos) and AAC up to 7.1 are copied. TrueHD and DTS/DTS-HD MA are converted to EAC3; TrueHD 5.1 next to VC-1 is decoded to CoreAudio.
- **Time to first frame** 0.18–1.48 s, seek 0.17–1.91 s; the slow end is the 4K DV P7 and TrueHD files above 90 Mbps. Within the 3 s budget.
- Interstellar (DV P8.1 with HDR10+, 109 Mbps) looked slightly overexposed; solved since (the user, 2026-10-23).
- The library shrank from 2073 to 1363 items between 2026-10-11 and 2026-10-23; it has no M2TS and no VobSub any more, so those rows were dropped.

MPVUI is not needed as a fallback for now. AetherEngine goes behind our own `PlaybackEngine` protocol, pinned to one version.

### Project setup (2026-10-15)

- **SwiftUI, Swift 6, iOS 26 minimum**, one app target for iPhone and iPad. No third-party dependencies yet.
- Bundle id `nl.jellycast.ios`, display name "JellyCast", version 0.1.0 (1).
- Xcode project with folder-synchronized groups, written by hand (no XcodeGen/Tuist): new files need no project edit.
- Dark only (`UIUserInterfaceStyle = Dark`). iPhone: portrait only, except the player, which turns to landscape (`OrientationLock`); iPad: all orientations.
- App Transport Security: `NSAllowsLocalNetworking` so plain HTTP to the LAN server works; `NSLocalNetworkUsageDescription` for the local network prompt.
- **Taken over from the Android app:** the color tokens, the brand (Cast triangle, wordmark) and the splash. The brand is drawn in code (`BrandMark.swift`, a port of the Compose `BrandMark`), and the app icon is rendered from that same code (`scripts/render-app-icon.sh`).
- **Splash:** the system launch screen is a plain `LaunchBackground` color (`#0E0E0F`), then the SwiftUI splash draws the line in 600 ms, fades in the wordmark, holds 250 ms and fades out in 200 ms. A tap skips it. The Android "wait for steady frames" step is left out: iOS delivers regular frames from the first one. Checked in the simulator by recording the launch.
- **Not taken over:** everything TV-specific (D-pad focus, the neon focus border, 10-foot sizes, the 2 GB RAM budget, the Chromecast's frame rate and passthrough work). Touch screens are designed anew.
