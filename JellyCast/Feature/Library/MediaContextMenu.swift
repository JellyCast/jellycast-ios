import SwiftUI

/// What a long press acts on: a movie, a whole series or one episode.
enum MediaTarget: Hashable {
    case movie(Movie)
    case series(Series)
    case episode(Episode)

    init(_ playable: Playable) {
        switch playable {
        case .movie(let movie): self = .movie(movie)
        case .episode(let episode): self = .episode(episode)
        }
    }

    init(_ entry: LibraryEntry) {
        switch entry.item {
        case .movie(let movie): self = .movie(movie)
        case .series(let series): self = .series(series)
        }
    }

    var id: String {
        switch self {
        case .movie(let movie): movie.id
        case .series(let series): series.id
        case .episode(let episode): episode.id
        }
    }
}

extension View {
    /// The drawer a long press opens to manage an item from anywhere it shows: play, play on a
    /// TV, watched or not, download, and go to its page.
    func mediaContextMenu(_ target: MediaTarget, index: LibraryIndex?) -> some View {
        modifier(MediaContextMenu(target: target, index: index))
    }
}

private struct MediaContextMenu: ViewModifier {
    let target: MediaTarget
    let index: LibraryIndex?

    @Environment(AppNavigation.self) private var navigation
    @Environment(LibraryStore.self) private var store: LibraryStore?
    @Environment(RemoteSessions.self) private var remote: RemoteSessions?
    @Environment(\.isOffline) private var isOffline
    @Environment(\.openURL) private var openURL
    @State private var sheet: Sheet?

    private enum Sheet: Identifiable {
        case download(Playable)
        case playOn(Playable)

        var id: String {
            switch self {
            case .download(let playable): "download-\(playable.id)"
            case .playOn(let playable): "playOn-\(playable.id)"
            }
        }
    }

    private var downloads: DownloadStore { .shared }

    func body(content: Content) -> some View {
        content
            .actionDrawer(header, actions: actions)
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .download(let playable):
                    DownloadSheet(playable: playable)
                case .playOn(let playable):
                    if let remote {
                        PlayOnSheet(playable: playable, remote: remote) { navigation.play(playable) }
                    }
                }
            }
    }

    private var actions: [DrawerAction] {
        var actions: [DrawerAction] = []
        if let playable { actions += playActions(playable) }
        if store != nil, !isOffline { actions += WatchedActions.make(status: watchStatus, setPlayed: setPlayed) }
        if let downloadable { actions += downloadActions(downloadable) }
        if !isOffline { actions.append(addToListAction) }
        actions += pageActions
        return actions
    }

    private func playActions(_ playable: Playable) -> [DrawerAction] {
        var actions = [
            DrawerAction(title: playTitle(playable), systemImage: "play.fill", isAccented: true) {
                navigation.play(playable)
            },
        ]
        if playable.watch.isInProgress {
            actions.append(DrawerAction(
                title: String(localized: "Play from the beginning"), systemImage: "arrow.counterclockwise"
            ) { navigation.play(playable.fromStart) })
        }
        if remote != nil {
            actions.append(DrawerAction(title: String(localized: "Play on…"), systemImage: "tv") {
                sheet = .playOn(playable)
            })
        }
        return actions
    }

    private func downloadActions(_ playable: Playable) -> [DrawerAction] {
        if let download = downloads.download(for: playable.id) {
            let title = download.status == .done
                ? String(localized: "Remove download") : String(localized: "Cancel download")
            return [DrawerAction(title: title, systemImage: "trash") { downloads.remove(download.id) }]
        }
        guard downloads.canReachServer else { return [] }
        return [DrawerAction(title: String(localized: "Download…"), systemImage: "arrow.down.circle") {
            sheet = .download(playable)
        }]
    }

    private var addToListAction: DrawerAction {
        DrawerAction(title: String(localized: "Add to list…"), systemImage: "text.badge.plus") {
            navigation.addToList(listTitle, itemIDs: [target.id])
        }
    }

    private var listTitle: String {
        switch target {
        case .movie(let movie): movie.name
        case .series(let series): series.name
        case .episode(let episode): Format.joined([episode.seriesName, Format.seasonEpisode(episode)])
        }
    }

    private var pageActions: [DrawerAction] {
        var actions: [DrawerAction] = []
        switch target {
        case .movie(let movie):
            actions.append(DrawerAction(title: String(localized: "Go to movie"), systemImage: "film") {
                navigation.open(.movie(id: movie.id))
            })
        case .series(let series):
            actions.append(DrawerAction(title: String(localized: "Go to series"), systemImage: "rectangle.stack") {
                navigation.open(.series(id: series.id))
            })
        case .episode(let episode):
            actions.append(DrawerAction(title: String(localized: "Go to series"), systemImage: "rectangle.stack") {
                navigation.open(.series(id: episode.seriesID))
            })
        }
        let source = RatingSettings.shared.source
        if let url = source.url(of: externalTitle) {
            actions.append(DrawerAction(
                title: String(localized: "Open on \(source.title)"), systemImage: "arrow.up.right.square"
            ) { openURL(url) })
        }
        return actions
    }

    private var header: DrawerHeader {
        switch target {
        case .movie(let movie):
            DrawerHeader(
                title: movie.name,
                subtitle: Format.joined([String(localized: "Movie"), movie.year.map(String.init)]),
                image: movie.poster
            )
        case .series(let series):
            DrawerHeader(
                title: series.name,
                subtitle: Format.joined([
                    String(localized: "type.series", defaultValue: "Series"), series.year.map(String.init),
                ]),
                image: series.poster
            )
        case .episode(let episode):
            DrawerHeader(
                title: episode.seriesName,
                subtitle: Format.joined([Format.seasonEpisode(episode), episode.name]),
                image: episode.still ?? episode.seriesBackdrop,
                imageType: episode.still == nil ? .backdrop : .primary,
                isWide: true
            )
        }
    }

    /// For a series: the episode it continues with.
    private var playable: Playable? {
        switch target {
        case .movie(let movie): current(.movie(movie))
        case .episode(let episode): current(.episode(episode))
        case .series(let series): index?.progress(of: series.id)?.next.map(Playable.episode)
        }
    }

    private var downloadable: Playable? {
        if case .series = target { return nil }
        return playable
    }

    /// The card may hold an older copy; the index has what was marked since.
    private func current(_ playable: Playable) -> Playable {
        index?.playable(id: playable.id) ?? playable
    }

    private var watchStatus: WatchStatus {
        switch target {
        case .series(let series): index?.progress(of: series.id)?.status ?? .notStarted
        default: playable.map { WatchedActions.status(of: $0.watch) } ?? .notStarted
        }
    }

    private var externalTitle: ExternalTitle {
        switch target {
        case .movie(let movie): ExternalTitle(movie)
        case .series(let series): ExternalTitle(series)
        case .episode(let episode): ExternalTitle(episode, series: index?.seriesByID[episode.seriesID])
        }
    }

    private func playTitle(_ playable: Playable) -> String {
        if playable.watch.isInProgress { return String(localized: "Continue") }
        if case .series = target, case .episode(let episode) = playable {
            return String(localized: "Play \(Format.seasonEpisode(episode))")
        }
        return String(localized: "Play")
    }

    private func setPlayed(_ played: Bool) {
        guard let store else { return }
        Task { await store.setPlayed(played, itemID: target.id) }
    }
}

/// Mark as watched while not fully watched, mark as not watched once watched or begun:
/// something in progress gets both.
enum WatchedActions {
    static func status(of watch: WatchState) -> WatchStatus {
        if watch.played { return .watched }
        return watch.isInProgress ? .inProgress : .notStarted
    }

    static func make(status: WatchStatus, setPlayed: @escaping (Bool) -> Void) -> [DrawerAction] {
        var actions: [DrawerAction] = []
        if status != .watched {
            actions.append(DrawerAction(
                title: String(localized: "Mark as watched"), systemImage: "checkmark.circle"
            ) { setPlayed(true) })
        }
        if status != .notStarted {
            actions.append(DrawerAction(
                title: String(localized: "Mark as not watched"), systemImage: "circle"
            ) { setPlayed(false) })
        }
        return actions
    }
}
