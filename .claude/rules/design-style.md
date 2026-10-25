# Design: color, type and brand

Shared with the Android TV app (`../jellycast-android-tv/.claude/rules/design-style.md`), which has the history of each choice. Tokens live in code in `JellyCast/Core/DesignSystem/JellyCastColors.swift`. Paper file "JellyCast" (https://app.paper.design/file/01M4EKYVQ2AVZYWF1VAX97EAM0), pages "Logo & stijl", "Android TV" and "iOS"; artboard names are Dutch.

## Color

Dark theme only. Background near-black (no pure `#000`), text off-white. The accent fills at most one button per screen: its main action (Verder, Afspelen, Download), with `onAccent` text.

| Token | Value | Use |
|---|---|---|
| `background` | `#0E0E0F` | background; also the launch screen (`LaunchBackground` asset) |
| `surface` | `#1A1A1C` | skeleton, placeholders |
| `rail` | `#2A2A2E` | lines, progress track, inactive button |
| `text` | `#ECE9E4` | primary text |
| `textMuted` | `#A3A09A` | secondary text |
| `neonBlue` · `neonWhite` · `neonPurple` · `neonPink` | `#7FC8FF` · `#F2F6FF` · `#9B6BFF` · `#FF6EC7` | the brand line and, sparingly, selection |
| `progressStart` · `progressMid` · `progressEnd` | `#8FB8D8` · `#9A88D0` · `#C584B0` | progress: calmer than the neon |
| `accent` | `#B9A6F2` | the one main button per screen, check mark, "Cast" in the wordmark, tint (`AccentColor` asset) |
| `onAccent` | `#1A1206` | text and icon on the accent |
| `primaryContainer` | `#16161B` | primary button surface |

- Contrast text/background ≥ 4.5:1, also over a backdrop (use a scrim).

## Typography

- The system font (SF Pro): bold for titles, regular/medium for labels, light for the player. Use Dynamic Type text styles (`.title`, `.headline`, `.body`, …), not fixed sizes, except in the brand.
- Descriptions on overviews at most 3 lines.

## Brand

- **Mark: the Cast triangle.** The Jellyfin triangle upright as one neon line (7 on 200, gradient light blue → white → purple → pink from top left to bottom right), inside a dot with two arcs (the "Cast"), and on the right edge the weld spark with a 37-unit tail. Glow only as two wider translucent strokes (6% and 13%), no blur. Drawn in code: `BrandMark.swift` (a port of the Compose `BrandMark`), never as a PNG in the app.
- **Wordmark:** "Jelly" bold in `text`, directly followed by "Cast" light in `accent`, tracking −2%. `BrandWordmark`.
- **App icon:** the mark on `background`, the triangle as wide as in the Paper artboard "Icoon — B (512)". Rendered from `BrandMark.swift` by `scripts/render-app-icon.sh` into `AppIcon.appiconset` (1024 px, one variant). Re-render after every change to the mark.

## Splash

- The system launch screen is only the `LaunchBackground` color, so the hand-over to the app is invisible.
- Then `BrandSplash`: the mark (132 pt) with the wordmark 28 pt below it, centered. The line draws itself in 600 ms (ease in-out) led by the weld spark; the signal fades in over the last 40% of the line; the wordmark fades in from 500 ms over 250 ms; after a 250 ms hold the splash fades out in 200 ms. A tap skips it. Once per launch.

## Shapes and motion

- Cards: corner radius 8 pt. Card ratios 2:3 (poster) and 16:9 (episode, continue watching).
- Animate opacity, scale and position; avoid animating layout in scrolling lists. Transitions ≤ 250 ms.
- No blur on scrolling content, no shadow per card, no autoplaying trailers or parallax. The system's own materials (sheets, navigation bars) are fine.
