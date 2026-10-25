import Foundation

nonisolated struct MediaSegment: Decodable, Sendable, Hashable {
    enum Kind: String, Sendable {
        case intro = "Intro", recap = "Recap", outro = "Outro", preview = "Preview", commercial = "Commercial"
    }

    let `Type`: String
    let StartTicks: Int64
    let EndTicks: Int64

    var kind: Kind? { Kind(rawValue: Type) }
    var startSeconds: Double { Ticks.seconds(StartTicks) }
    var endSeconds: Double { Ticks.seconds(EndTicks) }

    func contains(_ seconds: Double) -> Bool { seconds >= startSeconds && seconds < endSeconds }

    /// The intro, recap or preview playing now, which a skip pill jumps over.
    static func skippable(in segments: [MediaSegment], at seconds: Double) -> MediaSegment? {
        segments.first { segment in
            [.intro, .recap, .preview].contains(segment.kind) && segment.contains(seconds)
                && segment.endSeconds - seconds > 1
        }
    }

    var skipTitle: String {
        switch kind {
        case .recap: String(localized: "Skip recap")
        case .preview: String(localized: "Skip preview")
        default: String(localized: "Skip intro")
        }
    }
}

/// What one playback reports to the server: the same item, file and session id in every report.
nonisolated struct PlaybackReport: Sendable {
    let itemID: String
    let mediaSourceID: String
    let playSessionID: String
    var positionTicks: Int64
    var isPaused: Bool
    var audioStreamIndex: Int?
    var subtitleStreamIndex: Int?
    var isTranscode = false
}

extension JellyfinClient {
    func mediaSegments(itemID: String) async throws -> [MediaSegment] {
        struct Response: Decodable { let Items: [MediaSegment] }
        let response: Response = try await send("MediaSegments/\(itemID)")
        return response.Items
    }

    func reportPlaybackStart(_ report: PlaybackReport) async throws {
        try await post("Sessions/Playing", body: report.body(event: nil))
    }

    func reportPlaybackProgress(_ report: PlaybackReport, event: String) async throws {
        try await post("Sessions/Playing/Progress", body: report.body(event: event))
    }

    func reportPlaybackStopped(_ report: PlaybackReport) async throws {
        let body: [String: JSONValue] = [
            "ItemId": .string(report.itemID),
            "MediaSourceId": .string(report.mediaSourceID),
            "PlaySessionId": .string(report.playSessionID),
            "PositionTicks": .int(report.positionTicks),
        ]
        try await post("Sessions/Playing/Stopped", body: body)
    }

    private func post(_ path: String, body: [String: JSONValue]) async throws {
        _ = try await data(path, method: "POST", body: try JSONEncoder().encode(body))
    }
}

nonisolated enum JSONValue: Encodable, Sendable {
    case string(String), int(Int64), bool(Bool)
    indirect case array([JSONValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let values): try container.encode(values)
        }
    }
}

private nonisolated extension PlaybackReport {
    func body(event: String?) -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "ItemId": .string(itemID),
            "MediaSourceId": .string(mediaSourceID),
            "PlaySessionId": .string(playSessionID),
            "PositionTicks": .int(positionTicks),
            "IsPaused": .bool(isPaused),
            "IsMuted": .bool(false),
            "CanSeek": .bool(true),
            "PlayMethod": .string(isTranscode ? "Transcode" : "DirectPlay"),
        ]
        if let audioStreamIndex { body["AudioStreamIndex"] = .int(Int64(audioStreamIndex)) }
        if let subtitleStreamIndex { body["SubtitleStreamIndex"] = .int(Int64(subtitleStreamIndex)) }
        if let event { body["EventName"] = .string(event) }
        return body
    }
}
