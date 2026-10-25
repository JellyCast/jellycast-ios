import Foundation

nonisolated enum Format {
    /// "2 h 49 min", "41 min".
    static func runtime(_ ticks: Int64?) -> String? {
        guard let ticks, ticks > 0 else { return nil }
        let minutes = Int((Ticks.seconds(ticks) / 60).rounded())
        let hours = minutes / 60
        guard hours > 0 else { return String(localized: "\(minutes) min") }
        return String(localized: "\(hours) h \(minutes % 60) min")
    }

    /// "18 min left", "1 h 2 min left".
    static func remaining(_ ticks: Int64?) -> String? {
        runtime(ticks).map { String(localized: "\($0) left") }
    }

    /// "S3 · E4".
    static func seasonEpisode(_ episode: Episode) -> String {
        switch (episode.seasonNumber, episode.episodeNumber) {
        case let (season?, number?) where season > 0: "S\(season) · E\(number)"
        case let (season?, nil) where season > 0: "S\(season)"
        default: String(localized: "Special")
        }
    }

    /// "117 Mbit/s", "2.5 Mbit/s".
    static func megabits(_ bitsPerSecond: Int) -> String {
        let megabits = (Double(bitsPerSecond) / 1_000_000)
            .formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "\(megabits) Mbit/s")
    }

    static func joined(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "★ 7,8": the community rating, which on this server comes from TMDb.
    static func rating(_ value: Double) -> String {
        "★ " + value.formatted(.number.precision(.fractionLength(1)))
    }
}

nonisolated extension Format {
    /// "18 min left" while in progress, otherwise the runtime.
    static func timeLabel(_ playable: Playable) -> String? {
        playable.watch.isInProgress ? remaining(playable.remainingTicks) : runtime(playable.runtimeTicks)
    }
}
