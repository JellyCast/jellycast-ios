import Foundation

/// What the player streams: the original file, or a server transcode capped in width and bitrate.
nonisolated enum StreamLevel: Int, CaseIterable, Comparable, Sendable {
    case p720, p1080, p1440, original

    static func < (lhs: StreamLevel, rhs: StreamLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var maxWidth: Int? {
        switch self {
        case .p720: 1280
        case .p1080: 1920
        case .p1440: 2560
        case .original: nil
        }
    }

    var maxBitsPerSecond: Int? {
        switch self {
        case .p720: 2_500_000
        case .p1080: 5_000_000
        case .p1440: 10_000_000
        case .original: nil
        }
    }

    /// The bitrate cap: "5 Mbit/s", or "Original".
    var name: String {
        maxBitsPerSecond.map(Format.megabits) ?? String(localized: "Original")
    }

    /// "1080p", or "Original": what the level is called where there is no room for the bitrate.
    var shortName: String { resolution ?? name }

    var resolution: String? {
        switch self {
        case .p720: "720p"
        case .p1080: "1080p"
        case .p1440: "1440p"
        case .original: nil
        }
    }

    /// "5 Mbit/s · 1080p", or the original with the file's own bitrate: "Original · 117 Mbit/s".
    func label(sourceBitsPerSecond: Int?) -> String {
        switch self {
        case .original:
            guard let bits = sourceBitsPerSecond, bits > 0 else { return name }
            return Format.joined([name, Format.megabits(bits)])
        default: return Format.joined([name, resolution])
        }
    }
}

/// The quality asked for: a fixed level, or the highest level the connection carries up to a ceiling.
nonisolated enum QualityPreference: Hashable, Sendable {
    case auto(upTo: StreamLevel)
    case fixed(StreamLevel)

    static let all: [QualityPreference] = [
        .auto(upTo: .original), .auto(upTo: .p1440), .auto(upTo: .p1080), .auto(upTo: .p720),
        .fixed(.original), .fixed(.p1440), .fixed(.p1080), .fixed(.p720),
    ]

    var isAuto: Bool {
        if case .auto = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .auto(upTo: .original): String(localized: "Auto")
        case .auto(upTo: let ceiling): String(localized: "Auto, up to \(ceiling.label(sourceBitsPerSecond: nil))")
        case .fixed(.original): String(localized: "Original")
        case .fixed(let level): level.label(sourceBitsPerSecond: nil)
        }
    }

    var storageValue: String {
        switch self {
        case .auto(let ceiling): "auto-\(ceiling.rawValue)"
        case .fixed(let level): "fixed-\(level.rawValue)"
        }
    }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: "-")
        guard parts.count == 2, let raw = Int(parts[1]), let level = StreamLevel(rawValue: raw) else {
            return nil
        }
        switch parts[0] {
        case "auto": self = .auto(upTo: level)
        case "fixed": self = .fixed(level)
        default: return nil
        }
    }
}

/// The video of the file as it is on the server.
nonisolated struct SourceVideo: Sendable, Equatable {
    let bitsPerSecond: Int
    let width: Int
}

nonisolated enum QualityChoice {
    /// Peaks in a stream run about this far above its average bitrate.
    static let headroom = 1.3

    /// The level to play. Auto picks once, at the start, the highest level whose bitrate the
    /// connection carries with headroom; without a measurement it takes the ceiling.
    static func level(
        for preference: QualityPreference, source: SourceVideo, connectionBitsPerSecond: Double?
    ) -> StreamLevel {
        switch preference {
        case .fixed(let level):
            return resolved(level, source: source)
        case .auto(let ceiling):
            guard let connection = connectionBitsPerSecond else { return resolved(ceiling, source: source) }
            let candidates = StreamLevel.allCases.filter { $0 <= ceiling }.reversed()
            let fitting = candidates.lazy
                .map { resolved($0, source: source) }
                .first { connection >= Double(bitsPerSecond(of: $0, source: source)) * headroom }
            return fitting ?? resolved(.p720, source: source)
        }
    }

    /// A level that would not make the file smaller plays the original: no transcode for nothing.
    static func resolved(_ level: StreamLevel, source: SourceVideo) -> StreamLevel {
        guard let maxBits = level.maxBitsPerSecond, let maxWidth = level.maxWidth else { return .original }
        return source.bitsPerSecond <= maxBits && source.width <= maxWidth ? .original : level
    }

    /// The levels worth offering for this file, highest first, the original always included.
    static func offered(for source: SourceVideo) -> [StreamLevel] {
        StreamLevel.allCases.reversed().filter { resolved($0, source: source) == $0 }
    }

    private static func bitsPerSecond(of level: StreamLevel, source: SourceVideo) -> Int {
        level.maxBitsPerSecond ?? source.bitsPerSecond
    }
}
