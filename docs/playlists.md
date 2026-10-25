# Plan: lists (playlists)

Date: 2026-10-25. Status: L1 built on 2026-10-25 and checked in the simulator (see `NOTES.md`, "Lists L1"); L2 not started.

## The idea

Make a list of things to watch in a set order, for example "DC Universe": films, and also single episodes or a whole series in between. The list is made and kept on the iPhone (create, add, reorder, remove). Playing it starts on the iPhone or on a TV (Chromecast, C2, CS), and continues with the next item in the list when one ends.

## What the server gives us (checked 2026-10-25, Jellyfin 10.11.11)

Jellyfin playlists do all of this already, so no plugin or own storage is needed.

- `POST /Playlists` with `Name`, `UserId`, `MediaType: "Video"` and `Ids` creates a list. **Films and episodes mix in one list** (tried: a film, an episode, a whole series and another film).
- **Adding a series or season adds its episodes**, in order, at that moment (tried: one series became 15 episodes). Episodes added to the library later do not join the list.
- `GET /Playlists/{id}/Items` returns the list in its own order, with user data (watched, position) and a `PlaylistItemId` per entry (an item can be in a list twice).
- `POST /Playlists/{id}/Items?ids=…` appends, `DELETE /Playlists/{id}/Items?entryIds=…` removes entries, `POST /Playlists/{id}/Items/{playlistItemId}/Move/{newIndex}` reorders, `POST /Playlists/{id}` with `Name` renames, `DELETE /Items/{id}` deletes the list.
- Lists belong to a user; `Users` (with `CanEdit`) and `IsPublic` share them. Lists of all users: `GET /Items?IncludeItemTypes=Playlist&Recursive=true`.
- Move and `GET /Playlists/{id}` answered 400 with the API key (no user behind it); **check them with the app's own user token** in L1.
- There are no playlists on the server yet.
- Not collections (BoxSets): they have no order of their own and the TV apps already show them as "collection".

**Playing a list on a TV** is standard Jellyfin remote play, the route from `remote-play.md` with more than one item:

- `POST /Sessions/{id}/Playing?playCommand=PlayNow&itemIds=a,b,c,…&startIndex=n&startPositionTicks=…` sends the whole queue and where to start.
- The player reports the queue back with `NowPlayingQueue` (item ids with `PlaylistItemId`) and `PlaylistItemId` in its progress reports; the iPhone reads them from `/Sessions`, so the now playing screen can show "DC Universe · 3 of 12" and what comes next.
- **Both TV apps take only the first item today** (`RemoteControlMappers.kt`: "the player has no queue"; `remoteControl.ts` the same), and play the next episode of the series when an item ends. They need a queue.

## How it works

- **A queue in every player** (iOS, Android TV, webOS): a list of item ids plus the current index. When an item ends, the next item in the queue plays instead of the next episode; without a queue the player behaves as now. `NextTrack` / `PreviousTrack` and the next button move through the queue. The countdown at the end ("Next: …") shows the next queue item.
- **Where a list starts:** at the first item that is not fully watched, at its resume position (proposal, see decision 2). "Play from the start" in the list's menu.
- **Long lists:** send the ids from the start index on, at most ~100 (a URL of ~3.5 KB); the player fetches the rest from the playlist when it gets there. Only needed for lists with whole series in them.

## Phases

### L1 — Lists on the iPhone (iOS only)

- Lists screen: all lists of the user with a collage of the first posters, number of items and how far you are ("4 of 12 watched").
- List screen: the items in order (poster, title, for episodes "Series · S1E3", watched mark and progress), **drag to reorder**, swipe to remove, rename and delete in the menu, a big Play / Continue button.
- **Add to list…** as one more action in the long-press drawer (`MediaContextMenu`: films, series and episodes on Home, Library and search), and the same drawer newly on episodes and seasons on the series page. No button or extra menu on the pages. A sheet with the lists (a check where the item already is) and "New list…"; new items go at the bottom.
- Lists open from the Library filter menu, at the bottom: "Lists". Nothing on Home or at the top of Library.
- Playing on the iPhone with a queue in `PlayerSession`.
- Design in Paper, page "iOS", section "10 · Voorstel — lijsten (L1)": Lists, the DC Universe list, the add-to-list sheet, and an artboard with the two entry points and the behaviour. Approved by the user on 2026-10-25.
- **Done when:** the DC list can be made from the iPhone with films and an episode in between, reordered, and played on the iPhone from film to film.

### L2 — Play a list on a TV

- **Android TV, then webOS:** read `ItemIds` and `StartIndex` from `Play`, keep the queue in the player, play the next queue item at the end, report `NowPlayingQueue`.
- **iOS:** "Play on…" on the list screen (the existing sheet, including waking the Chromecast with a `jellycast://play` link that carries the list id), and the now playing screen shows the list and its next items; tapping one plays it on the TV.
- **Done when:** a list started on the iPhone plays on the Chromecast and the C2, goes on to the next film by itself, and the iPhone shows where in the list the TV is.

### Later

- Lists on the TV apps themselves (a row "Lists" on Home), to start one with the remote.
- Sharing a list with another user.

## Decisions (taken with the user, 2026-10-25)

1. **Where lists live:** out of the way, because watching a set of titles in a row is rare; normally you watch one series or film. No tab, no section on Library, no row on Home. Lists open from the Library filter menu ("Lists"), and "Add to list…" is an action in the long-press drawer, not a button. The same holds for the TV apps later.
2. **Where Play starts:** at the first item not fully watched, at its resume position; "Play from the start" in the list's menu.
3. **Whole series in a list:** the episodes as they are at that moment (server behaviour); each can then be moved or removed on its own.
4. **Order of building:** L1 first and try it on the iPhone, then L2.
