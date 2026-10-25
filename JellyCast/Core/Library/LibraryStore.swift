import Foundation
import OSLog

enum ServerProblem {
    case offline
    case unreachable
}

/// Owns the library for the signed-in user: shows the cached copy first, then refreshes it.
@Observable
final class LibraryStore {
    enum SyncState: Equatable {
        case idle
        case syncing
        case failed(String)
    }

    private(set) var snapshot: LibrarySnapshot? {
        didSet { index = snapshot.map(LibraryIndex.init) }
    }
    private(set) var index: LibraryIndex?
    private(set) var syncState: SyncState = .idle
    /// Why the last refresh failed; it stays while a retry runs and clears once one succeeds.
    private(set) var syncFailure: String?
    private(set) var cacheLoadDuration: Duration?
    private(set) var lastSyncDuration: Duration?
    private(set) var isSessionExpired = false
    /// The server did not answer the quick check on opening the app; cleared once it does or the
    /// user dismisses it.
    private(set) var serverProblem: ServerProblem?
    /// The last server check failed to reach it; unlike `serverProblem` this stays until a check
    /// succeeds. Offline, only downloads can be opened.
    private(set) var isServerUnreachable = false

    let session: Session
    let reporter: PlaybackReporter

    private static let logger = Logger(subsystem: "nl.jellycast.ios", category: "library")
    /// Short, so a server that is down is reported before the user taps around; the library
    /// sync itself waits much longer.
    private static let serverCheckTimeoutSeconds = 5.0

    init(session: Session, snapshot: LibrarySnapshot? = nil) {
        self.session = session
        self.snapshot = snapshot
        reporter = PlaybackReporter(client: session.client, userID: session.userID)
        index = snapshot.map(LibraryIndex.init)
    }

    func start() async {
        Task { await UserLanguages.shared.load(client: session.client) }
        if snapshot == nil {
            let started = ContinuousClock.now
            snapshot = await LibraryCache.load(serverID: session.serverID, userID: session.userID)
                .map(Self.applyingOfflineProgress(to:))
            cacheLoadDuration = .now - started
            Self.logger.info("Cache loaded in \(self.cacheLoadDuration?.formatted() ?? "-")")
        }
        await refresh()
    }

    func refresh() async {
        guard syncState != .syncing else { return }
        syncState = .syncing
        let started = ContinuousClock.now
        do {
            let fresh = try await Self.fetch(session: session)
            snapshot = Self.applyingOfflineProgress(to: fresh)
            lastSyncDuration = .now - started
            syncState = .idle
            syncFailure = nil
            let duration = lastSyncDuration?.formatted() ?? "-"
            Self.logger.info("Synced \(fresh.episodes.count) episodes in \(duration)")
            try await LibraryCache.save(fresh)
        } catch is CancellationError {
            syncState = .idle
        } catch JellyfinError.unauthorized {
            isSessionExpired = true
            syncState = .failed(JellyfinError.unauthorized.localizedDescription)
        } catch {
            syncState = .failed(error.localizedDescription)
            syncFailure = error.localizedDescription
        }
    }

    /// Asks the server for its public info; only a failure to reach it counts, the sync reports
    /// the rest. Without `reportsProblem` only the reachability changes, no alert.
    @discardableResult
    func checkServer(reportsProblem: Bool = true) async -> ServerProblem? {
        #if DEBUG
        // `-simulateServerUnreachable YES` tries offline mode in the simulator.
        if UserDefaults.standard.bool(forKey: "simulateServerUnreachable") {
            isServerUnreachable = true
            if reportsProblem { serverProblem = .unreachable }
            return .unreachable
        }
        #endif
        do {
            _ = try await session.client.publicInfo(timeout: Self.serverCheckTimeoutSeconds)
            serverProblem = nil
            isServerUnreachable = false
            Task { await sendOfflineProgress() }
        } catch let error as JellyfinError {
            if case .unreachable(let reason) = error {
                isServerUnreachable = true
                let problem: ServerProblem = reason.code == .notConnectedToInternet ? .offline : .unreachable
                if reportsProblem { serverProblem = problem }
                return problem
            }
        } catch {}
        return nil
    }

    /// Positions watched in downloads without the server; the library is reloaded when any changed.
    func sendOfflineProgress() async {
        guard !isServerUnreachable, await OfflineProgress.shared.send(client: session.client, userID: session.userID) else { return }
        await refresh()
    }

    func report(_ problem: ServerProblem) {
        serverProblem = problem
    }

    func dismissServerProblem() {
        serverProblem = nil
    }

    /// Marks a movie, episode or whole series as watched or not; shown at once, undone on failure.
    func setPlayed(_ played: Bool, itemID: String) async {
        guard let before = snapshot else { return }
        snapshot = Self.applying(played: played, itemID: itemID, to: before)
        do {
            try await session.client.setPlayed(played, itemID: itemID, userID: session.userID)
        } catch {
            snapshot = before
            syncState = .failed(error.localizedDescription)
        }
    }

    /// Shows where playback stopped before the server's copy comes back with the next sync.
    func recordPlayback(itemID: String, positionTicks: Int64, finished: Bool) {
        guard var updated = snapshot else { return }
        func update(_ watch: inout WatchState) {
            watch.lastPlayed = .now
            watch.played = finished || watch.played
            watch.positionTicks = finished ? 0 : positionTicks
        }
        for position in updated.movies.indices where updated.movies[position].id == itemID {
            update(&updated.movies[position].watch)
        }
        for position in updated.episodes.indices where updated.episodes[position].id == itemID {
            update(&updated.episodes[position].watch)
        }
        snapshot = updated
    }

    /// Positions the server doesn't have yet, so the library shows where a download was left.
    private static func applyingOfflineProgress(to snapshot: LibrarySnapshot) -> LibrarySnapshot {
        let pending = OfflineProgress.shared.pending
        guard !pending.isEmpty else { return snapshot }
        var updated = snapshot
        func apply(_ watch: inout WatchState, _ position: OfflinePosition) {
            if let lastPlayed = watch.lastPlayed, lastPlayed >= position.watchedAt { return }
            watch.lastPlayed = position.watchedAt
            watch.played = position.played || watch.played
            watch.positionTicks = position.positionTicks
        }
        for index in updated.movies.indices {
            if let position = pending[updated.movies[index].id] { apply(&updated.movies[index].watch, position) }
        }
        for index in updated.episodes.indices {
            if let position = pending[updated.episodes[index].id] { apply(&updated.episodes[index].watch, position) }
        }
        return updated
    }

    private static func applying(played: Bool, itemID: String, to snapshot: LibrarySnapshot) -> LibrarySnapshot {
        var updated = snapshot
        func mark(_ watch: inout WatchState) {
            watch.played = played
            watch.positionTicks = 0
            if played { watch.lastPlayed = .now }
        }
        for index in updated.movies.indices where updated.movies[index].id == itemID {
            mark(&updated.movies[index].watch)
        }
        for index in updated.episodes.indices
        where updated.episodes[index].id == itemID || updated.episodes[index].seriesID == itemID {
            mark(&updated.episodes[index].watch)
        }
        return updated
    }

    @concurrent
    private static func fetch(session: Session) async throws -> LibrarySnapshot {
        let client = session.client
        async let movies = client.items(type: "Movie", userID: session.userID)
        async let series = client.items(type: "Series", userID: session.userID)
        async let episodes = client.items(type: "Episode", userID: session.userID)
        return try await LibrarySnapshot(
            formatVersion: LibrarySnapshot.formatVersion,
            serverID: session.serverID,
            userID: session.userID,
            syncedAt: Date(),
            movies: movies.map(Movie.init),
            series: series.map(Series.init),
            episodes: episodes.compactMap(Episode.init)
        )
    }
}
