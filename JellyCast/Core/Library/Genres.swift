import Foundation

/// The server's genres come from TMDb in English, partly as combined names; the app splits and
/// translates them so one genre is one tile.
nonisolated enum Genres {
    private static let combined: [String: [String]] = [
        "Sci-Fi & Fantasy": ["Science Fiction", "Fantasy"],
        "Action & Adventure": ["Action", "Adventure"],
        "War & Politics": ["War", "Politics"],
        "Sci-Fi": ["Science Fiction"],
        "Kids": ["Family"],
    ]

    static func canonical(_ genres: [String]) -> [String] {
        var seen = Set<String>()
        return genres.flatMap { combined[$0] ?? [$0] }.filter { seen.insert($0).inserted }
    }

    static func displayName(_ genre: String) -> String {
        String(localized: String.LocalizationValue(genre), table: "Genres")
    }

    static func displayNames(_ genres: [String]) -> [String] {
        canonical(genres).map(displayName)
    }
}
