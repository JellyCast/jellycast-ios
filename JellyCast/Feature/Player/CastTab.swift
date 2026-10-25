import SwiftUI

/// Actors with what the server knows about them, then the makers under a divider. A role the
/// server lists nobody for is left out.
struct CastTab: View {
    let playable: Playable
    let store: LibraryStore
    /// For an episode: the series' own cast and makers, as on the series page.
    var wholeSeries = false

    @Environment(\.openURL) private var openURL
    @State private var cast: CastCredits?
    @State private var failed = false
    @State private var showsAll = false

    private static let collapsedActors = 6

    var body: some View {
        Group {
            if let cast {
                content(cast)
            } else if failed {
                VStack(spacing: 12) {
                    Text("The cast couldn't be loaded.").foregroundStyle(JellyCastColors.textMuted)
                    Button("Try again") { Task { await load() } }.buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
        .task(id: creditsItemID) { await load() }
    }

    private func content(_ cast: CastCredits) -> some View {
        let actors = showsAll ? cast.actors : Array(cast.actors.prefix(Self.collapsedActors))
        let hidden = cast.actors.count - actors.count + (showsAll ? 0 : cast.guestStars.count)
        return VStack(alignment: .leading, spacing: 22) {
            ForEach(actors) { credit in
                ActorRow(credit: credit, details: cast.details[credit.id]) { open(credit, cast) }
            }
            if showsAll, !cast.guestStars.isEmpty {
                ListSectionLabel(text: String(localized: "Guest stars"))
                ForEach(cast.guestStars) { credit in
                    ActorRow(credit: credit, details: cast.details[credit.id]) { open(credit, cast) }
                }
            }
            if hidden > 0 {
                Button { showsAll = true } label: {
                    HStack(spacing: 6) {
                        Text(expandTitle(cast))
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JellyCastColors.accent)
                }
                .buttonStyle(PressedOpacityButtonStyle())
            }
            if cast.hasMakers { makers(cast) }
        }
    }

    private func expandTitle(_ cast: CastCredits) -> String {
        guard !cast.guestStars.isEmpty else { return String(localized: "All \(cast.actors.count) actors") }
        return String(localized: "All \(cast.actors.count) actors and \(cast.guestStars.count) guest stars")
    }

    private func makers(_ cast: CastCredits) -> some View {
        let isEpisode = if case .episode = playable, !wholeSeries { true } else { false }
        return VStack(alignment: .leading, spacing: 16) {
            Rectangle().fill(JellyCastColors.rail).frame(height: 1)
            Text("Makers").font(.title3.bold()).foregroundStyle(JellyCastColors.text)
            if !cast.directors.isEmpty {
                makerGroup(isEpisode ? "Directed by · this episode" : "Directed by", cast.directors, cast)
            }
            if !cast.writers.isEmpty {
                makerGroup(isEpisode ? "Written by · this episode" : "Written by", cast.writers, cast)
            }
            if !cast.producers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ListSectionLabel(
                        text: isEpisode ? String(localized: "Produced by · series") : String(localized: "Produced by")
                    )
                    Text(cast.producers.map(\.name).joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(JellyCastColors.text)
                }
            }
        }
        .padding(.top, 4)
    }

    private func makerGroup(_ title: String.LocalizationValue, _ credits: [Credit], _ cast: CastCredits) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ListSectionLabel(text: String(localized: title))
            ForEach(credits) { credit in
                MakerRow(credit: credit, details: cast.details[credit.id]) { open(credit, cast) }
            }
        }
    }

    private func open(_ credit: Credit, _ cast: CastCredits) {
        let source = RatingSettings.shared.source
        if let details = cast.details[credit.id],
           let url = source.personURL(imdbID: details.imdbID, tmdbID: details.tmdbID, name: credit.name) {
            return openURL(url)
        }
        let session = store.session
        Task {
            guard let url = try? await session.client.externalURL(
                person: credit.person, source: source, userID: session.userID
            ) else { return }
            openURL(url)
        }
    }

    private var creditsItemID: String {
        if wholeSeries, case .episode(let episode) = playable { return episode.seriesID }
        return playable.id
    }

    private var fillingSeriesID: String? {
        if !wholeSeries, case .episode(let episode) = playable { return episode.seriesID }
        return nil
    }

    private func load() async {
        failed = false
        do {
            cast = try await CastCredits.load(itemID: creditsItemID, seriesID: fillingSeriesID, session: store.session)
        } catch is CancellationError {
            return
        } catch {
            if cast == nil { failed = true }
        }
    }
}

/// The credits of a movie, or of an episode plus its series, sorted into the tab's groups.
nonisolated struct CastCredits: Sendable {
    let actors: [Credit]
    let guestStars: [Credit]
    let directors: [Credit]
    let writers: [Credit]
    let producers: [Credit]
    let details: [String: PersonDetails]

    var hasMakers: Bool { !directors.isEmpty || !writers.isEmpty || !producers.isEmpty }

    static func load(for playable: Playable, session: Session) async throws -> CastCredits {
        if case .episode(let episode) = playable {
            return try await load(itemID: episode.id, seriesID: episode.seriesID, session: session)
        }
        return try await load(itemID: playable.id, seriesID: nil, session: session)
    }

    /// Episodes carry directors and writers; producers (and sometimes the actors) are on the series,
    /// passed as `seriesID` to fill in what the episode lacks.
    static func load(itemID: String, seriesID: String?, session: Session) async throws -> CastCredits {
        let client = session.client
        let own = try await client.credits(itemID: itemID, userID: session.userID)
        var series: [Credit] = []
        if let seriesID {
            series = (try? await client.credits(itemID: seriesID, userID: session.userID)) ?? []
        }
        func of(_ kind: Credit.Kind, _ credits: [Credit]) -> [Credit] { unique(credits.filter { $0.kind == kind }) }
        let actors = of(.actor, own).isEmpty ? of(.actor, series) : of(.actor, own)
        let producers = of(.producer, own).isEmpty ? of(.producer, series) : of(.producer, own)
        let groups = (
            actors: actors, guests: of(.guestStar, own), directors: of(.director, own),
            writers: of(.writer, own), producers: producers
        )
        let ids = (groups.actors + groups.guests + groups.directors + groups.writers).map(\.id)
        let details = (try? await client.personDetails(ids: ids, userID: session.userID)) ?? [:]
        return CastCredits(
            actors: groups.actors, guestStars: groups.guests, directors: groups.directors,
            writers: groups.writers, producers: groups.producers, details: details
        )
    }

    private static func unique(_ credits: [Credit]) -> [Credit] {
        var seen = Set<String>()
        return credits.filter { seen.insert($0.id).inserted }
    }
}

private struct ActorRow: View {
    let credit: Credit
    let details: PersonDetails?
    let onExternalLink: () -> Void

    private static let imageSize: CGFloat = 64
    private static let biographyLines = 3

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PersonPhoto(credit: credit, size: Self.imageSize)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(credit.name)
                        .font(.headline)
                        .foregroundStyle(JellyCastColors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ExternalTextButton(source: RatingSettings.shared.source, action: onExternalLink)
                }
                if let role = credit.role, !role.isEmpty {
                    Text("as \(role)").font(.subheadline).foregroundStyle(JellyCastColors.accent)
                }
                if let facts = PersonFacts.line(details) {
                    Text(facts).font(.footnote).foregroundStyle(JellyCastColors.textMuted)
                }
                if let biography = details?.biography {
                    Text(biography)
                        .font(.subheadline)
                        .foregroundStyle(JellyCastColors.textMuted)
                        .lineLimit(Self.biographyLines)
                        .padding(.top, 4)
                }
            }
        }
    }
}

private struct MakerRow: View {
    let credit: Credit
    let details: PersonDetails?
    let onExternalLink: () -> Void

    private static let imageSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 12) {
            PersonPhoto(credit: credit, size: Self.imageSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(credit.name).font(.subheadline.weight(.semibold)).foregroundStyle(JellyCastColors.text)
                if let facts = PersonFacts.line(details) {
                    Text(facts).font(.footnote).foregroundStyle(JellyCastColors.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ExternalTextButton(source: RatingSettings.shared.source, action: onExternalLink)
        }
    }
}

private struct PersonPhoto: View {
    let credit: Credit
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(JellyCastColors.rail)
            Text(initials)
                .font(size > 50 ? .headline : .subheadline.weight(.semibold))
                .foregroundStyle(JellyCastColors.textMuted)
            if credit.image != nil { RemoteImage(ref: credit.image, width: size) }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }

    private var initials: String {
        credit.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

private struct ExternalTextButton: View {
    let source: RatingSource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(verbatim: source.title).font(.footnote.weight(.bold)).foregroundStyle(JellyCastColors.text)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(JellyCastColors.textMuted)
            }
        }
        .buttonStyle(PressedOpacityButtonStyle())
    }
}

/// "48 years · New York City, United States", from what is known.
nonisolated enum PersonFacts {
    static func line(_ details: PersonDetails?, now: Date = .now) -> String? {
        guard let details else { return nil }
        let line = Format.joined([age(details.birthDate, now: now), details.birthplace])
        return line.isEmpty ? nil : line
    }

    private static func age(_ birthDate: DateComponents?, now: Date) -> String? {
        guard let birthDate, let born = Calendar(identifier: .gregorian).date(from: birthDate) else { return nil }
        guard let years = Calendar(identifier: .gregorian).dateComponents([.year], from: born, to: now).year,
              years > 0
        else { return nil }
        return String(localized: "\(years) years")
    }
}
