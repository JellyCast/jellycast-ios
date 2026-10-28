import Foundation

nonisolated extension Movie {
    init(_ item: JellyfinItem) {
        self.init(
            id: item.Id,
            name: item.Name,
            overview: item.Overview,
            genres: item.Genres ?? [],
            year: item.ProductionYear,
            dateAdded: item.DateCreated,
            runtimeTicks: item.RunTimeTicks,
            communityRating: item.CommunityRating,
            officialRating: item.OfficialRating,
            poster: item.ownImage("Primary"),
            backdrop: item.ownBackdrop,
            logo: item.ownImage("Logo"),
            collectionID: item.ProviderIds?["TmdbCollection"],
            imdbID: item.ProviderIds?["Imdb"],
            tmdbID: item.ProviderIds?["Tmdb"],
            criticRating: item.CriticRating,
            watch: WatchState(item.UserData)
        )
    }
}

nonisolated extension Series {
    init(_ item: JellyfinItem) {
        self.init(
            id: item.Id,
            name: item.Name,
            overview: item.Overview,
            genres: item.Genres ?? [],
            year: item.ProductionYear,
            dateAdded: item.DateCreated,
            isEnded: item.Status == "Ended",
            communityRating: item.CommunityRating,
            officialRating: item.OfficialRating,
            poster: item.ownImage("Primary"),
            backdrop: item.ownBackdrop,
            logo: item.ownImage("Logo"),
            imdbID: item.ProviderIds?["Imdb"],
            tmdbID: item.ProviderIds?["Tmdb"],
            watch: WatchState(item.UserData),
            unplayedEpisodeCount: item.UserData?.UnplayedItemCount ?? 0
        )
    }
}

nonisolated extension Episode {
    /// Nil for an episode without a series, which the library can't place.
    init?(_ item: JellyfinItem) {
        guard let seriesID = item.SeriesId else { return nil }
        self.init(
            id: item.Id,
            name: item.Name,
            overview: item.Overview,
            seriesID: seriesID,
            seriesName: item.SeriesName ?? "",
            seasonID: item.SeasonId,
            seasonNumber: item.ParentIndexNumber,
            episodeNumber: item.IndexNumber,
            premiereDate: item.PremiereDate,
            dateAdded: item.DateCreated,
            runtimeTicks: item.RunTimeTicks,
            still: item.ownImage("Primary"),
            seriesPoster: item.SeriesPrimaryImageTag.map { ImageRef(itemID: seriesID, tag: $0) },
            seriesBackdrop: item.parentBackdrop,
            seasonThumb: item.seasonThumb,
            imdbID: item.ProviderIds?["Imdb"],
            communityRating: item.CommunityRating,
            watch: WatchState(item.UserData)
        )
    }
}

nonisolated extension WatchState {
    init(_ userData: JellyfinItem.ItemUserData?) {
        self.init(
            played: userData?.Played ?? false,
            positionTicks: userData?.PlaybackPositionTicks ?? 0,
            lastPlayed: userData?.LastPlayedDate,
            isFavorite: userData?.IsFavorite ?? false
        )
    }
}

private nonisolated extension JellyfinItem {
    func ownImage(_ type: String) -> ImageRef? {
        ImageTags?[type].map { ImageRef(itemID: Id, tag: $0) }
    }

    var ownBackdrop: ImageRef? {
        BackdropImageTags?.first.map { ImageRef(itemID: Id, tag: $0) }
    }

    /// The parent thumb falls back to the series' own; only the season's counts here.
    var seasonThumb: ImageRef? {
        guard let itemID = ParentThumbItemId, itemID == SeasonId, let tag = ParentThumbImageTag else {
            return nil
        }
        return ImageRef(itemID: itemID, tag: tag)
    }

    var parentBackdrop: ImageRef? {
        guard let itemID = ParentBackdropItemId, let tag = ParentBackdropImageTags?.first else {
            return nil
        }
        return ImageRef(itemID: itemID, tag: tag)
    }
}
