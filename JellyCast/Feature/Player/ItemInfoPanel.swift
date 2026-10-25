import SwiftUI

/// How the info panel is laid out: one scrolling column, or (landscape on the iPad) the header
/// and summary on the left with the episodes, cast and related titles scrolling on the right.
enum InfoPanelArrangement {
    case column, split

    /// The share of the width the left side gets in the split.
    static let splitLeadingFraction: CGFloat = 0.645
}

/// Under the video in the player, and under the image on the movie detail: what it is, then tabs
/// with the episodes, cast, related titles and the chat.
struct ItemInfoPanel<Header: View, Actions: View>: View {
    let playable: Playable
    let mediaInfo: MediaInfo?
    let store: LibraryStore
    var showsTitle = true
    var arrangement = InfoPanelArrangement.column
    /// Set while a TV plays it, so the episode list says where.
    var playingOn: String?
    /// Room to keep free above the tab bar when a tab scrolls it up, where the panel runs under
    /// the navigation bar.
    var tabBarTopClearance: CGFloat = 0
    /// The series page: every season under Episodes, the series' own cast, and its meta line.
    var showsWholeSeries = false
    /// Raised by the header above the column to bring the column back to its top.
    var scrollToTopRequest = 0
    /// Told when the column scrolls away from its top and back, so a header above it can shrink.
    var onScrolledDown: ((Bool) -> Void)?
    let onSelect: (Playable) -> Void
    @ViewBuilder var header: Header
    @ViewBuilder var actions: Actions

    @Environment(\.layout) private var layout
    @State private var extras: ItemExtras?
    @State private var selectedTab: InfoTab?
    @State private var chat = ChatModel()
    @FocusState private var isChatFocused: Bool
    @State private var viewportHeight: CGFloat = 0
    @State private var tabBarY: CGFloat = 0
    @State private var scrollPosition = ScrollPosition()
    @State private var isScrolledDown = false
    @State private var visibleHeight: CGFloat = 0
    @State private var chatEndY: CGFloat = 0
    /// Set when a message or step arrives; the scroll waits for the conversation's new end.
    @State private var scrollsToChatEnd = false
    /// Measured once the field shows; the estimate covers the first switch to the chat.
    @State private var chatInputHeight: CGFloat = 66

    private static var episodesBefore: Int { 1 }
    private static var episodesAfter: Int { 6 }
    private static var splitTrailingPadding: CGFloat { 24 }
    private static var chatEndID: String { "chatEnd" }
    private static var contentSpace: String { "panelContent" }
    /// The tab bar and the gaps around it, so a short tab can still scroll the bar to the top.
    private static var tabBarSpace: CGFloat { 72 }
    /// Apart, so a header that changes size while it scrolls doesn't flip back and forth.
    private static var scrolledDownOffset: CGFloat { 60 }
    private static var backAtTopOffset: CGFloat { 16 }

    var body: some View {
        Group {
            switch arrangement {
            case .column: column
            case .split: split
            }
        }
        .task(id: playable.id) { await loadExtras() }
    }

    private var column: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 22) {
                    summary.frame(maxWidth: layout.textMaxWidth, alignment: .leading)
                    InfoTabBar(tabs: tabs, selection: scrollingTabSelection)
                        .frame(maxWidth: layout.textMaxWidth)
                        .padding(.top, 6)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.frame(in: .named(Self.contentSpace)).minY
                        } action: { tabBarY = $0 }
                    tabContent(isLarge: layout.isRegular, margin: layout.margin)
                        .frame(minHeight: tabMinHeight, alignment: .top)
                }
                .padding(.horizontal, layout.margin)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .coordinateSpace(.named(Self.contentSpace))
        }
        .scrollPosition($scrollPosition)
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.y + $0.contentInsets.top
        } action: { _, offset in
            updateScrolledDown(offset: offset)
        }
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.containerSize.height - $0.contentInsets.top - $0.contentInsets.bottom
        } action: { _, height in
            visibleHeight = height
        }
        .dismissesKeyboard($isChatFocused)
        .safeAreaInset(edge: .bottom) { chatInput(margin: layout.margin) }
        .onChange(of: chat.messages.count) { scrollsToChatEnd = true }
        .onChange(of: chat.steps.count) { scrollsToChatEnd = true }
        .onChange(of: chatEndY) { scrollColumnToChatEnd() }
        .onChange(of: scrollToTopRequest) {
            withAnimation(.smooth(duration: 0.4)) { scrollPosition.scrollTo(edge: .top) }
        }
    }

    /// Never above the tab bar: a short conversation would otherwise pull the page back to its top.
    private func scrollColumnToChatEnd() {
        guard scrollsToChatEnd else { return }
        scrollsToChatEnd = false
        guard currentTab == .chat else { return }
        let target = max(tabBarY - tabBarTopClearance, chatEndY - visibleHeight)
        withAnimation { scrollPosition.scrollTo(y: target) }
    }

    private var split: some View {
        GeometryReader { proxy in
            let leadingWidth = (proxy.size.width * InfoPanelArrangement.splitLeadingFraction).rounded()
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        summary
                            .padding(.horizontal, layout.margin)
                            .padding(.top, 18)
                            .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(width: leadingWidth)
                VStack(spacing: 0) {
                    InfoTabBar(tabs: tabs, selection: tabSelection)
                        .padding(.horizontal, Self.splitTrailingPadding)
                        .padding(.top, 18 + tabBarTopClearance)
                        .padding(.bottom, 8)
                    ScrollViewReader { scroll in
                        ScrollView {
                            tabContent(isLarge: false, margin: Self.splitTrailingPadding)
                                .padding(.horizontal, Self.splitTrailingPadding)
                                .padding(.top, 10)
                                .padding(.bottom, 40)
                        }
                        .scrollIndicators(.hidden)
                        .dismissesKeyboard($isChatFocused)
                        .onChange(of: chat.messages.count) { scrollToChatEnd(scroll) }
                        .onChange(of: chat.steps.count) { scrollToChatEnd(scroll) }
                    }
                    .safeAreaInset(edge: .bottom) { chatInput(margin: Self.splitTrailingPadding) }
                }
            }
        }
    }

    private func updateScrolledDown(offset: CGFloat) {
        guard let onScrolledDown else { return }
        let scrolledDown = isScrolledDown ? offset > Self.backAtTopOffset : offset > Self.scrolledDownOffset
        guard scrolledDown != isScrolledDown else { return }
        isScrolledDown = scrolledDown
        onScrolledDown(scrolledDown)
    }

    private var tabs: [InfoTab] {
        InfoTab.available(for: playable, chatEnabled: ChatSettings.shared.hasKey)
    }

    private var currentTab: InfoTab {
        if let selectedTab, tabs.contains(selectedTab) { return selectedTab }
        return tabs.first ?? .cast
    }

    private var tabSelection: Binding<InfoTab> {
        Binding { currentTab } set: { selectedTab = $0 }
    }

    /// Tall enough that the tab bar can scroll up to the top, also above the chat's question field.
    private var tabMinHeight: CGFloat {
        let inset = currentTab == .chat ? chatInputHeight : 0
        return max(0, viewportHeight - Self.tabBarSpace - tabBarTopClearance + inset)
    }

    /// Choosing a tab scrolls the bar up to just under the video or image, so the tab has room.
    private var scrollingTabSelection: Binding<InfoTab> {
        Binding { currentTab } set: { tab in
            selectedTab = tab
            let target = max(0, tabBarY - tabBarTopClearance)
            withAnimation(.easeInOut(duration: 0.25)) { scrollPosition.scrollTo(y: target) }
        }
    }

    @ViewBuilder
    private func tabContent(isLarge: Bool, margin: CGFloat) -> some View {
        switch currentTab {
        case .episodes:
            if showsWholeSeries, case .episode(let episode) = playable,
               let progress = store.index?.progress(of: episode.seriesID) {
                SeriesEpisodesTab(
                    progress: progress, series: series, margin: margin, isLarge: isLarge
                ) { candidate in
                    onSelect(.episode(candidate))
                } onSetPlayed: { candidate, played in
                    Task { await store.setPlayed(played, itemID: candidate.id) }
                }
            } else if case .episode(let episode) = playable {
                EpisodeInfoList(
                    episodes: episodeWindow(around: episode), series: series, playingID: episode.id,
                    playingOn: playingOn, isLarge: isLarge
                ) { candidate in
                    onSelect(.episode(candidate))
                } onSetPlayed: { candidate, played in
                    Task { await store.setPlayed(played, itemID: candidate.id) }
                }
            }
        case .cast:
            CastTab(playable: playable, store: store, wholeSeries: showsWholeSeries).frame(maxWidth: layout.textMaxWidth, alignment: .leading)
        case .related:
            if case .movie(let movie) = playable { relatedTab(movie) }
        case .chat:
            VStack(alignment: .leading, spacing: 0) {
                ChatTab(playable: playable, store: store, model: chat)
                Color.clear.frame(height: 1).id(Self.chatEndID)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.frame(in: .named(Self.contentSpace)).maxY
                    } action: { chatEndY = $0 }
            }
            .frame(maxWidth: layout.textMaxWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private func chatInput(margin: CGFloat) -> some View {
        if currentTab == .chat {
            ChatInputBar(title: title, isSending: chat.isSending, isFocused: $isChatFocused) { question in
                chat.send(question, about: playable, store: store)
            }
            .frame(maxWidth: layout.textMaxWidth)
            .padding(.horizontal, margin)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JellyCastColors.background)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chatInputHeight = $0 }
        }
    }

    private func scrollToChatEnd(_ proxy: ScrollViewProxy) {
        guard currentTab == .chat else { return }
        withAnimation { proxy.scrollTo(Self.chatEndID, anchor: .bottom) }
    }


    private func relatedTab(_ movie: Movie) -> some View {
        let collection = store.index?.collection(of: movie) ?? []
        return RelatedTab(
            collectionTitle: RelatedMovies.collectionTitle(of: [movie.name] + collection.map(\.name)),
            collection: collection,
            related: extras?.related,
            onSelect: onSelect
        )
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading
            if let overview { ExpandableText(text: overview) }
            HStack(spacing: 10) {
                if let titleURL { ExternalLink(source: ratingSource, url: titleURL) }
                if let rating = ratingSource.rating(of: summaryTitle) {
                    Text(verbatim: rating).font(.footnote).foregroundStyle(JellyCastColors.textMuted)
                }
                actions
                if !showsWholeSeries { DownloadButton(playable: playable) }
            }
        }
    }

    private var series: Series? {
        guard case .episode(let episode) = playable else { return nil }
        return store.index?.seriesByID[episode.seriesID]
    }

    private var ratingSource: RatingSource { RatingSettings.shared.source }

    /// For an episode the series: the episode's own link and rating are in the episode list.
    private var summaryTitle: ExternalTitle {
        switch playable {
        case .movie(let movie): ExternalTitle(movie)
        case .episode(let episode): series.map(ExternalTitle.init) ?? ExternalTitle(episode, series: nil)
        }
    }

    private var titleURL: URL? {
        if case .episode = playable, series == nil { return nil }
        return ratingSource.url(of: summaryTitle)
    }

    /// An episode is titled by its series: its own name is in the episode list.
    private var title: String {
        switch playable {
        case .movie(let movie): movie.name
        case .episode(let episode): episode.seriesName
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                Text(title)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(JellyCastColors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(meta)
                .font(.subheadline)
                .foregroundStyle(JellyCastColors.textMuted)
            if !showsWholeSeries {
                TechBadges(parts: mediaInfo.map(TechLine.parts(for:)) ?? [])
                    .padding(.top, 2)
            }
        }
    }

    /// The episode before this one and the next few, across season ends.
    private func episodeWindow(around episode: Episode) -> [Episode] {
        let regular = (store.index?.progress(of: episode.seriesID)?.episodes ?? [])
            .filter { ($0.seasonNumber ?? 0) > 0 }
        guard let position = regular.firstIndex(where: { $0.id == episode.id }) else { return [episode] }
        let start = max(0, position - Self.episodesBefore)
        let end = min(regular.count, position + Self.episodesAfter + 1)
        return Array(regular[start..<end])
    }

    /// For an episode the series text: the episode's own text and link are in the episode list.
    private var overview: String? {
        switch playable {
        case .movie(let movie): movie.overview
        case .episode: series?.overview
        }
    }

    private var meta: String {
        switch playable {
        case .movie(let movie):
            return Format.joined([
                movie.year.map(String.init),
                Format.runtime(movie.runtimeTicks),
                Genres.displayNames(movie.genres).prefix(2).joined(separator: ", "),
                movie.officialRating,
            ])
        case .episode(let episode) where showsWholeSeries:
            let series = store.index?.seriesByID[episode.seriesID]
            let seasons = store.index?.progress(of: episode.seriesID)?.seasons.count { $0.number > 0 } ?? 0
            return Format.joined([
                series?.year.map(String.init),
                String(localized: "\(seasons) seasons"),
                series.map { Genres.displayNames($0.genres).prefix(2).joined(separator: ", ") },
                series?.officialRating,
            ])
        case .episode(let episode):
            let series = store.index?.seriesByID[episode.seriesID]
            return Format.joined([
                Format.seasonEpisode(episode),
                Format.runtime(episode.runtimeTicks),
                series.map { Genres.displayNames($0.genres).prefix(2).joined(separator: ", ") },
                series?.officialRating,
                ratingSource.rating(of: ExternalTitle(episode, series: series)),
            ])
        }
    }

    private func loadExtras() async {
        extras = nil
        let session = store.session
        let itemID = playable.id
        guard let details = try? await session.client.itemDetails(itemID: itemID, userID: session.userID)
        else { return }
        guard case .movie(let movie) = playable, let index = store.index else {
            extras = ItemExtras(details: details, related: [])
            return
        }
        extras = ItemExtras(details: details, related: nil)
        let candidates = (try? await session.client.similarMovies(itemID: itemID, userID: session.userID)) ?? []
        let excluded = Set([movie.id] + index.collection(of: movie).map(\.id))
        let related = RelatedMovies.groupedByCollection(
            RelatedMovies.rank(candidates, to: details, excluding: excluded).compactMap { index.moviesByID[$0] }
        )
        guard !Task.isCancelled else { return }
        extras = ItemExtras(details: details, related: related)
    }
}

private struct ItemExtras {
    let details: ItemDetails
    /// Nil while the related movies are still loading.
    let related: [Movie]?
}

#Preview {
    let store = LibraryStore(session: .preview, snapshot: .preview)
    ItemInfoPanel(
        playable: .movie(LibrarySnapshot.preview.movies[0]), mediaInfo: nil, store: store
    ) { _ in }
    .background(JellyCastColors.background)
    .preferredColorScheme(.dark)
}

extension ItemInfoPanel where Header == EmptyView, Actions == EmptyView {
    init(playable: Playable, mediaInfo: MediaInfo?, store: LibraryStore, onSelect: @escaping (Playable) -> Void) {
        self.init(playable: playable, mediaInfo: mediaInfo, store: store, onSelect: onSelect) {
            EmptyView()
        } actions: {
            EmptyView()
        }
    }
}
