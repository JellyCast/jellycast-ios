import Foundation

/// One tile on Home.
nonisolated enum HomeItem: Sendable, Hashable, Identifiable {
    case continueWatching(Playable)
    case newMovie(Movie)
    case newEpisodes(Series, firstNew: Episode?, count: Int, isNewSeason: Bool)
    case notStartedSeries(Series)
    case notStartedMovie(Movie)

    /// The movie or series the tile stands for, so a series shows once whichever episode it shows.
    var id: String {
        switch self {
        case .continueWatching(.movie(let movie)), .newMovie(let movie), .notStartedMovie(let movie):
            movie.id
        case .continueWatching(.episode(let episode)):
            episode.seriesID
        case .newEpisodes(let series, _, _, _), .notStartedSeries(let series):
            series.id
        }
    }
}

nonisolated extension LibraryIndex {
    /// Continue watching, then New, then what hasn't been started (series, then movies); each
    /// movie or series once, in the first group it is in.
    func homeFeed(now: Date = .now) -> [HomeItem] {
        let continuing = continueWatching.map(HomeItem.continueWatching)
        let new = newEntries(now: now).map { entry -> HomeItem in
            switch entry {
            case .movie(let movie):
                .newMovie(movie)
            case .series(let series, let count, let isNewSeason):
                .newEpisodes(
                    series, firstNew: firstNewEpisode(of: series.id, now: now),
                    count: count, isNewSeason: isNewSeason
                )
            }
        }
        let notStarted = notStartedSeries.map(HomeItem.notStartedSeries)
            + notStartedMovies.map(HomeItem.notStartedMovie)
        var seen = Set<String>()
        return (continuing + new + notStarted).filter { seen.insert($0.id).inserted }
    }
}
