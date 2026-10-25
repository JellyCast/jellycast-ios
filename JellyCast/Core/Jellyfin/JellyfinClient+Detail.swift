import Foundation

nonisolated struct MediaInfo: Sendable, Equatable {
    struct Stream: Decodable, Sendable, Equatable {
        let `Type`: String
        let Index: Int?
        let Codec: String?
        let Profile: String?
        let Width: Int?
        let Height: Int?
        let VideoRangeType: String?
        let Channels: Int?
        let DisplayTitle: String?
        let Title: String?
        let IsDefault: Bool?
        let IsForced: Bool?
        let IsHearingImpaired: Bool?
        let IsExternal: Bool?
        let Language: String?
    }

    let mediaSourceID: String
    let bitsPerSecond: Int
    let streams: [Stream]
    var sizeBytes: Int64?

    var sourceVideo: SourceVideo {
        SourceVideo(bitsPerSecond: bitsPerSecond, width: streams.first { $0.Type == "Video" }?.Width ?? 0)
    }

    var audioStreams: [Stream] { streams.filter { $0.Type == "Audio" } }

    var subtitleStreams: [Stream] { streams.filter { $0.Type == "Subtitle" } }
}

nonisolated struct PersonResult: Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let role: String?
    let image: ImageRef?
}

/// The people, studios and links of one movie or episode, as the player shows and ranks them.
nonisolated struct ItemDetails: Sendable, Equatable {
    let cast: [PersonResult]
    let peopleIDs: Set<String>
    let studioIDs: Set<String>
}

/// A movie the server calls similar, with what it shares to rank it on.
nonisolated struct SimilarMovie: Sendable {
    let id: String
    let peopleIDs: Set<String>
    let studioIDs: Set<String>
}

private nonisolated struct ItemPeopleDTO: Decodable {
    struct Person: Decodable {
        let Id: String
        let Name: String
        let Role: String?
        let `Type`: String?
        let PrimaryImageTag: String?
    }
    struct Studio: Decodable { let Id: String }

    let Id: String
    let People: [Person]?
    let Studios: [Studio]?
    let ProviderIds: [String: String]?

    var peopleIDs: Set<String> { Set((People ?? []).map(\.Id)) }
    var studioIDs: Set<String> { Set((Studios ?? []).map(\.Id)) }
}

extension JellyfinClient {
    private static let castLimit = 20
    private static let similarLimit = 20

    func itemDetails(itemID: String, userID: String) async throws -> ItemDetails {
        let item: ItemPeopleDTO = try await send(
            "Items/\(itemID)",
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "fields", value: "People,Studios"),
            ]
        )
        let cast = (item.People ?? []).filter { $0.Type == "Actor" }.prefix(Self.castLimit).map { person in
            PersonResult(
                id: person.Id, name: person.Name, role: person.Role,
                image: person.PrimaryImageTag.map { ImageRef(itemID: person.Id, tag: $0) }
            )
        }
        return ItemDetails(
            cast: Array(cast), peopleIDs: item.peopleIDs, studioIDs: item.studioIDs
        )
    }

    /// The person's page on the site, or a search for the name when the server keeps no id.
    func externalURL(person: PersonResult, source: RatingSource, userID: String) async throws -> URL? {
        let item: ItemPeopleDTO = try await send(
            "Items/\(person.id)",
            query: [URLQueryItem(name: "userId", value: userID), URLQueryItem(name: "fields", value: "ProviderIds")]
        )
        let ids = item.ProviderIds ?? [:]
        return source.personURL(imdbID: ids["Imdb"], tmdbID: ids["Tmdb"], name: person.name)
    }

    func similarMovies(itemID: String, userID: String) async throws -> [SimilarMovie] {
        struct Response: Decodable { let Items: [ItemPeopleDTO] }
        let response: Response = try await send(
            "Items/\(itemID)/Similar",
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "limit", value: String(Self.similarLimit)),
                URLQueryItem(name: "fields", value: "People,Studios"),
            ]
        )
        return response.Items.map { SimilarMovie(id: $0.Id, peopleIDs: $0.peopleIDs, studioIDs: $0.studioIDs) }
    }

    func mediaInfo(itemID: String, userID: String) async throws -> MediaInfo? {
        struct Source: Decodable {
            let Id: String
            let Bitrate: Int?
            let Size: Int64?
            let MediaStreams: [MediaInfo.Stream]?
        }
        struct Response: Decodable { let MediaSources: [Source]? }
        let response: Response = try await send(
            "Items/\(itemID)",
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "fields", value: "MediaSources"),
            ]
        )
        guard let source = response.MediaSources?.first else { return nil }
        return MediaInfo(
            mediaSourceID: source.Id, bitsPerSecond: source.Bitrate ?? 0, streams: source.MediaStreams ?? [],
            sizeBytes: source.Size
        )
    }

    func setPlayed(_ played: Bool, itemID: String, userID: String) async throws {
        _ = try await data(
            "UserPlayedItems/\(itemID)",
            method: played ? "POST" : "DELETE",
            query: [URLQueryItem(name: "userId", value: userID)]
        )
    }

    func searchPeople(_ term: String, userID: String) async throws -> [PersonResult] {
        struct Person: Decodable {
            let Id: String
            let Name: String
            let ImageTags: [String: String]?
        }
        struct Response: Decodable { let Items: [Person] }
        let response: Response = try await send(
            "Persons",
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "searchTerm", value: term),
                URLQueryItem(name: "limit", value: "10"),
                URLQueryItem(name: "enableImageTypes", value: "Primary"),
            ]
        )
        return response.Items.map { person in
            PersonResult(
                id: person.Id, name: person.Name, role: nil,
                image: person.ImageTags?["Primary"].map { ImageRef(itemID: person.Id, tag: $0) }
            )
        }
    }

    /// Ids of the movies and series a person appears in.
    func itemIDs(withPerson personID: String, userID: String) async throws -> [String] {
        struct Item: Decodable { let Id: String }
        struct Response: Decodable { let Items: [Item] }
        let response: Response = try await send(
            "Items",
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "recursive", value: "true"),
                URLQueryItem(name: "personIds", value: personID),
                URLQueryItem(name: "includeItemTypes", value: "Movie,Series"),
            ]
        )
        return response.Items.map(\.Id)
    }

    /// The original file, served as it is: the server neither remuxes nor transcodes.
    func originalStreamURL(itemID: String, mediaSourceID: String) -> URL {
        var components = URLComponents(
            url: serverURL.appending(path: "Videos/\(itemID)/stream"), resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "mediaSourceId", value: mediaSourceID),
        ]
        return components?.url ?? serverURL
    }

    enum ImageType: String { case primary = "Primary", backdrop = "Backdrop", thumb = "Thumb", logo = "Logo" }

    /// Cache-safe image URL at display size; the tag changes when the image does.
    func imageURL(_ ref: ImageRef, type: ImageType, pixelWidth: Int) -> URL {
        var components = URLComponents(
            url: serverURL.appending(path: "Items/\(ref.itemID)/Images/\(type.rawValue)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "tag", value: ref.tag),
            URLQueryItem(name: "fillWidth", value: String(pixelWidth)),
            URLQueryItem(name: "quality", value: "85"),
        ]
        return components?.url ?? serverURL
    }
}
