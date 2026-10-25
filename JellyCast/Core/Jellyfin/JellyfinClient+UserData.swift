import Foundation

/// Where the user is in one item, as the server keeps it.
nonisolated struct ItemPosition: Sendable {
    let positionTicks: Int64
    let played: Bool
    let lastPlayed: Date?
}

extension JellyfinClient {
    func position(itemID: String, userID: String) async throws -> ItemPosition {
        struct Response: Decodable {
            let PlaybackPositionTicks: Int64?
            let Played: Bool?
            let LastPlayedDate: Date?
        }
        let response: Response = try await send(
            "UserItems/\(itemID)/UserData", query: [URLQueryItem(name: "userId", value: userID)]
        )
        return ItemPosition(
            positionTicks: response.PlaybackPositionTicks ?? 0, played: response.Played ?? false,
            lastPlayed: response.LastPlayedDate
        )
    }

    /// Sets the position with the time it was watched, which the server keeps as it is; a
    /// playback report would stamp it with now.
    func setPosition(_ position: ItemPosition, itemID: String, userID: String) async throws {
        var body: [String: JSONValue] = [
            "PlaybackPositionTicks": .int(position.positionTicks),
            "Played": .bool(position.played),
        ]
        if let lastPlayed = position.lastPlayed {
            body["LastPlayedDate"] = .string(lastPlayed.formatted(.iso8601))
        }
        _ = try await data(
            "UserItems/\(itemID)/UserData", method: "POST",
            query: [URLQueryItem(name: "userId", value: userID)],
            body: try JSONEncoder().encode(body)
        )
    }
}
