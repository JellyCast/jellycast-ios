import SwiftUI

/// Searching the library: the term, people from the server, matching episodes and recent searches.
/// Matching titles are filtered in `LibraryListing`, so the library's own filters apply to them.
@Observable
final class SearchModel {
    var query = ""
    private(set) var episodes: [Episode] = []
    private(set) var people: [PersonResult] = []
    private(set) var recentSearches: [String]

    private static let recentKey = "recentSearches"
    private static let recentLimit = 5
    private static let episodeLimit = 10
    private static let peopleDelay = Duration.milliseconds(300)

    init() {
        recentSearches = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
    }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    func updateEpisodes(index: LibraryIndex?) {
        let term = trimmedQuery
        guard let index, !term.isEmpty else {
            episodes = []
            return
        }
        episodes = Array(index.snapshot.episodes.lazy
            .filter { LibraryListing.matches($0.name, term) }
            .prefix(Self.episodeLimit))
    }

    func searchPeople(session: Session) async {
        let term = trimmedQuery
        guard !term.isEmpty else {
            people = []
            return
        }
        do {
            try await Task.sleep(for: Self.peopleDelay)
            people = try await session.client.searchPeople(term, userID: session.userID)
        } catch {
            if !(error is CancellationError) { people = [] }
        }
    }

    func remember() {
        let term = trimmedQuery
        guard !term.isEmpty else { return }
        recentSearches = Array(([term] + recentSearches.filter { $0.caseInsensitiveCompare(term) != .orderedSame })
            .prefix(Self.recentLimit))
        UserDefaults.standard.set(recentSearches, forKey: Self.recentKey)
    }

    func forget(_ term: String) {
        recentSearches.removeAll { $0 == term }
        UserDefaults.standard.set(recentSearches, forKey: Self.recentKey)
    }
}

struct RecentSearchRow: View {
    let term: String
    let onSelect: () -> Void
    let onForget: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: "clock")
                        .foregroundStyle(JellyCastColors.textMuted)
                        .frame(width: 24)
                    Text(term)
                        .font(.body)
                        .foregroundStyle(JellyCastColors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 48)
                .contentShape(.rect)
            }
            .buttonStyle(PressedOpacityButtonStyle())
            Button(action: onForget) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(JellyCastColors.textMuted)
                    .frame(width: 28, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove")
        }
    }
}

struct PersonRow: View {
    let person: PersonResult
    let action: () -> Void

    private static let imageSize: CGFloat = 60

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(JellyCastColors.rail)
                    Text(initials)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(JellyCastColors.textMuted)
                    if person.image != nil {
                        RemoteImage(ref: person.image, width: Self.imageSize)
                    }
                }
                .frame(width: Self.imageSize, height: Self.imageSize)
                .clipShape(.circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(person.name).font(.headline).foregroundStyle(JellyCastColors.text)
                    if let role = person.role {
                        Text(role).font(.subheadline).foregroundStyle(JellyCastColors.textMuted)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(JellyCastColors.textMuted)
                    .frame(width: 28)
            }
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(PressedOpacityButtonStyle())
    }

    private var initials: String {
        person.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

struct EpisodeResultRow: View {
    let episode: Episode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RemoteImage(ref: episode.still, width: 96)
                    .frame(width: 96, height: 54)
                    .clipShape(.rect(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.name).font(.subheadline.weight(.semibold)).foregroundStyle(JellyCastColors.text)
                    Text(Format.joined([episode.seriesName, Format.seasonEpisode(episode)]))
                        .font(.footnote)
                        .foregroundStyle(JellyCastColors.textMuted)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(PressedOpacityButtonStyle())
    }
}
