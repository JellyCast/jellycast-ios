import Foundation

nonisolated enum LibraryKind: CaseIterable, Hashable, Sendable {
    case all, series, movies
}

nonisolated enum LibrarySort: CaseIterable, Hashable, Sendable {
    case newest, title, year, length
}

/// One row in Library: a movie or a series, with what the list sorts and filters on.
nonisolated struct LibraryEntry: Identifiable, Hashable, Sendable {
    enum Item: Hashable, Sendable {
        case movie(Movie)
        case series(Series)
    }

    let item: Item
    let status: WatchStatus
    let runtimeTicks: Int64

    var id: String {
        switch item {
        case .movie(let movie): movie.id
        case .series(let series): series.id
        }
    }

    var name: String {
        switch item {
        case .movie(let movie): movie.name
        case .series(let series): series.name
        }
    }

    var dateAdded: Date? {
        switch item {
        case .movie(let movie): movie.dateAdded
        case .series(let series): series.dateAdded
        }
    }

    var year: Int? {
        switch item {
        case .movie(let movie): movie.year
        case .series(let series): series.year
        }
    }

    var genres: [String] {
        switch item {
        case .movie(let movie): movie.genres
        case .series(let series): series.genres
        }
    }

    var poster: ImageRef? {
        switch item {
        case .movie(let movie): movie.poster
        case .series(let series): series.poster
        }
    }
}

nonisolated struct LibrarySection: Identifiable, Sendable {
    let title: String
    let entries: [LibraryEntry]

    var id: String { title }
}

nonisolated enum LibraryListing {
    private static let weekDays = 7
    private static let monthDays = 30
    private static let shortTicks = 2 * 3600 * Ticks.perSecond
    private static let longTicks = 3 * 3600 * Ticks.perSecond

    static func entries(_ index: LibraryIndex, kind: LibraryKind) -> [LibraryEntry] {
        let movies: [LibraryEntry] = kind == .series ? [] : index.snapshot.movies.map { movie in
            LibraryEntry(
                item: .movie(movie), status: index.status(of: movie), runtimeTicks: movie.runtimeTicks ?? 0
            )
        }
        let series: [LibraryEntry] = kind == .movies ? [] : index.snapshot.series.map { series in
            let runtime = index.progress(of: series.id)?.episodes.reduce(0) { $0 + ($1.runtimeTicks ?? 0) } ?? 0
            return LibraryEntry(item: .series(series), status: index.status(of: series), runtimeTicks: runtime)
        }
        return movies + series
    }

    static func filtered(_ entries: [LibraryEntry], genre: String?, query: String) -> [LibraryEntry] {
        entries.filter { entry in
            (genre.map { Genres.canonical(entry.genres).contains($0) } ?? true)
                && (query.isEmpty || matches(entry.name, query))
        }
    }

    static func matches(_ name: String, _ term: String) -> Bool {
        name.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func genreCounts(_ entries: [LibraryEntry]) -> [(genre: String, count: Int)] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for genre in Genres.canonical(entry.genres) { counts[genre, default: 0] += 1 }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    static func sections(
        _ entries: [LibraryEntry], status: WatchStatus?, sort: LibrarySort, now: Date = .now
    ) -> [LibrarySection] {
        let filtered = status.map { status in entries.filter { $0.status == status } } ?? entries
        switch sort {
        case .newest:
            let sorted = filtered.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
            return grouped(sorted) { entry in
                let added = entry.dateAdded ?? .distantPast
                let days = Calendar.current.dateComponents([.day], from: added, to: now).day ?? .max
                if days < weekDays { return String(localized: "Added this week") }
                if days < monthDays { return String(localized: "Added this month") }
                return String(localized: "Earlier")
            }
        case .title:
            let sorted = filtered.sorted {
                sortKey($0.name).localizedStandardCompare(sortKey($1.name)) == .orderedAscending
            }
            return grouped(sorted) { entry in
                guard let first = sortKey(entry.name).first, first.isLetter else { return "#" }
                return String(first).uppercased()
            }
        case .year:
            let sorted = filtered.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
            return grouped(sorted) { entry in
                guard let year = entry.year else { return String(localized: "Unknown year") }
                return String(localized: "\(String(year / 10 * 10))s")
            }
        case .length:
            let sorted = filtered.sorted { $0.runtimeTicks > $1.runtimeTicks }
            return grouped(sorted) { entry in
                if entry.runtimeTicks > longTicks { return String(localized: "Over 3 hours") }
                if entry.runtimeTicks > shortTicks { return String(localized: "2 to 3 hours") }
                return String(localized: "Under 2 hours")
            }
        }
    }

    /// Ignores a leading "The", "A" or "De" when sorting by title.
    private static func sortKey(_ name: String) -> String {
        for article in ["The ", "A ", "An ", "De ", "Het ", "Een "] where name.hasPrefix(article) {
            return String(name.dropFirst(article.count))
        }
        return name
    }

    private static func grouped(
        _ entries: [LibraryEntry], by title: (LibraryEntry) -> String
    ) -> [LibrarySection] {
        var sections: [LibrarySection] = []
        for entry in entries {
            let sectionTitle = title(entry)
            if let last = sections.last, last.title == sectionTitle {
                sections[sections.count - 1] = LibrarySection(title: sectionTitle, entries: last.entries + [entry])
            } else {
                sections.append(LibrarySection(title: sectionTitle, entries: [entry]))
            }
        }
        return sections
    }
}
