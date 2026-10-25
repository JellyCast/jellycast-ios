import Foundation

extension Session {
    static let preview = Session(
        serverURL: URL(filePath: "/"), serverID: "server", serverName: "home server",
        userID: "user", userName: "han", accessToken: ""
    )
}

extension LibrarySnapshot {
    static let preview: LibrarySnapshot = {
        let unwatched = WatchState(played: false, positionTicks: 0, lastPlayed: nil, isFavorite: false)
        var watched = unwatched
        watched.played = true
        var inProgress = unwatched
        inProgress.positionTicks = 12_000_000_000
        return LibrarySnapshot(
            formatVersion: formatVersion, serverID: "server", userID: "user", syncedAt: .now,
            movies: [
                Movie(id: "1", name: "Interstellar", overview: nil, genres: [], year: 2014,
                      dateAdded: nil, runtimeTicks: nil, communityRating: nil, officialRating: nil,
                      poster: nil, backdrop: nil, watch: watched),
                Movie(id: "2", name: "Oppenheimer", overview: nil, genres: [], year: 2023,
                      dateAdded: nil, runtimeTicks: nil, communityRating: nil, officialRating: nil,
                      poster: nil, backdrop: nil, watch: inProgress),
            ],
            series: [
                Series(id: "3", name: "The White Lotus", overview: nil, genres: [], year: 2021,
                       dateAdded: nil, isEnded: false, communityRating: nil, officialRating: nil,
                       poster: nil, backdrop: nil, watch: unwatched, unplayedEpisodeCount: 4),
            ],
            episodes: []
        )
    }()
}
