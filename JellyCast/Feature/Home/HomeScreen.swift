import SwiftUI

/// Home: what to watch now. Built from the cached library, so it shows without the server.
struct HomeScreen: View {
    let store: LibraryStore

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.layout) private var layout

    private static let sectionSpacing: CGFloat = 26
    private static let heroBottomSpacing: CGFloat = 18

    var body: some View {
        Group {
            if let index = store.index {
                content(index)
            } else if case .failed(let message) = store.syncState {
                ContentErrorView(message: message) { Task { await store.refresh() } }
            } else {
                HomeSkeleton()
            }
        }
        .background(JellyCastColors.background)
        .overlay(alignment: .top) { SyncProblemOverlay(store: store) }
        .animation(.easeOut(duration: 0.2), value: store.syncFailure)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { navigation.showsSettings = true } label: {
                    Label("Settings", systemImage: "person")
                }
            }
        }
    }

    private func content(_ index: LibraryIndex) -> some View {
        let upNext = index.continueWatching
        let hero = upNext.first ?? fallbackHero(index)
        let newEntries = index.newEntries()
        let notStarted = index.notStartedSeries
        return RefreshableScrollView {
            await store.refresh()
        } content: {
            VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                if let hero {
                    HomeHeroCard(playable: hero, isContinuing: hero.id == upNext.first?.id, index: index)
                        .availableOffline(hero.id)
                        .padding(.bottom, Self.heroBottomSpacing)
                }
                if upNext.count > 1 {
                    section(title: "Up next", subtitle: "in progress and next episode") {
                        ForEach(upNext.dropFirst()) { playable in
                            UpNextCard(playable: playable, index: index).availableOffline(playable.id)
                        }
                    }
                }
                if !newEntries.isEmpty {
                    section(
                        title: "New", subtitle: "last 30 days", trailing: "All",
                        onTrailing: navigation.showNewInLibrary
                    ) {
                        ForEach(newEntries) { entry in NewEntryCard(entry: entry, index: index) }
                    }
                }
                if !notStarted.isEmpty {
                    section(title: "Not started", subtitle: "series you haven't begun") {
                        ForEach(notStarted) { series in
                            let seasons = index.progress(of: series.id)?.seasons.count { $0.number > 0 } ?? 0
                            PosterCard(ref: series.poster, caption: String(localized: "\(seasons) seasons")) {
                                navigation.open(.series(id: series.id))
                            }
                            .mediaContextMenu(.series(series), index: index)
                            .availableOffline(series.id)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func fallbackHero(_ index: LibraryIndex) -> Playable? {
        if let series = index.notStartedSeries.first,
           let first = index.progress(of: series.id)?.episodes.first(where: { ($0.seasonNumber ?? 0) > 0 }) {
            return .episode(first)
        }
        return index.snapshot.movies.first(where: { !$0.watch.played }).map { .movie($0) }
    }

    private func section<Cards: View>(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        trailing: LocalizedStringKey? = nil,
        onTrailing: (() -> Void)? = nil,
        @ViewBuilder cards: () -> Cards
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, subtitle: subtitle, trailing: trailing, onTrailing: onTrailing)
                .padding(.horizontal, layout.margin)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: layout.cardSpacing) { cards() }
                    .padding(.horizontal, layout.margin)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct HomeHeroCard: View {
    let playable: Playable
    let isContinuing: Bool
    let index: LibraryIndex

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.layout) private var layout

    var body: some View {
        VStack(spacing: 10) {
            DetailHero(backdrop: backdrop, logo: logo, title: title) {
                HeroContinueFrame(playable: playable) { navigation.play(playable) }
                    .mediaContextMenu(MediaTarget(playable), index: index)
            }
            Text(label)
                .font(.caption.weight(.semibold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(JellyCastColors.accent)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(JellyCastColors.textMuted)
                .lineLimit(1)
                .padding(.horizontal, layout.margin)
        }
        .contentShape(.rect)
        .onTapGesture { navigation.open(route) }
    }

    private var title: String {
        switch playable {
        case .movie(let movie): movie.name
        case .episode(let episode): episode.seriesName
        }
    }

    private var detail: String {
        switch playable {
        case .movie(let movie):
            Format.joined([movie.year.map(String.init), Format.timeLabel(playable)])
        case .episode(let episode):
            Format.joined([Format.seasonEpisode(episode), episode.name, Format.timeLabel(playable)])
        }
    }

    private var label: LocalizedStringKey {
        guard isContinuing else { return "Start something new" }
        return playable.watch.isInProgress ? "Continue watching" : "Next episode"
    }

    private var logo: ImageRef? {
        switch playable {
        case .movie(let movie): movie.logo
        case .episode(let episode): index.seriesByID[episode.seriesID]?.logo
        }
    }

    private var backdrop: ImageRef? {
        switch playable {
        case .movie(let movie): movie.backdrop ?? movie.poster
        case .episode(let episode): episode.seriesBackdrop ?? episode.still
        }
    }

    private var route: Route {
        switch playable {
        case .movie(let movie): .movie(id: movie.id)
        case .episode(let episode): .series(id: episode.seriesID)
        }
    }
}

private struct UpNextCard: View {
    let playable: Playable
    let index: LibraryIndex

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.layout) private var layout

    private static let newEpisodeDays = 7

    var body: some View {
        let width = layout.upNextCardWidth
        Button { navigation.play(playable) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ContinueImage(playable: playable, width: width)
                    .overlay(alignment: .topLeading) {
                        if isNew { ImageBadge(text: "New").padding(8) }
                    }
                    .clipShape(.rect(cornerRadius: ContinueImage.cornerRadius))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JellyCastColors.text)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(JellyCastColors.textMuted)
            }
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(PressedOpacityButtonStyle())
        .mediaContextMenu(MediaTarget(playable), index: index)
    }

    private var title: String {
        switch playable {
        case .movie(let movie): movie.name
        case .episode(let episode): episode.seriesName
        }
    }

    private var detail: String {
        switch playable {
        case .movie(let movie): Format.joined([movie.year.map(String.init), Format.timeLabel(playable)])
        case .episode(let episode): Format.joined([Format.seasonEpisode(episode), Format.timeLabel(playable)])
        }
    }

    private var isNew: Bool {
        guard case .episode(let episode) = playable, !episode.watch.isInProgress,
              let added = episode.dateAdded,
              let cutoff = Calendar.current.date(byAdding: .day, value: -Self.newEpisodeDays, to: .now)
        else { return false }
        return added >= cutoff
    }
}

private struct NewEntryCard: View {
    let entry: NewEntry
    let index: LibraryIndex

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        switch entry {
        case .series(let series, let count, let isNewSeason):
            PosterCard(
                ref: series.poster,
                caption: isNewSeason
                    ? String(localized: "Series · new season")
                    : String(localized: "Series · \(count) new")
            ) { navigation.open(.series(id: series.id)) }
            .mediaContextMenu(.series(series), index: index)
            .availableOffline(series.id)
        case .movie(let movie):
            PosterCard(
                ref: movie.poster,
                caption: Format.joined([String(localized: "Movie"), movie.year.map(String.init)])
            ) { navigation.open(.movie(id: movie.id)) }
            .mediaContextMenu(.movie(movie), index: index)
            .availableOffline(movie.id)
        }
    }
}

/// The still of what continues, with its progress along the bottom; Up next and the hero share it.
private struct ContinueImage: View {
    let playable: Playable
    let width: CGFloat

    static let aspectRatio: CGFloat = 16 / 9
    static let cornerRadius: CGFloat = 10

    var body: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(ref: image, type: imageType, width: width)
            if let progress = playable.progress {
                WatchProgressBar.onImage(progress)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: width, height: width / Self.aspectRatio)
    }

    private var image: ImageRef? {
        switch playable {
        case .movie(let movie): movie.backdrop ?? movie.poster
        case .episode(let episode): episode.still ?? episode.seriesBackdrop
        }
    }

    private var imageType: JellyfinClient.ImageType {
        switch playable {
        case .movie(let movie): movie.backdrop == nil ? .primary : .backdrop
        case .episode(let episode): episode.still == nil ? .backdrop : .primary
        }
    }
}

/// The frame of what continues, centered on the hero's backdrop with the play button on it and
/// a shadow to lift it off the backdrop.
private struct HeroContinueFrame: View {
    let playable: Playable
    let onPlay: () -> Void

    @Environment(\.layout) private var layout

    private static let widthFraction: CGFloat = 0.56
    private static let widthFractionRegular: CGFloat = 0.44
    private static let heightFraction: CGFloat = 0.62
    private static let playSize: CGFloat = 56
    private static let shadowRadius: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let width = min(
                proxy.size.width * (layout.isRegular ? Self.widthFractionRegular : Self.widthFraction),
                proxy.size.height * Self.heightFraction * ContinueImage.aspectRatio
            )
            Button(action: onPlay) {
                ContinueImage(playable: playable, width: width)
                    .overlay { playIcon }
                    .clipShape(.rect(cornerRadius: ContinueImage.cornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: ContinueImage.cornerRadius)
                            .strokeBorder(JellyCastColors.text.opacity(0.14), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.55), radius: Self.shadowRadius, y: 8)
            }
            .buttonStyle(PressedOpacityButtonStyle())
            .accessibilityLabel(playable.watch.isInProgress ? "Continue" : "Play")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var playIcon: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(JellyCastColors.text)
            .offset(x: 2)
            .frame(width: Self.playSize, height: Self.playSize)
            .background(.black.opacity(0.35), in: .circle)
            .overlay(Circle().strokeBorder(JellyCastColors.text.opacity(0.85), lineWidth: 1.5))
    }
}

struct PosterCard: View {
    let ref: ImageRef?
    let caption: String
    let action: () -> Void

    @Environment(\.layout) private var layout

    private static let heightPerWidth: CGFloat = 1.5

    var body: some View {
        let width = layout.posterWidth
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                RemoteImage(ref: ref, width: width)
                    .frame(width: width, height: width * Self.heightPerWidth)
                    .clipShape(.rect(cornerRadius: 10))
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(JellyCastColors.textMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(PressedOpacityButtonStyle())
    }
}

private struct HomeSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Rectangle().fill(JellyCastColors.surface).frame(height: 300).padding(.horizontal, -20)
            RoundedRectangle(cornerRadius: 4).fill(JellyCastColors.surface).frame(width: 140, height: 22)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10).fill(JellyCastColors.surface).frame(width: 220, height: 124)
                RoundedRectangle(cornerRadius: 10).fill(JellyCastColors.surface).frame(width: 220, height: 124)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}

#Preview {
    NavigationStack {
        HomeScreen(store: LibraryStore(session: .preview, snapshot: .preview))
    }
    .environment(AppNavigation())
    .preferredColorScheme(.dark)
}
