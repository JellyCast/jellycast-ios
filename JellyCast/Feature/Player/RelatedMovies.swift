import Foundation

/// Picks the server's similar movies that really belong with a movie: ones that share people
/// (cast or crew) with it. A shared genre alone is not enough.
nonisolated enum RelatedMovies {
    private static let minimumSharedPeople = 2
    private static let personWeight = 2

    static func rank(_ candidates: [SimilarMovie], to details: ItemDetails, excluding: Set<String>) -> [String] {
        candidates
            .filter { !excluding.contains($0.id) }
            .compactMap { candidate -> (id: String, score: Int)? in
                let sharedPeople = candidate.peopleIDs.intersection(details.peopleIDs).count
                guard sharedPeople >= minimumSharedPeople else { return nil }
                let sharedStudios = candidate.studioIDs.intersection(details.studioIDs).count
                return (candidate.id, sharedPeople * personWeight + sharedStudios)
            }
            .sorted { $0.score > $1.score }
            .map(\.id)
    }

    /// Keeps the ranking between collections, but puts the movies of one collection together and
    /// in release order, so a trilogy reads first, second, third.
    static func groupedByCollection(_ movies: [Movie]) -> [Movie] {
        var groups: [(key: String, movies: [Movie])] = []
        for movie in movies {
            let key = movie.collectionID ?? movie.id
            if let index = groups.firstIndex(where: { $0.key == key }) {
                groups[index].movies.append(movie)
            } else {
                groups.append((key, [movie]))
            }
        }
        return groups.flatMap { $0.movies.sorted { ($0.year ?? 0) < ($1.year ?? 0) } }
    }

    /// "The Lord of the Rings" from "The Lord of the Rings: The Two Towers" and its siblings;
    /// nil when the titles share no part before a colon.
    static func collectionTitle(of names: [String]) -> String? {
        guard let first = names.first, let colon = first.firstIndex(of: ":") else { return nil }
        let prefix = String(first[..<colon])
        return names.allSatisfy { $0.hasPrefix(prefix + ":") } ? prefix : nil
    }
}
