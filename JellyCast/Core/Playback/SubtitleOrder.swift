import Foundation

/// The subtitle list as the track sheet shows it: the user's languages first, then the rest
/// alphabetically by name, and per track the language with only what tells it apart.
nonisolated enum SubtitleOrder {
    struct Track: Equatable {
        let id: Int
        let language: String?
        /// The name in the file, e.g. "SDH", "Simplified" or a release name.
        let title: String?
        let codec: String?
        let isHearingImpaired: Bool
        let isForced: Bool
    }

    struct Entry: Equatable {
        let id: Int
        /// In the app's language; `nil` when the file does not say.
        let language: String?
        /// A name from the file that adds something to the language.
        let title: String?
        let isSDH: Bool
        let isForced: Bool
        /// Drawn as images (PGS, VobSub): the subtitle style does not apply.
        let isImage: Bool
        /// 2, 3, … for tracks that would otherwise look the same.
        var number: Int?
    }

    /// Within a language the plain track comes before SDH, and forced comes last.
    static func entries(_ tracks: [Track], preferred: [String], locale: Locale = .current) -> [Entry] {
        let preferredCodes = preferred.compactMap(AudioLanguage.normalize)
        let titles = tracks.map { $0.title?.trimmingCharacters(in: .whitespaces) }
        let shared = tracks.count > 1 && Set(titles).count == 1 ? titles.first ?? nil : nil

        let ranked = tracks.enumerated().map { position, track in
            let code = AudioLanguage.normalize(track.language)
            let names = code.map { languageNames($0, locale: locale) } ?? []
            let title = titles[position].flatMap { $0.isEmpty || $0 == shared ? nil : $0 }
            let keywords = title?.lowercased() ?? ""
            let entry = Entry(
                id: track.id,
                language: names.first,
                title: title.flatMap { $0.count > maxTitleLength || onlyRepeats($0, names: names) ? nil : $0 },
                isSDH: track.isHearingImpaired || sdhWords.contains { containsWord(keywords, $0) },
                isForced: track.isForced || containsWord(keywords, "forced"),
                isImage: track.codec.map(isImageCodec) ?? false
            )
            let rank = code.flatMap { preferredCodes.firstIndex(of: $0) } ?? preferredCodes.count
            return (entry: entry, rank: rank, position: position)
        }

        let sorted = ranked.sorted { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            if (a.entry.language == nil) != (b.entry.language == nil) { return a.entry.language != nil }
            let nameOrder = (a.entry.language ?? a.entry.title ?? "")
                .compare(b.entry.language ?? b.entry.title ?? "", locale: locale)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            if a.entry.variantOrder != b.entry.variantOrder { return a.entry.variantOrder < b.entry.variantOrder }
            return a.position < b.position
        }

        var seen: [String: Int] = [:]
        return sorted.map { item in
            var entry = item.entry
            let key = "\(entry.language ?? "")|\(entry.title ?? "")|\(entry.isSDH)|\(entry.isForced)|\(entry.isImage)"
            let count = (seen[key] ?? 0) + 1
            seen[key] = count
            entry.number = count > 1 ? count : nil
            return entry
        }
    }

    /// The name in [locale] first, then in English and in the language itself.
    private static func languageNames(_ code: String, locale: Locale) -> [String] {
        let identifier = Locale.Language(identifier: code).languageCode?.identifier(.alpha2) ?? code
        return [locale, Locale(identifier: "en"), Locale(identifier: identifier)].map { names in
            let name = names.localizedString(forLanguageCode: identifier) ?? code
            return name.prefix(1).uppercased(with: names) + name.dropFirst()
        }
    }

    /// True when the title says nothing beyond the language, SDH, forced or the format.
    private static func onlyRepeats(_ title: String, names: [String]) -> Bool {
        var rest = title.lowercased()
        for word in (names.map { $0.lowercased() } + noiseWords).sorted(by: { $0.count > $1.count }) {
            rest = rest.replacingOccurrences(of: wordPattern(word), with: " ", options: .regularExpression)
        }
        return !rest.contains { $0.isLetter || $0.isNumber }
    }

    private static func containsWord(_ text: String, _ word: String) -> Bool {
        text.range(of: wordPattern(word), options: .regularExpression) != nil
    }

    private static func wordPattern(_ word: String) -> String {
        "(?<!\\p{L})\(NSRegularExpression.escapedPattern(for: word))(?!\\p{L})"
    }

    private static func isImageCodec(_ codec: String) -> Bool {
        let lower = codec.lowercased()
        return ["pgs", "dvd", "dvb", "vobsub"].contains { lower.contains($0) }
    }

    private static let maxTitleLength = 40
    private static let sdhWords = ["sdh", "cc", "hearing impaired"]
    private static let noiseWords = sdhWords + [
        "forced", "full", "default", "subtitles", "subtitle", "subs", "srt", "subrip", "ass", "ssa", "pgs", "vobsub",
    ]
}

private extension SubtitleOrder.Entry {
    nonisolated var variantOrder: Int { isForced ? 2 : isSDH ? 1 : 0 }
}
