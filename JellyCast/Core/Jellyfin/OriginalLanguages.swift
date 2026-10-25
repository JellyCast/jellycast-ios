import Foundation
import OSLog

/// Jellyfin keeps no original language. Wikidata knows it by the title's IMDb id, without an API key.
actor OriginalLanguages {
    static let shared = OriginalLanguages()

    /// Per IMDb id; episodes share their series' entry.
    private var cache: [String: [String]] = [:]

    private static let logger = Logger(subsystem: "nl.jellycast.ios", category: "player")
    private static let sparqlURL = URL(string: "https://query.wikidata.org/sparql")
    /// Playback waits for this; without an answer the fallback languages decide.
    private static let timeoutSeconds = 2.5

    /// ISO 639-1 codes ("en"); empty when unknown or unreachable.
    func languages(itemID: String, client: JellyfinClient, userID: String) async -> [String] {
        do {
            guard let imdbID = try await imdbID(itemID: itemID, client: client, userID: userID) else { return [] }
            if let cached = cache[imdbID] { return cached }
            let languages = try await queryWikidata(imdbID: imdbID)
            Self.logger.info("Original language of \(imdbID, privacy: .public): \(languages, privacy: .public)")
            cache[imdbID] = languages
            return languages
        } catch {
            Self.logger.debug("No original language for \(itemID, privacy: .public): \(error, privacy: .public)")
            return []
        }
    }

    /// Episode IMDb ids rarely carry a language on Wikidata, so episodes use their series.
    private func imdbID(itemID: String, client: JellyfinClient, userID: String) async throws -> String? {
        let item = try await client.providerItem(itemID: itemID, userID: userID)
        let title = if let seriesID = item.SeriesId {
            try await client.providerItem(itemID: seriesID, userID: userID)
        } else {
            item
        }
        return title.ProviderIds?["Imdb"].flatMap { $0.hasPrefix("tt") ? $0 : nil }
    }

    private func queryWikidata(imdbID: String) async throws -> [String] {
        let query = """
            SELECT ?code WHERE { ?work wdt:P345 "\(imdbID)"; wdt:P364 ?language. \
            ?language wdt:P218 ?code }
            """
        guard let base = Self.sparqlURL,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return [] }
        components.queryItems = [URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "query", value: query)]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.timeoutSeconds
        // Wikidata refuses requests without a descriptive User-Agent.
        request.setValue("JellyCast/1.0 (personal Jellyfin client)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.languageCodes(from: data)
    }

    static func languageCodes(from data: Data) throws -> [String] {
        struct Value: Decodable { let value: String }
        struct Binding: Decodable { let code: Value? }
        struct Results: Decodable { let bindings: [Binding] }
        struct Answer: Decodable { let results: Results }
        var seen = Set<String>()
        return try JSONDecoder().decode(Answer.self, from: data).results.bindings
            .compactMap { $0.code?.value }
            .filter { seen.insert($0).inserted }
    }
}

extension JellyfinClient {
    nonisolated func providerItem(itemID: String, userID: String) async throws -> JellyfinItem {
        try await send(
            "Items/\(itemID)",
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "fields", value: "ProviderIds"),
            ]
        )
    }
}
