import Foundation

nonisolated struct ImageRef: Codable, Sendable, Hashable {
    let itemID: String
    let tag: String
}

nonisolated struct WatchState: Codable, Sendable, Hashable {
    var played: Bool
    var positionTicks: Int64
    var lastPlayed: Date?
    var isFavorite: Bool

    var isInProgress: Bool { !played && positionTicks > 0 }
}

nonisolated struct Movie: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let overview: String?
    let genres: [String]
    let year: Int?
    let dateAdded: Date?
    let runtimeTicks: Int64?
    let communityRating: Double?
    let officialRating: String?
    let poster: ImageRef?
    let backdrop: ImageRef?
    var logo: ImageRef?
    /// The TMDb collection ("The Lord of the Rings Collection") the movie belongs to.
    var collectionID: String?
    var imdbID: String?
    var tmdbID: String?
    /// The Rotten Tomatoes critics' score in percent.
    var criticRating: Double?
    var watch: WatchState
}

nonisolated struct Series: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let overview: String?
    let genres: [String]
    let year: Int?
    let dateAdded: Date?
    let isEnded: Bool
    let communityRating: Double?
    let officialRating: String?
    let poster: ImageRef?
    let backdrop: ImageRef?
    var logo: ImageRef?
    var imdbID: String?
    var tmdbID: String?
    var watch: WatchState
    var unplayedEpisodeCount: Int
}

nonisolated struct Episode: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let overview: String?
    let seriesID: String
    let seriesName: String
    let seasonID: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let premiereDate: Date?
    let dateAdded: Date?
    let runtimeTicks: Int64?
    let still: ImageRef?
    let seriesPoster: ImageRef?
    let seriesBackdrop: ImageRef?
    var imdbID: String?
    var communityRating: Double?
    var watch: WatchState
}

/// Everything one user can watch on one server, as of `syncedAt`.
nonisolated struct LibrarySnapshot: Codable, Sendable {
    static let formatVersion = 1

    let formatVersion: Int
    let serverID: String
    let userID: String
    let syncedAt: Date
    var movies: [Movie]
    var series: [Series]
    var episodes: [Episode]
}
