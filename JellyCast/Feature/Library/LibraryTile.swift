import SwiftUI

/// A poster with the title and year under it; the status shows on the poster.
struct LibraryTile: View {
    let entry: LibraryEntry
    let index: LibraryIndex

    @Environment(AppNavigation.self) private var navigation

    private static let heightPerWidth: CGFloat = 1.5

    var body: some View {
        Button { navigation.open(route) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Color.clear
                    .aspectRatio(1 / Self.heightPerWidth, contentMode: .fit)
                    .overlay {
                        GeometryReader { proxy in
                            RemoteImage(ref: entry.poster, width: proxy.size.width)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if entry.status == .watched { WatchedMark().padding(6) }
                    }
                    .overlay(alignment: .bottom) {
                        if let progress { WatchProgressBar.onImage(progress).padding(6) }
                    }
                    .clipShape(.rect(cornerRadius: 8))
                    .padding(.bottom, 2)
                Text(entry.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(JellyCastColors.text)
                    .lineLimit(1)
                if let year = entry.year {
                    Text(String(year))
                        .font(.caption)
                        .foregroundStyle(JellyCastColors.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(.rect)
        }
        .buttonStyle(PressedOpacityButtonStyle())
        .mediaContextMenu(MediaTarget(entry), index: index)
        .availableOffline(entry.id)
    }

    private var route: Route {
        switch entry.item {
        case .movie(let movie): .movie(id: movie.id)
        case .series(let series): .series(id: series.id)
        }
    }

    private var progress: Double? {
        guard case .movie(let movie) = entry.item else { return nil }
        return Playable.movie(movie).progress
    }
}

private struct WatchedMark: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.caption.weight(.bold))
            .foregroundStyle(JellyCastColors.text)
            .frame(width: 26, height: 26)
            .background(JellyCastColors.background.opacity(0.72), in: .circle)
            .accessibilityLabel("Watched")
    }
}
