import SwiftUI

/// Sizes of one tile; the iPhone's small tiles are a step smaller than the iPad's.
struct HomeTileStyle {
    let isFeatured: Bool
    let isPhone: Bool

    private static let lineHeightPerPoint: CGFloat = 1.25

    var cornerRadius: CGFloat { isFeatured ? 12 : 10 }
    var progressHeight: CGFloat { isFeatured ? 5 : (isPhone ? 3 : 4) }
    var isSmallPhone: Bool { isPhone && !isFeatured }

    var titleSize: CGFloat {
        if isFeatured { return isPhone ? 20 : 22 }
        return isPhone ? 15 : 16
    }

    var metaSize: CGFloat {
        if isFeatured { return isPhone ? 15 : 16 }
        return isPhone ? 13 : 14
    }

    var titleFont: Font { .system(size: titleSize, weight: isFeatured ? .bold : .semibold) }
    var metaFont: Font { .system(size: metaSize) }
    var imageToTitle: CGFloat { isFeatured ? 12 : 10 }
    var titleToMeta: CGFloat { isFeatured ? 4 : 2 }
    var titleLineHeight: CGFloat { (titleSize * Self.lineHeightPerPoint).rounded(.up) }
    var metaLineHeight: CGFloat { (metaSize * Self.lineHeightPerPoint).rounded(.up) }
}

/// A 16:9 image with the title and one meta line under it, as on YouTube.
struct HomeTile: View {
    let item: HomeItem
    let index: LibraryIndex
    let size: HomeTileSize
    let style: HomeTileStyle

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                HomeTileImage(item: item, index: index, size: size, style: style)
                Text(item.title)
                    .font(style.titleFont)
                    .foregroundStyle(JellyCastColors.text)
                    .frame(height: style.titleLineHeight)
                    .padding(.top, style.imageToTitle)
                Text(item.meta(index))
                    .font(style.metaFont)
                    .foregroundStyle(JellyCastColors.textMuted)
                    .frame(height: style.metaLineHeight)
                    .padding(.top, style.titleToMeta)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: size.width, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(PressedOpacityButtonStyle())
        .mediaContextMenu(item.target, index: index)
        .availableOffline(item.offlineID)
    }

    private func open() {
        switch item {
        case .continueWatching(.movie(let movie)): navigation.open(.movie(id: movie.id))
        case .continueWatching(.episode(let episode)): navigation.open(.series(id: episode.seriesID))
        case .newMovie(let movie), .notStartedMovie(let movie): navigation.open(.movie(id: movie.id))
        case .newEpisodes(let series, _, _, _), .notStartedSeries(let series):
            navigation.open(.series(id: series.id))
        }
    }
}

private struct HomeTileImage: View {
    let item: HomeItem
    let index: LibraryIndex
    let size: HomeTileSize
    let style: HomeTileStyle

    private static let badgeInsetPhone: CGFloat = 8
    private static let badgeInset: CGFloat = 10

    var body: some View {
        let inset = style.isPhone ? Self.badgeInsetPhone : Self.badgeInset
        RemoteImage(ref: item.image, type: item.imageType, width: size.width)
            .frame(width: size.width, height: size.imageHeight)
            .frame(maxHeight: size.imageHeight == nil ? .infinity : nil)
            .overlay(alignment: .topLeading) {
                if let label = item.label {
                    TileLabel(label: label, isPhone: style.isPhone).padding(inset)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let time = timeLabel {
                    TimeBadge(text: time, isSmallPhone: style.isSmallPhone)
                        .padding(.trailing, inset)
                        .padding(.bottom, inset + (item.progress == nil ? 0 : style.progressHeight))
                }
            }
            .overlay(alignment: .bottom) {
                if let progress = item.progress {
                    WatchProgressBar(
                        progress: progress, height: style.progressHeight,
                        track: .white.opacity(0.2)
                    )
                }
            }
            .clipShape(.rect(cornerRadius: style.cornerRadius))
    }

    /// The iPhone's tiles are too small to carry a runtime as well; only the time left stays.
    private var timeLabel: String? {
        if style.isPhone, item.progress == nil { return nil }
        return item.timeLabel(index)
    }
}

/// "nog 18 min", "1 u 52 min" or "16 afl." on the image.
private struct TimeBadge: View {
    let text: String
    let isSmallPhone: Bool

    var body: some View {
        Text(text)
            .font(.system(size: isSmallPhone ? 12 : 13, weight: .semibold))
            .foregroundStyle(JellyCastColors.text)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                JellyCastColors.background.opacity(0.8),
                in: .rect(cornerRadius: isSmallPhone ? 5 : 6)
            )
    }
}

enum HomeTileLabel {
    case new, notStarted

    var text: LocalizedStringKey {
        switch self {
        case .new: "New"
        case .notStarted: "Not watched yet"
        }
    }
}

/// "NIEUW" or "NOG NIET GEZIEN": bold on the iPad, quiet on the iPhone's smaller images.
private struct TileLabel: View {
    let label: HomeTileLabel
    let isPhone: Bool

    private static let trackingPerPointPhone: CGFloat = 0.05
    private static let trackingPerPoint: CGFloat = 0.06

    var body: some View {
        let fontSize: CGFloat = isPhone ? 10 : 12
        let radius: CGFloat = isPhone ? 4 : 6
        Text(label.text)
            .font(.system(size: fontSize, weight: weight))
            .tracking(fontSize * (isPhone ? Self.trackingPerPointPhone : Self.trackingPerPoint))
            .textCase(.uppercase)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, isPhone ? 5 : 8)
            .frame(height: isPhone ? 16 : 22)
            .background(background, in: .rect(cornerRadius: radius))
            .overlay {
                if !isPhone, label == .notStarted {
                    RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.2), lineWidth: 1)
                }
            }
    }

    private var weight: Font.Weight {
        isPhone && label == .notStarted ? .semibold : .bold
    }

    private var foreground: Color {
        switch (label, isPhone) {
        case (.new, true): JellyCastColors.accent
        case (.new, false): JellyCastColors.onAccent
        case (.notStarted, true): JellyCastColors.text.opacity(0.8)
        case (.notStarted, false): JellyCastColors.text
        }
    }

    private var background: Color {
        switch (label, isPhone) {
        case (_, true): JellyCastColors.background.opacity(0.7)
        case (.new, false): JellyCastColors.accent
        case (.notStarted, false): JellyCastColors.background.opacity(0.8)
        }
    }
}

extension HomeItem {
    var title: String {
        switch self {
        case .continueWatching(.episode(let episode)): episode.seriesName
        case .continueWatching(.movie(let movie)), .newMovie(let movie), .notStartedMovie(let movie):
            movie.name
        case .newEpisodes(let series, _, _, _), .notStartedSeries(let series): series.name
        }
    }

    /// "S2 · E7 · Episode name", "Film · 2001", "Serie · 2 seizoenen". The season and episode
    /// come first so a long name is what gets cut.
    func meta(_ index: LibraryIndex) -> String {
        switch self {
        case .continueWatching(.episode(let episode)):
            return Format.joined([Format.seasonEpisode(episode), episode.name])
        case .continueWatching(.movie(let movie)), .newMovie(let movie), .notStartedMovie(let movie):
            return Format.joined([String(localized: "Movie"), movie.year.map(String.init)])
        case .newEpisodes(_, let firstNew, let count, let isNewSeason):
            let what = if isNewSeason {
                String(localized: "new season")
            } else if count == 1 {
                String(localized: "new episode")
            } else {
                String(localized: "\(count) new episodes")
            }
            return Format.joined([firstNew.map(Format.seasonEpisode), what])
        case .notStartedSeries(let series):
            let seasons = index.progress(of: series.id)?.seasons.count { $0.number > 0 } ?? 0
            return String(localized: "Series · \(seasons) seasons")
        }
    }

    /// The time left while in progress, otherwise the runtime; the episode count for a series.
    func timeLabel(_ index: LibraryIndex) -> String? {
        switch self {
        case .continueWatching(let playable):
            return Format.timeLabel(playable)
        case .newMovie(let movie), .notStartedMovie(let movie):
            return Format.runtime(movie.runtimeTicks)
        case .newEpisodes(_, let firstNew, let count, _):
            return count == 1 ? Format.runtime(firstNew?.runtimeTicks) : Self.episodeCount(count)
        case .notStartedSeries(let series):
            let count = index.progress(of: series.id)?.episodes.count { ($0.seasonNumber ?? 0) > 0 } ?? 0
            return count > 0 ? Self.episodeCount(count) : nil
        }
    }

    private static func episodeCount(_ count: Int) -> String {
        String(localized: "\(count) eps.")
    }

    var label: HomeTileLabel? {
        switch self {
        case .continueWatching: nil
        case .newMovie, .newEpisodes: .new
        case .notStartedSeries, .notStartedMovie: .notStarted
        }
    }

    var progress: Double? {
        guard case .continueWatching(let playable) = self else { return nil }
        return playable.progress
    }

    var image: ImageRef? { art.ref }

    var imageType: JellyfinClient.ImageType { art.type }

    /// The season's thumb when it has one, else the series' backdrop: never an episode still.
    private var art: (ref: ImageRef?, type: JellyfinClient.ImageType) {
        switch self {
        case .continueWatching(.episode(let episode)):
            Self.art(season: episode.seasonThumb, backdrop: episode.seriesBackdrop, poster: episode.seriesPoster)
        case .continueWatching(.movie(let movie)), .newMovie(let movie), .notStartedMovie(let movie):
            Self.art(season: nil, backdrop: movie.backdrop, poster: movie.poster)
        case .newEpisodes(let series, let firstNew, _, _):
            Self.art(season: firstNew?.seasonThumb, backdrop: series.backdrop, poster: series.poster)
        case .notStartedSeries(let series):
            Self.art(season: nil, backdrop: series.backdrop, poster: series.poster)
        }
    }

    private static func art(
        season: ImageRef?, backdrop: ImageRef?, poster: ImageRef?
    ) -> (ref: ImageRef?, type: JellyfinClient.ImageType) {
        if let season { return (season, .thumb) }
        if let backdrop { return (backdrop, .backdrop) }
        return (poster, .primary)
    }

    var target: MediaTarget {
        switch self {
        case .continueWatching(let playable): MediaTarget(playable)
        case .newMovie(let movie), .notStartedMovie(let movie): .movie(movie)
        case .newEpisodes(let series, _, _, _), .notStartedSeries(let series): .series(series)
        }
    }

    var offlineID: String {
        if case .continueWatching(let playable) = self { return playable.id }
        return id
    }
}
