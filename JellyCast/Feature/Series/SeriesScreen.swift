import SwiftUI

/// The series page: the backdrop with the logo and a play button for the next episode, then the
/// same info and tabs as the movie detail, with every season under Episodes.
struct SeriesScreen: View {
    let store: LibraryStore
    let seriesID: String

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.layout) private var layout
    @State private var topInset: CGFloat = 0

    var body: some View {
        Group {
            if let series = store.index?.seriesByID[seriesID], let progress = store.index?.progress(of: seriesID),
               let next = Self.playableNext(progress) {
                content(series, progress, next: next)
            } else {
                ContentErrorView(message: String(localized: "This series is no longer in the library.")) {
                    Task { await store.refresh() }
                }
            }
        }
        .background(JellyCastColors.background)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.index?.progress(of: seriesID)?.next?.id) {
            guard let next = store.index?.progress(of: seriesID)?.next else { return }
            await StreamCaches.shared.warmUp(itemID: next.id, session: store.session)
        }
    }

    private func content(_ series: Series, _ progress: SeriesProgress, next: Episode) -> some View {
        GeometryReader { proxy in
            let isSplit = layout.isRegular && proxy.size.width > proxy.size.height
            ItemInfoPanel(
                playable: .episode(next), mediaInfo: nil, store: store, showsTitle: false,
                arrangement: isSplit ? .split : .column, tabBarTopClearance: topInset, showsWholeSeries: true
            ) { selected in
                navigation.play(selected)
            } header: {
                DetailHero(backdrop: series.backdrop ?? series.poster, logo: series.logo, title: series.name) {
                    HeroPlayButton(playable: .episode(next), caption: playCaption(progress, next: next)) {
                        navigation.play(.episode(next))
                    }
                    .availableOffline(next.id)
                }
            } actions: {
                PlayOnButton(playable: .episode(next), size: 34)
                DownloadNextButton(series: series, progress: progress)
                RailCircleButton(
                    systemImage: progress.status == .watched ? "checkmark.circle.fill" : "checkmark",
                    label: progress.status == .watched ? "Mark as not watched" : "Mark as watched", size: 34
                ) {
                    Task { await store.setPlayed(progress.status != .watched, itemID: series.id) }
                }
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    /// The next episode, or the first one once all are watched.
    private static func playableNext(_ progress: SeriesProgress) -> Episode? {
        progress.next ?? progress.episodes.first { ($0.seasonNumber ?? 0) > 0 }
    }

    private func playCaption(_ progress: SeriesProgress, next: Episode) -> String {
        let episode = Format.seasonEpisode(next)
        if next.watch.isInProgress { return String(localized: "Continue · \(episode)") }
        if progress.next == nil, progress.status == .watched { return String(localized: "Watch again · \(episode)") }
        return String(localized: "Play · \(episode)")
    }
}

/// Every season of a series as chips, with the chosen season's episodes under them.
struct SeriesEpisodesTab: View {
    let progress: SeriesProgress
    let series: Series?
    let margin: CGFloat
    var isLarge = false
    let onPlay: (Episode) -> Void
    let onSetPlayed: (Episode, Bool) -> Void

    @State private var selectedSeason: Int?
    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    @Environment(\.isOffline) private var isOffline

    var body: some View {
        let season = selectedSeason ?? defaultSeason
        VStack(alignment: .leading, spacing: 4) {
            SeasonChips(
                seasons: progress.seasons, selection: season, margin: margin,
                poster: progress.episodes.first?.seriesPoster, actions: seasonActions
            ) {
                selectedSeason = $0
            }
            .padding(.horizontal, -margin)
            .padding(.bottom, 6)
            EpisodeInfoList(
                episodes: progress.episodes.filter { ($0.seasonNumber ?? 0) == season }, series: series,
                nextID: progress.next?.id, isLarge: isLarge, onSelect: onPlay, onSetPlayed: onSetPlayed
            )
            .padding(.top, 8)
        }
    }

    private var defaultSeason: Int {
        progress.next?.seasonNumber ?? progress.seasons.first?.number ?? 1
    }

    private func seasonActions(_ season: SeasonSummary) -> [DrawerAction] {
        guard let navigation, !isOffline else { return [] }
        let episodes = progress.episodes.filter { ($0.seasonNumber ?? 0) == season.number }
        let title = Format.joined([episodes.first?.seriesName, SeasonChips.title(of: season)])
        return [DrawerAction(title: String(localized: "Add season to list…"), systemImage: "text.badge.plus") {
            navigation.addToList(title, itemIDs: episodes.map(\.id))
        }]
    }
}

struct ExpandableText: View {
    let text: String

    @State private var isExpanded = false

    private static let collapsedLines = 3

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(JellyCastColors.textMuted)
            .lineLimit(isExpanded ? nil : Self.collapsedLines)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onTapGesture { isExpanded.toggle() }
    }
}

private struct SeasonChips: View {
    let seasons: [SeasonSummary]
    let selection: Int
    let margin: CGFloat
    let poster: ImageRef?
    let actions: (SeasonSummary) -> [DrawerAction]
    let onSelect: (Int) -> Void

    static func title(of season: SeasonSummary) -> String {
        season.number == 0 ? String(localized: "Specials") : String(localized: "Season \(season.number)")
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(seasons) { season in chip(season).id(season.number) }
                }
                .padding(.horizontal, margin)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
    }

    private func chip(_ season: SeasonSummary) -> some View {
        let isSelected = season.number == selection
        return Button { onSelect(season.number) } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Text(Self.title(of: season)).fontWeight(.bold)
                    Text("\(season.watchedCount)/\(season.episodeCount)").opacity(0.6)
                } else {
                    Text(season.number == 0 ? String(localized: "Specials") : "S\(season.number)")
                        .fontWeight(.medium)
                    if season.isWatched { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                }
            }
            .font(.subheadline)
            .foregroundStyle(
                isSelected ? JellyCastColors.background
                    : season.isWatched ? JellyCastColors.textMuted : JellyCastColors.text
            )
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(isSelected ? JellyCastColors.text : JellyCastColors.rail, in: .capsule)
        }
        .buttonStyle(PressedOpacityButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .seasonDrawer(DrawerHeader(title: Self.title(of: season), image: poster), actions: actions(season))
    }
}

private extension View {
    @ViewBuilder
    func seasonDrawer(_ header: DrawerHeader, actions: [DrawerAction]) -> some View {
        if actions.isEmpty {
            self
        } else {
            actionDrawer(header, actions: actions)
        }
    }
}
