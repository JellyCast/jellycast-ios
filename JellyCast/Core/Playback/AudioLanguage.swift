import Foundation

/// Picks the audio track to start with. Dubbed releases mark their dub as the default track, so the
/// title's original language comes first, then English and Dutch, and only then the default.
nonisolated enum AudioLanguage {
    struct Track: Equatable {
        let id: Int
        let language: String?
        let isDefault: Bool
        let isCommentary: Bool
    }

    static let fallback = ["eng", "nld"]

    /// `nil` when the file has none of the languages: then the default track stays.
    static func preferredTrack(in tracks: [Track], languages: [String]) -> Track? {
        for language in languages {
            let candidates = tracks.filter {
                !$0.isCommentary && normalize($0.language) != nil && normalize($0.language) == normalize(language)
            }
            if let track = candidates.first(where: \.isDefault) ?? candidates.first { return track }
        }
        return nil
    }

    /// Track tags mix ISO 639-2/B ("fre") and /T ("fra"); Wikidata gives ISO 639-1 ("fr").
    /// Everything becomes 639-2/T.
    static func normalize(_ code: String?) -> String? {
        guard let lower = code?.trimmingCharacters(in: .whitespaces).lowercased(),
              !lower.isEmpty, lower != "und"
        else { return nil }
        if let terminology = bibliographicCodes[lower] { return terminology }
        guard lower.count == 2 else { return lower }
        return Locale.Language(identifier: lower).languageCode?.identifier(.alpha3) ?? lower
    }

    private static let bibliographicCodes = [
        "alb": "sqi", "arm": "hye", "baq": "eus", "bur": "mya", "chi": "zho", "cze": "ces",
        "dut": "nld", "fre": "fra", "geo": "kat", "ger": "deu", "gre": "ell", "ice": "isl",
        "mac": "mkd", "may": "msa", "per": "fas", "rum": "ron", "slo": "slk", "tib": "bod",
        "wel": "cym",
    ]
}
