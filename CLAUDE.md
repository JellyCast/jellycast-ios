# JellyCast for iOS

Own Jellyfin client for iPhone and iPad, bundle id `nl.jellycast.ios`, SwiftUI app `JellyCastApp`.
Sister project of the Android TV app in `../jellycast-android-tv` (Chromecast with Google TV). Same server, same brand, same priorities; a different device, so the screens are designed anew for touch.
Target devices: the user's iPhone 18 Pro Max (iOS 27) and iPad. Personal use only, installed from Xcode with the free personal team.

## Documents

- `NOTES.md`: status, what is not built yet, decisions, open questions and what was found on the devices. Newest first. Keep it up to date.
- `docs/remote-play.md`: how the iPhone sees, controls and starts playback on the TV apps, and how waking the TVs works.
- `docs/server.md`: the Jellyfin server, the library profile and what the Android app learned about the API. Read it before any network or playback work.
- `README.md`: public description of the app.
- `../jellycast-android-tv/`: reference implementation. Its `NOTES.md`, `docs/research/` and `.claude/rules/` hold the reasoning behind most choices; adopt what applies, decide anew what is TV-specific.

## Rule files (`.claude/rules/`)

- `product-principles.md`: why the app exists and the priority works well > responds instantly > looks good. Overrides the other rules.
- `design-style.md`: color tokens, typography, brand mark, app icon and splash.
- `code-language.md`: everything in English, when a comment is allowed, Swift style.
- Keep every rule file and this file under 100 lines. Split by topic when one grows longer.

## Stack

- Swift 6, SwiftUI, iOS 26 minimum, iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`). No Mac Catalyst, no visionOS.
- Default actor isolation is `MainActor`; mark background work explicitly (`nonisolated`, `@concurrent`).
- The Xcode project uses folder-synchronized groups: a new file in `JellyCast/` is part of the target automatically, no `project.pbxproj` edit needed. Only `JellyCast/Info.plist` is excluded (it is the target's Info.plist, merged with the generated keys).
- One third-party dependency: AetherEngine (playback, pinned; see `NOTES.md`). Add another only when it clearly adds something and record why in `NOTES.md`.

## Project layout

```
JellyCast/
  App/                 # JellyCastApp, RootView, MainView (tabs), AppNavigation (tab, paths, playing)
  Core/DesignSystem/   # colors, brand, Components (AccentButton, glass buttons, headers), Format
  Core/Images/         # ImagePipeline (memory + disk cache), RemoteImage
  Core/Jellyfin/       # JellyfinClient (nonisolated, one server), JellyfinItem (server DTO)
  Core/Session/        # Session in the Keychain, device id
  Core/Library/        # models, LibraryStore (cache first, then sync), LibraryIndex (derived lists), Genres
  Core/Playback/       # PlaybackReporter, StreamCache + LocalStreamServer (original file via loopback)
  Feature/<name>/      # one folder per screen: Home, Library (with search), Series, Movie, Player, Settings ...
  Resources/           # Assets, Localizable.xcstrings (en + nl), Genres.xcstrings
  Info.plist           # launch screen and App Transport Security (local network)
scripts/               # render-app-icon.sh
```

## Working agreements

- Everything in the repository is English: code, comments, docs, commit messages. Talk to the user in Dutch. User-facing text goes through the string catalog once there is more than one language.
- Build and check every change in the simulator (screenshots via the iOS Simulator tool); playback and performance always on the real iPhone or iPad.
- Look versions up, never guess them; stable versions only.
- No secrets in code or git: the server address and account are entered in the app; the token goes in the Keychain.
- Small commits per step. Write what you discover on a device in `NOTES.md`.
- The brand mark is drawn in code (`BrandMark.swift`). After changing it, run `scripts/render-app-icon.sh` so the app icon matches.

## Commands

```bash
# Build and run in the simulator
xcodebuild -project JellyCast.xcodeproj -scheme JellyCast \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/DerivedData build
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/JellyCast.app
xcrun simctl launch booted nl.jellycast.ios

# Build for and install on a physical device (free personal team; the profile lasts 7 days)
xcrun devicectl list devices
xcodebuild -project JellyCast.xcodeproj -scheme JellyCast -destination 'id=<udid>' \
  -derivedDataPath build/DerivedData -allowProvisioningUpdates build
xcrun devicectl device install app --device <udid> build/DerivedData/Build/Products/Debug-iphoneos/JellyCast.app
xcrun devicectl device process launch --device <udid> nl.jellycast.ios

scripts/render-app-icon.sh   # app icon from BrandMark.swift
```
