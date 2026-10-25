# Language, comments and Swift style

Everything in the repository is English: code, identifiers, test names, log messages, comments, docs, rules, commit messages. Only user-facing text is translated, through the string catalog. Talk to the user in Dutch.

## Comments

- Code explains itself through names and structure. If a block needs a comment to be understood, rename, extract a function, or introduce a named constant or type.
- A comment is allowed only for a *why* the code cannot express: a platform quirk, a server quirk, a non-obvious constraint. One or two short lines.
- No comments that restate a name, repeat the design spec, reference rule files or Paper, or record history (dates, measurements, "used to be"). History goes in the commit message or `NOTES.md`.
- `///` doc comments only where a contract is genuinely non-obvious. No commented-out code.

## Readable code

- Functions do one thing; a view body or function longer than ~60 lines is a candidate to split into smaller views.
- Files longer than ~400 lines are split by responsibility.
- Magic numbers get a named constant; units go in the name (`positionTicks`, `markSize`).
- 4 spaces, lines up to ~100 characters, trailing commas in multi-line collection literals.

## Swift and SwiftUI

- Swift 6 language mode with strict concurrency. The default actor isolation is `MainActor`; network and parsing code is `nonisolated` or runs in an actor.
- `async`/`await` and structured concurrency; no completion handlers, no Combine for new code. Start work in `.task { }` so it cancels with the view.
- State: `@State` for view-local state, `@Observable` classes for screen models. No `ObservableObject`/`@Published` in new code.
- Views are small and take values plus closures; a screen model owns loading and errors.
- No force unwraps (`!`) or `try!` outside tests and previews. Never swallow `CancellationError`.
- Never log the access token or a stream URL containing `api_key`.
- Every view in `Core/DesignSystem` and every screen has a `#Preview` with fixed data; previews never touch the network.

## Glossary

Use the same English terms as the Android app (`../jellycast-android-tv/.claude/rules/code-language.md` → Glossary), e.g. Continue watching, New, Not started, series page, movie detail, episode/season, watched/in progress, tech line, jump pill, weld spark, skeleton, fallback, transcode, passthrough.
