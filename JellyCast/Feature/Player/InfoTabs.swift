import SwiftUI

/// The tabs under the info of a movie or episode.
enum InfoTab: Hashable {
    case episodes, cast, related, chat

    static func available(for playable: Playable, chatEnabled: Bool) -> [InfoTab] {
        let base: [InfoTab] = switch playable {
        case .episode: [.episodes, .cast]
        case .movie: [.cast, .related]
        }
        return chatEnabled ? base + [.chat] : base
    }

    var title: LocalizedStringKey {
        switch self {
        case .episodes: "Episodes"
        case .cast: "Cast"
        case .related: "Related"
        case .chat: "Chat"
        }
    }
}

/// A row of capsule tabs, like the segmented kind picker in the library, with a sparkle on Chat.
struct InfoTabBar: View {
    let tabs: [InfoTab]
    @Binding var selection: InfoTab

    static let height: CGFloat = 40
    private static let inset: CGFloat = 3
    private static let selectedFill = Color(white: 0.35)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 5) {
                        if tab == .chat {
                            Image(systemName: "sparkle")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(JellyCastColors.accent)
                        }
                        Text(tab.title)
                            .font(.subheadline.weight(tab == selection ? .semibold : .medium))
                            .foregroundStyle(JellyCastColors.text)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if tab == selection { Capsule().fill(Self.selectedFill) }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(PressedOpacityButtonStyle())
                .accessibilityAddTraits(tab == selection ? .isSelected : [])
            }
        }
        .padding(Self.inset)
        .frame(height: Self.height)
        .background(JellyCastColors.rail, in: .capsule)
    }
}

/// Episodes, each with its overview, rating site link and rating: around the one playing in the player,
/// a whole season on the series page.
struct EpisodeInfoList: View {
    let episodes: [Episode]
    /// For the TMDB links, which go through the series.
    let series: Series?
    var playingID: String?
    /// The series page's next episode, outlined like the one playing.
    var nextID: String?
    /// Set while a TV plays it, so the row says where.
    var playingOn: String?
    var isLarge = false
    let onSelect: (Episode) -> Void
    let onSetPlayed: (Episode, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(episodes) { episode in
                EpisodeInfoRow(
                    episode: episode, series: series, isPlaying: episode.id == playingID,
                    isNext: episode.id == nextID,
                    playingOn: playingOn, isLarge: isLarge
                ) {
                    if episode.id != playingID { onSelect(episode) }
                } onSetPlayed: { onSetPlayed(episode, $0) }
                .availableOffline(episode.id)
            }
        }
    }
}

private struct EpisodeInfoRow: View {
    let episode: Episode
    let series: Series?
    let isPlaying: Bool
    let isNext: Bool
    let playingOn: String?
    let isLarge: Bool
    let onPlay: () -> Void
    let onSetPlayed: (Bool) -> Void

    /// Missing in the player, which is presented outside the tabs.
    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    @Environment(\.isOffline) private var isOffline

    private static let stillAspectRatio: CGFloat = 16 / 9
    private static let watchedImageOpacity = 0.55
    private static let overviewLines = 3

    private var stillWidth: CGFloat { isLarge ? 192 : 136 }

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: isLarge ? .top : .center, spacing: isLarge ? 16 : 12) {
                    still
                    VStack(alignment: .leading, spacing: 3) {
                        titleLines
                        if isLarge, let overview = episode.overview { overviewText(overview).padding(.top, 3) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        if episode.watch.played && !isPlaying {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(JellyCastColors.textMuted)
                        }
                    }
                    .frame(width: 28)
                    DownloadButton(playable: .episode(episode))
                }
                if !isLarge, let overview = episode.overview { overviewText(overview) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressedOpacityButtonStyle())
        .actionDrawer(
            DrawerHeader(
                title: episode.name,
                subtitle: Format.seasonEpisode(episode),
                image: episode.still ?? episode.seriesBackdrop,
                imageType: episode.still == nil ? .backdrop : .primary,
                isWide: true
            ),
            actions: drawerActions
        )
    }

    private var drawerActions: [DrawerAction] {
        var actions = WatchedActions.make(status: WatchedActions.status(of: episode.watch), setPlayed: onSetPlayed)
        if let navigation, !isOffline {
            let title = Format.joined([episode.seriesName, Format.seasonEpisode(episode)])
            actions.append(DrawerAction(title: String(localized: "Add to list…"), systemImage: "text.badge.plus") {
                navigation.addToList(title, itemIDs: [episode.id])
            })
        }
        return actions
    }

    private var still: some View {
        let playable = Playable.episode(episode)
        return ZStack(alignment: .bottom) {
            RemoteImage(
                ref: episode.still ?? episode.seriesBackdrop,
                type: episode.still == nil ? .backdrop : .primary,
                width: stillWidth
            )
            if let progress = playable.progress {
                WatchProgressBar.onImage(progress).padding(.horizontal, 8).padding(.bottom, 6)
            }
        }
        .frame(width: stillWidth, height: stillWidth / Self.stillAspectRatio)
        .opacity(episode.watch.played && !isPlaying ? Self.watchedImageOpacity : 1)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            if isPlaying || isNext {
                RoundedRectangle(cornerRadius: 8).strokeBorder(JellyCastColors.accent, lineWidth: 2)
            }
        }
    }

    @ViewBuilder
    private var titleLines: some View {
        Text(episode.episodeNumber.map { "\($0). \(episode.name)" } ?? episode.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(episode.watch.played && !isPlaying ? JellyCastColors.textMuted : JellyCastColors.text)
            .lineLimit(2)
        if !statusLine.isEmpty {
            Text(statusLine)
                .font(.footnote.weight(isPlaying ? .semibold : .regular))
                .foregroundStyle(
                    isPlaying || episode.watch.isInProgress ? JellyCastColors.accent : JellyCastColors.textMuted
                )
                .lineLimit(1)
        }
        let source = RatingSettings.shared.source
        let title = ExternalTitle(episode, series: series)
        let url = source.url(of: title)
        let rating = source.rating(of: title)
        if url != nil || rating != nil {
            HStack(spacing: 10) {
                if let url { InlineExternalLink(source: source, url: url) }
                if let rating {
                    Text(verbatim: rating).font(.footnote).foregroundStyle(JellyCastColors.textMuted)
                }
            }
            .padding(.top, 2)
        }
    }

    private func overviewText(_ overview: String) -> some View {
        Text(overview)
            .font(.footnote)
            .foregroundStyle(isPlaying ? JellyCastColors.text : JellyCastColors.textMuted)
            .lineLimit(Self.overviewLines)
            .multilineTextAlignment(.leading)
    }

    private var statusLine: String {
        let playable = Playable.episode(episode)
        if isPlaying {
            if let playingOn { return String(localized: "Playing on \(playingOn)") }
            return Format.joined([String(localized: "Playing now"), Format.remaining(playable.remainingTicks)])
        }
        if episode.watch.played {
            return Format.joined([String(localized: "Watched"), Format.runtime(episode.runtimeTicks)])
        }
        if episode.watch.isInProgress { return Format.remaining(playable.remainingTicks) ?? "" }
        return Format.runtime(episode.runtimeTicks) ?? ""
    }
}

/// "IMDb ↗" or another site as small text, for rows where a capsule would be too heavy.
struct InlineExternalLink: View {
    let source: RatingSource
    let url: URL

    var body: some View {
        Link(destination: url) {
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
