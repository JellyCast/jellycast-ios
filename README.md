<h1 align="center">JellyCast for iOS</h1>

<p align="center">
  <b>A Jellyfin client for iPhone and iPad.</b><br>
  The sister app of <a href="../jellycast-android-tv">JellyCast for Android TV</a>: same server, same brand, same priorities.
</p>

---

## Why

JellyCast started on a Chromecast with Google TV, where the existing Jellyfin apps were either too slow or not pretty. The iOS app brings the same idea to the phone and tablet: start watching quickly, play as much as possible without transcoding, and never make you wait for a screen.

Every choice follows one order of priority:

> **Works well > responds instantly > looks good.**

## Status

Early. The project is set up with the JellyCast brand, app icon and splash screen. Next: connecting to a server, signing in (Quick Connect or password), and choosing the playback engine (see [NOTES.md](NOTES.md)).

## Building

You'll need Xcode 27 and a Jellyfin server.

1. Open `JellyCast.xcodeproj`.
2. Under *Signing & Capabilities*, choose your own team.
3. Pick your iPhone or iPad and press Run.

### Trying it without your own server

The Jellyfin project runs a public demo server with freely licensed films. JellyCast signs in with Quick Connect, so you approve the code in a browser:

1. In JellyCast, enter `https://demo.jellyfin.org/stable` as the server address and tap Connect.
2. In a browser, open `https://demo.jellyfin.org/stable` and sign in as `demo` with an empty password.
3. Open the profile icon at the top right → Quick Connect (or go to `https://demo.jellyfin.org/stable/web/#/quickconnect`), enter the code from the app and tap Authorize.

The demo server is not part of JellyCast; it may be offline or reset at times, and it runs a newer Jellyfin version than the server JellyCast is tested on.

## How it's built

Swift 6 and SwiftUI, iOS 26 or later. Playback runs on [AetherEngine](https://github.com/superuser404notfound/AetherEngine), built on FFmpeg; every third-party component and its license is in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). The brand mark is drawn in code (`JellyCast/Core/DesignSystem/BrandMark.swift`) and the app icon is rendered from it with `scripts/render-app-icon.sh`.

| Document | About |
|---|---|
| [CLAUDE.md](CLAUDE.md) | Stack, layout, commands and working agreements |
| [NOTES.md](NOTES.md) | Status, decisions and open questions |
| [docs/remote-play.md](docs/remote-play.md) | Seeing and controlling the TV apps from the iPhone |
| [docs/server.md](docs/server.md) | The Jellyfin server and what the API taught us |
| [.claude/rules/](.claude/rules/) | Product principles, style and code rules |

## Contributing or forking

JellyCast for iOS is a paid app in the App Store, and its source is open to read, change and build.

- **Ideas and improvements are welcome.** Open an issue or a pull request; see [CONTRIBUTING.md](CONTRIBUTING.md). Contributors agree to the [Contributor License Agreement](CLA.md) once, so their work can ship in the App Store version.
- **Forking for your own use is fine.** Build your own version and install it on your own iPhone or iPad, no permission needed.
- **Publishing a copy is not.** An app based on this code may not be offered to others, in the App Store or anywhere else, free or paid.

## Content

JellyCast is a client for your own Jellyfin server. It does not provide, host or index any content. You are responsible for the content on your server and for having the rights to play it.

## License

Source-available under the [PolyForm Shield License 1.0.0](LICENSE): use, change and build it for anything except a product that competes with JellyCast. This is not an open source license.

The name "JellyCast", the logo and the app icon are not covered by the license. Third-party components keep their own licenses; see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

JellyCast is not an official Jellyfin project.
