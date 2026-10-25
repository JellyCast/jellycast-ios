# Third-party notices

JellyCast for iOS includes the components below. Each keeps its own license; the [PolyForm Shield License](LICENSE) of this repository does not apply to them. Versions are the ones pinned in `Package.resolved`.

| Component | Version | License | Source |
|---|---|---|---|
| AetherEngine | 7.36.0 | LGPL-3.0, with an App Store / DRM exception | https://github.com/superuser404notfound/AetherEngine |
| FFmpegBuild (FFmpeg n8.1.3) | 3.7.1 | LGPL-2.1-or-later | https://github.com/superuser404notfound/FFmpegBuild |
| ↳ dav1d 1.5.4 | | BSD-2-Clause | |
| ↳ zimg 3.0.6 | | WTFPL | |
| ↳ libzvbi 0.2.45 | | LGPL-2.0-or-later (`ure.c` MIT) | |
| LibDTSX | 1.0.1 | LGPL-3.0-or-later (built library; repository sources Apache-2.0) | https://github.com/superuser404notfound/LibDTSX |
| LibDovi (libdovi) | 2.1.0 | MIT | https://github.com/superuser404notfound/LibDovi |
| LibTrueHD | 2.3.0 | MIT; includes the `truehd` and `oamd` crates under Apache-2.0 | https://github.com/superuser404notfound/LibTrueHD |
| SMBClient | 0.3.1 | MIT | https://github.com/kishikawakatsumi/SMBClient |

The full license texts are in each component's repository at the version above. LibTrueHD's `NOTICE` and `LICENSE-APACHE` must travel with any copy of its library.

## LGPL components

AetherEngine, FFmpeg, libzvbi and LibDTSX are licensed under the GNU Lesser General Public License. You may change them and use your changed version in this app:

1. Get the source of the component at the version above, from its repository.
2. Point the package reference in `JellyCast.xcodeproj` at your changed version.
3. Build the app from this repository and install it on your own device.

The [license of this repository](LICENSE) allows building and installing your own copy, and does not limit any right the LGPL gives you, including reverse engineering the app to debug such changes.

## Trademarks

Jellyfin is a trademark of the Jellyfin project; JellyCast is not an official Jellyfin project. Dolby, Dolby Vision, Dolby Atmos and Dolby TrueHD are trademarks of Dolby Laboratories. DTS and DTS:X are trademarks of DTS, Inc. This app is not affiliated with or endorsed by them.
