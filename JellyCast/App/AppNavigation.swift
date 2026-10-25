import Foundation

enum AppTab: Hashable {
    case home, library, downloads
}

enum Route: Hashable {
    case series(id: String)
    case movie(id: String)
    case person(PersonResult)
    case downloadedSeries(id: String)
    case lists
    case list(id: String)
}

/// What "Add to list…" adds: one item, or the episodes of a season.
struct AddToListRequest: Identifiable, Hashable {
    let title: String
    let itemIDs: [String]

    var id: [String] { itemIDs }
}

/// Which tab is open, the navigation path per tab, and what is playing.
@Observable
final class AppNavigation {
    var tab = AppTab.home
    var homePath: [Route] = []
    var libraryPath: [Route] = []
    var downloadsPath: [Route] = []
    /// Set by any screen to play something; `MainView` hands it to `NowPlaying`.
    var playRequest: Playable?
    /// The tracks a TV played, for a play that continues here.
    var playStreams: StreamSelection?
    /// The list the requested item starts, so the player goes on with the next item.
    var playQueue: PlayQueue?
    var addToListRequest: AddToListRequest?
    var showsSettings = false
    var librarySortRequest: LibrarySort?

    func open(_ route: Route) {
        switch tab {
        case .home: homePath.append(route)
        case .library: libraryPath.append(route)
        case .downloads: downloadsPath.append(route)
        }
    }

    func goBack() {
        switch tab {
        case .home: _ = homePath.popLast()
        case .library: _ = libraryPath.popLast()
        case .downloads: _ = downloadsPath.popLast()
        }
    }

    func play(_ playable: Playable, streams: StreamSelection? = nil) {
        playStreams = streams
        playQueue = nil
        playRequest = playable
    }

    func play(_ queue: PlayQueue) {
        guard let current = queue.current else { return }
        playStreams = nil
        playQueue = queue
        playRequest = current
    }

    func addToList(_ title: String, itemIDs: [String]) {
        addToListRequest = AddToListRequest(title: title, itemIDs: itemIDs)
    }

    func showNewInLibrary() {
        librarySortRequest = .newest
        tab = .library
    }
}
