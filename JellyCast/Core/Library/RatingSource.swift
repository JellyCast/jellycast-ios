import Foundation

/// The site whose rating and page the app shows for titles and people, chosen in Settings.
///
/// The server puts OMDb first for movies and series, so their community rating and text are IMDb's;
/// episodes keep TMDb first, so theirs are TMDb's. Rotten Tomatoes is the critics' score OMDb adds,
/// for movies only. TMDb has no rating left on movies and series.
nonisolated enum RatingSource: String, CaseIterable, Sendable {
    case imdb
    case rottenTomatoes
    case tmdb

    var title: String {
        switch self {
        case .imdb: "IMDb"
        case .rottenTomatoes: "Rotten Tomatoes"
        case .tmdb: "TMDB"
        }
    }

    /// "★ 7.8" or "91%", when the server has this site's rating for the title.
    func rating(of title: ExternalTitle) -> String? {
        switch self {
        case .rottenTomatoes:
            return title.criticRating.map { "\(Int($0.rounded()))%" }
        case .imdb, .tmdb:
            guard title.communityRatingSource == self else { return nil }
            return title.communityRating.map(Format.rating)
        }
    }

    /// The title's page; a search where the server keeps no id for this site.
    func url(of title: ExternalTitle) -> URL? {
        switch self {
        case .imdb:
            return title.imdbID.flatMap { URL(string: "https://www.imdb.com/title/\($0)/") }
        case .tmdb:
            guard let tmdbID = title.tmdbID else { return nil }
            return switch title.kind {
            case .movie: URL(string: "https://www.themoviedb.org/movie/\(tmdbID)")
            case .series: URL(string: "https://www.themoviedb.org/tv/\(tmdbID)")
            case .episode(let season?, let episode?):
                URL(string: "https://www.themoviedb.org/tv/\(tmdbID)/season/\(season)/episode/\(episode)")
            case .episode: URL(string: "https://www.themoviedb.org/tv/\(tmdbID)")
            }
        case .rottenTomatoes:
            return Self.search("https://www.rottentomatoes.com/search", "search", title.searchName)
        }
    }

    /// The person's page, or a search for the name.
    func personURL(imdbID: String?, tmdbID: String?, name: String) -> URL? {
        switch self {
        case .imdb:
            if let imdbID { return URL(string: "https://www.imdb.com/name/\(imdbID)/") }
            return Self.search("https://www.imdb.com/find/", "q", name, extra: URLQueryItem(name: "s", value: "nm"))
        case .tmdb:
            if let tmdbID { return URL(string: "https://www.themoviedb.org/person/\(tmdbID)") }
            return Self.search("https://www.themoviedb.org/search/person", "query", name)
        case .rottenTomatoes:
            return Self.search("https://www.rottentomatoes.com/search", "search", name)
        }
    }

    private static func search(_ base: String, _ key: String, _ text: String, extra: URLQueryItem? = nil) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: key, value: text)] + [extra].compactMap(\.self)
        return components?.url
    }
}

/// What the rating sites know a movie, series or episode by.
nonisolated struct ExternalTitle: Sendable {
    enum Kind: Sendable {
        case movie
        case series
        case episode(season: Int?, episode: Int?)
    }

    let kind: Kind
    /// For an episode its series' name: the sites search by series.
    let searchName: String
    let imdbID: String?
    /// For an episode its series' id: TMDb links episodes under the series.
    let tmdbID: String?
    let communityRating: Double?
    let communityRatingSource: RatingSource
    let criticRating: Double?

    init(_ movie: Movie) {
        kind = .movie
        searchName = movie.name
        imdbID = movie.imdbID
        tmdbID = movie.tmdbID
        communityRating = movie.communityRating
        communityRatingSource = .imdb
        criticRating = movie.criticRating
    }

    init(_ series: Series) {
        kind = .series
        searchName = series.name
        imdbID = series.imdbID
        tmdbID = series.tmdbID
        communityRating = series.communityRating
        communityRatingSource = .imdb
        criticRating = nil
    }

    init(_ episode: Episode, series: Series?) {
        kind = .episode(season: episode.seasonNumber, episode: episode.episodeNumber)
        searchName = episode.seriesName
        imdbID = episode.imdbID
        tmdbID = series?.tmdbID
        communityRating = episode.communityRating
        communityRatingSource = .tmdb
        criticRating = nil
    }
}

/// The chosen rating site, kept on this device.
@Observable
final class RatingSettings {
    static let shared = RatingSettings()

    var source: RatingSource {
        didSet { defaults.set(source.rawValue, forKey: Self.sourceKey) }
    }

    private let defaults: UserDefaults

    private static let sourceKey = "ratings.source"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        source = defaults.string(forKey: Self.sourceKey).flatMap(RatingSource.init(rawValue:)) ?? .imdb
    }
}
