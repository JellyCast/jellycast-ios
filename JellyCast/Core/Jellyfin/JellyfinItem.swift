import Foundation

/// The part of Jellyfin's `BaseItemDto` the library uses, as the server sends it.
nonisolated struct JellyfinItem: Decodable, Sendable {
    struct ItemUserData: Decodable, Sendable {
        let PlaybackPositionTicks: Int64?
        let PlayCount: Int?
        let IsFavorite: Bool?
        let Played: Bool?
        let LastPlayedDate: Date?
        let UnplayedItemCount: Int?
    }

    let Id: String
    let Name: String
    let `Type`: String
    let Overview: String?
    let Genres: [String]?
    let ProductionYear: Int?
    let PremiereDate: Date?
    let DateCreated: Date?
    let RunTimeTicks: Int64?
    let CommunityRating: Double?
    let CriticRating: Double?
    let OfficialRating: String?
    let Status: String?
    let ChildCount: Int?

    let SeriesId: String?
    let SeriesName: String?
    let SeasonId: String?
    let SeasonName: String?
    let IndexNumber: Int?
    let ParentIndexNumber: Int?

    let ProviderIds: [String: String]?

    let ImageTags: [String: String]?
    let BackdropImageTags: [String]?
    let ParentBackdropItemId: String?
    let ParentBackdropImageTags: [String]?
    let SeriesPrimaryImageTag: String?
    let ParentThumbItemId: String?
    let ParentThumbImageTag: String?

    let UserData: ItemUserData?
}
