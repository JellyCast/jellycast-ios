import Foundation

/// Someone credited on a movie, series or episode, as the server lists them.
nonisolated struct Credit: Sendable, Identifiable, Hashable {
    enum Kind: String, Sendable {
        case actor = "Actor"
        case guestStar = "GuestStar"
        case director = "Director"
        case writer = "Writer"
        case producer = "Producer"
    }

    let id: String
    let name: String
    let role: String?
    let kind: Kind
    let image: ImageRef?

    var person: PersonResult { PersonResult(id: id, name: name, role: role, image: image) }
}

/// What the server knows about a person beyond the credit: mostly from TMDb and Wikipedia.
nonisolated struct PersonDetails: Sendable, Equatable {
    let birthDate: DateComponents?
    let birthplace: String?
    let biography: String?
    let imdbID: String?
    let tmdbID: String?
}

private nonisolated struct PersonDTO: Decodable {
    let Id: String
    let PremiereDate: Date?
    let ProductionLocations: [String]?
    let Overview: String?
    let ProviderIds: [String: String]?
}

extension JellyfinClient {
    /// The credits of one item, in the server's order (billing order for actors).
    func credits(itemID: String, userID: String) async throws -> [Credit] {
        struct Person: Decodable {
            let Id: String
            let Name: String
            let Role: String?
            let `Type`: String?
            let PrimaryImageTag: String?
        }
        struct Item: Decodable { let People: [Person]? }
        let item: Item = try await send(
            "Items/\(itemID)",
            query: [URLQueryItem(name: "userId", value: userID), URLQueryItem(name: "fields", value: "People")]
        )
        return (item.People ?? []).compactMap { person in
            guard let kind = person.Type.flatMap(Credit.Kind.init(rawValue:)) else { return nil }
            return Credit(
                id: person.Id, name: person.Name, role: person.Role, kind: kind,
                image: person.PrimaryImageTag.map { ImageRef(itemID: person.Id, tag: $0) }
            )
        }
    }

    /// Details of several people in one request, keyed by person id.
    func personDetails(ids: [String], userID: String) async throws -> [String: PersonDetails] {
        guard !ids.isEmpty else { return [:] }
        struct Response: Decodable { let Items: [PersonDTO] }
        let response: Response = try await send(
            "Items",
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "ids", value: ids.joined(separator: ",")),
                URLQueryItem(name: "fields", value: "Overview,ProductionLocations,PremiereDate,ProviderIds"),
            ]
        )
        return Dictionary(
            response.Items.map { ($0.Id, PersonDetails($0)) }, uniquingKeysWith: { first, _ in first }
        )
    }
}

private nonisolated extension PersonDetails {
    init(_ dto: PersonDTO) {
        self.init(
            birthDate: dto.PremiereDate.map(Self.calendarDate),
            birthplace: dto.ProductionLocations?.first.flatMap(Self.place),
            biography: dto.Overview.flatMap(Self.cleanBiography),
            imdbID: dto.ProviderIds?["Imdb"],
            tmdbID: dto.ProviderIds?["Tmdb"]
        )
    }

    /// The server stores a birthday as midnight in its own time zone, sent in UTC (the evening
    /// before for Europe). Noon UTC lands on the right calendar day for any zone within 12 hours.
    static func calendarDate(_ date: Date) -> DateComponents {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        return utc.dateComponents([.year, .month, .day], from: date.addingTimeInterval(12 * 3600))
    }

    /// "Manhattan, New York City, New York, USA" becomes "Manhattan, United States" in the
    /// device's language: the first and the last part.
    static func place(_ raw: String) -> String? {
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = parts.first else { return nil }
        guard parts.count > 1, let last = parts.last else { return first }
        return "\(first), \(Country.localizedName(last))"
    }

    /// TMDb copies Wikipedia's attribution into the text; that isn't part of the biography.
    static func cleanBiography(_ raw: String) -> String? {
        var text = raw
        for marker in ["Description above from the Wikipedia", "Description above from Wikipedia"] {
            if let range = text.range(of: marker) { text = String(text[..<range.lowerBound]) }
        }
        text = text.replacingOccurrences(of: "From Wikipedia, the free encyclopedia.", with: "")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Country names as TMDb writes them (English), shown in the device's language.
nonisolated enum Country {
    private static let aliases = ["USA": "US", "UK": "GB", "England": "GB", "Scotland": "GB", "Wales": "GB"]

    static func localizedName(_ english: String) -> String {
        guard let code = aliases[english] ?? code(forEnglishName: english) else { return english }
        return Locale.current.localizedString(forRegionCode: code) ?? english
    }

    private static func code(forEnglishName name: String) -> String? {
        let english = Locale(identifier: "en")
        return Locale.Region.isoRegions.first {
            english.localizedString(forRegionCode: $0.identifier) == name
        }?.identifier
    }
}
