import Foundation

nonisolated enum Ticks {
    static let perSecond: Int64 = 10_000_000

    static func seconds(_ ticks: Int64) -> Double { Double(ticks) / Double(perSecond) }
}

nonisolated enum WatchStatus: Sendable, Hashable {
    case notStarted, inProgress, watched
}

/// Something that can be played: a movie or an episode.
nonisolated enum Playable: Codable, Sendable, Hashable, Identifiable {
    case movie(Movie)
    case episode(Episode)

    var id: String {
        switch self {
        case .movie(let movie): movie.id
        case .episode(let episode): episode.id
        }
    }

    var name: String {
        switch self {
        case .movie(let movie): movie.name
        case .episode(let episode): episode.name
        }
    }

    var watch: WatchState {
        switch self {
        case .movie(let movie): movie.watch
        case .episode(let episode): episode.watch
        }
    }

    var runtimeTicks: Int64? {
        switch self {
        case .movie(let movie): movie.runtimeTicks
        case .episode(let episode): episode.runtimeTicks
        }
    }

    var remainingTicks: Int64? {
        runtimeTicks.map { max(0, $0 - watch.positionTicks) }
    }

    var progress: Double? {
        guard watch.isInProgress, let runtime = runtimeTicks, runtime > 0 else { return nil }
        return min(1, Double(watch.positionTicks) / Double(runtime))
    }

    var fromStart: Playable {
        switch self {
        case .movie(var movie):
            movie.watch.positionTicks = 0
            return .movie(movie)
        case .episode(var episode):
            episode.watch.positionTicks = 0
            return .episode(episode)
        }
    }
}

nonisolated struct SeasonSummary: Sendable, Hashable, Identifiable {
    let number: Int
    let episodeCount: Int
    let watchedCount: Int

    var id: Int { number }
    var isWatched: Bool { episodeCount > 0 && watchedCount == episodeCount }
}

nonisolated struct SeriesProgress: Sendable, Hashable {
    let episodes: [Episode]
    let seasons: [SeasonSummary]
    let watchedCount: Int
    let lastTouched: Date?
    /// The episode in progress, or the first unwatched one after the last one watched.
    let next: Episode?

    var status: WatchStatus {
        if !episodes.isEmpty, watchedCount == episodes.count { return .watched }
        if watchedCount > 0 || episodes.contains(where: \.watch.isInProgress) { return .inProgress }
        return .notStarted
    }
}

nonisolated enum NewEntry: Sendable, Hashable, Identifiable {
    case series(Series, newEpisodeCount: Int, isNewSeason: Bool)
    case movie(Movie)

    var id: String {
        switch self {
        case .series(let series, _, _): series.id
        case .movie(let movie): movie.id
        }
    }
}

/// Lookups and derived lists over one snapshot, computed once per snapshot.
nonisolated struct LibraryIndex: Sendable {
    let snapshot: LibrarySnapshot
    let moviesByID: [String: Movie]
    let seriesByID: [String: Series]
    let episodesByID: [String: Episode]
    let progressBySeries: [String: SeriesProgress]

    private static let newWindowDays = 30

    init(_ snapshot: LibrarySnapshot) {
        self.snapshot = snapshot
        moviesByID = Dictionary(snapshot.movies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        seriesByID = Dictionary(snapshot.series.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        episodesByID = Dictionary(snapshot.episodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        progressBySeries = Dictionary(grouping: snapshot.episodes, by: \.seriesID)
            .mapValues(Self.progress(of:))
    }

    func progress(of seriesID: String) -> SeriesProgress? { progressBySeries[seriesID] }

    func playable(id: String) -> Playable? {
        if let movie = moviesByID[id] { return .movie(movie) }
        return episodesByID[id].map(Playable.episode)
    }

    /// The other movies of the same TMDb collection, in release order.
    func collection(of movie: Movie) -> [Movie] {
        guard let collectionID = movie.collectionID else { return [] }
        return snapshot.movies
            .filter { $0.collectionID == collectionID && $0.id != movie.id }
            .sorted { ($0.year ?? 0) < ($1.year ?? 0) }
    }

    func status(of movie: Movie) -> WatchStatus {
        if movie.watch.played { return .watched }
        return movie.watch.isInProgress ? .inProgress : .notStarted
    }

    func status(of series: Series) -> WatchStatus {
        progressBySeries[series.id]?.status ?? .notStarted
    }

    /// Movies and episodes in progress, plus the next episode of every series being watched,
    /// most recently touched first. A next episode added after the series was last watched
    /// counts from when it was added, so a new episode comes first.
    var continueWatching: [Playable] {
        let movies = snapshot.movies.filter(\.watch.isInProgress).map { (Playable.movie($0), $0.watch.lastPlayed) }
        let episodes = progressBySeries.values.compactMap { progress -> (Playable, Date?)? in
            guard let next = progress.next, let lastTouched = progress.lastTouched else { return nil }
            return (.episode(next), max(lastTouched, next.dateAdded ?? .distantPast))
        }
        return (movies + episodes)
            .sorted { ($0.1 ?? .distantPast) > ($1.1 ?? .distantPast) }
            .map(\.0)
    }

    /// Watched movies and fully watched series are left out, as on the TV apps.
    func newEntries(now: Date = .now) -> [NewEntry] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -Self.newWindowDays, to: now) else {
            return []
        }
        let movies = snapshot.movies
            .filter { !$0.watch.played && ($0.dateAdded ?? .distantPast) >= cutoff }
            .map { (NewEntry.movie($0), $0.dateAdded ?? .distantPast) }
        let series = progressBySeries.compactMap { seriesID, progress -> (NewEntry, Date)? in
            guard progress.status != .watched else { return nil }
            let added = progress.episodes.filter { ($0.dateAdded ?? .distantPast) >= cutoff }
            guard let series = seriesByID[seriesID], let latest = added.compactMap(\.dateAdded).max() else {
                return nil
            }
            let newSeasons = Set(added.compactMap(\.seasonNumber))
            let olderSeasons = Set(progress.episodes.filter { !added.contains($0) }.compactMap(\.seasonNumber))
            let isNewSeason = !olderSeasons.isEmpty && !newSeasons.isSubset(of: olderSeasons)
            return (.series(series, newEpisodeCount: added.count, isNewSeason: isNewSeason), latest)
        }
        return (movies + series).sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// The first episode in air order that came in during the New window.
    func firstNewEpisode(of seriesID: String, now: Date = .now) -> Episode? {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -Self.newWindowDays, to: now) else {
            return nil
        }
        return progressBySeries[seriesID]?.episodes.first { ($0.dateAdded ?? .distantPast) >= cutoff }
    }

    var notStartedMovies: [Movie] {
        snapshot.movies
            .filter { status(of: $0) == .notStarted }
            .sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
    }

    var notStartedSeries: [Series] {
        snapshot.series
            .filter { status(of: $0) == .notStarted }
            .sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
    }

    func newEpisodeCount(of seriesID: String, days: Int, now: Date = .now) -> Int {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return 0 }
        return progressBySeries[seriesID]?.episodes.count { ($0.dateAdded ?? .distantPast) >= cutoff } ?? 0
    }

    private static func progress(of episodes: [Episode]) -> SeriesProgress {
        let ordered = episodes.sorted(by: Self.airOrder)
        let regular = ordered.filter { ($0.seasonNumber ?? 0) > 0 }
        let seasons = Dictionary(grouping: ordered, by: { $0.seasonNumber ?? 0 })
            .map { number, episodes in
                SeasonSummary(
                    number: number, episodeCount: episodes.count,
                    watchedCount: episodes.count(where: \.watch.played)
                )
            }
            .sorted { ($0.number == 0 ? Int.max : $0.number) < ($1.number == 0 ? Int.max : $1.number) }
        let touched = regular.filter { $0.watch.lastPlayed != nil && ($0.watch.played || $0.watch.isInProgress) }
        let lastTouched = touched.max {
            ($0.watch.lastPlayed ?? .distantPast) < ($1.watch.lastPlayed ?? .distantPast)
        }
        let next: Episode?
        if let lastTouched, lastTouched.watch.isInProgress {
            next = lastTouched
        } else if let lastTouched, let index = regular.firstIndex(of: lastTouched) {
            next = regular[(index + 1)...].first { !$0.watch.played }
        } else {
            next = nil
        }
        return SeriesProgress(
            episodes: ordered,
            seasons: seasons,
            watchedCount: ordered.count(where: \.watch.played),
            lastTouched: lastTouched?.watch.lastPlayed,
            next: next
        )
    }

    private static func airOrder(_ lhs: Episode, _ rhs: Episode) -> Bool {
        let lhsSeason = lhs.seasonNumber.map { $0 == 0 ? Int.max : $0 } ?? Int.max
        let rhsSeason = rhs.seasonNumber.map { $0 == 0 ? Int.max : $0 } ?? Int.max
        if lhsSeason != rhsSeason { return lhsSeason < rhsSeason }
        return (lhs.episodeNumber ?? 0) < (rhs.episodeNumber ?? 0)
    }
}
