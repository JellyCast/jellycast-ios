import SwiftUI

/// The movie detail: the backdrop with the logo and a play button, and the same info as under
/// the playing video.
struct MovieScreen: View {
    let store: LibraryStore
    let movieID: String

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.layout) private var layout
    @State private var mediaInfo: MediaInfo?
    @State private var topInset: CGFloat = 0

    var body: some View {
        Group {
            if let movie = store.index?.moviesByID[movieID] {
                content(movie)
            } else {
                ContentErrorView(message: String(localized: "This movie is no longer in the library.")) {
                    Task { await store.refresh() }
                }
            }
        }
        .background(JellyCastColors.background)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: movieID) {
            mediaInfo = try? await store.session.client.mediaInfo(itemID: movieID, userID: store.session.userID)
            await StreamCaches.shared.warmUp(itemID: movieID, session: store.session)
        }
    }

    private func content(_ movie: Movie) -> some View {
        GeometryReader { proxy in
            let isSplit = layout.isRegular && proxy.size.width > proxy.size.height
            panel(movie, arrangement: isSplit ? .split : .column)
        }
    }

    private func panel(_ movie: Movie, arrangement: InfoPanelArrangement) -> some View {
        ItemInfoPanel(
            playable: .movie(movie), mediaInfo: mediaInfo, store: store, showsTitle: false,
            arrangement: arrangement, tabBarTopClearance: topInset
        ) { selected in
            navigation.open(.movie(id: selected.id))
        } header: {
            DetailHero(backdrop: movie.backdrop ?? movie.poster, logo: movie.logo, title: movie.name) {
                HeroPlayButton(playable: .movie(movie)) { navigation.play(.movie(movie)) }
            }
        } actions: {
            PlayOnButton(playable: .movie(movie), size: 34)
            RailCircleButton(
                systemImage: movie.watch.played ? "checkmark.circle.fill" : "checkmark",
                label: movie.watch.played ? "Mark as not watched" : "Mark as watched", size: 34
            ) {
                Task { await store.setPlayed(!movie.watch.played, itemID: movie.id) }
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

/// "4K · Dolby Vision · TrueHD Atmos · PGS" from the default tracks of the file.
nonisolated enum TechLine {
    static func text(for info: MediaInfo) -> String {
        parts(for: info).joined(separator: " · ")
    }

    static func parts(for info: MediaInfo) -> [String] {
        let video = info.streams.first { $0.Type == "Video" }
        let audio = info.streams.first { $0.Type == "Audio" && $0.IsDefault == true }
            ?? info.streams.first { $0.Type == "Audio" }
        let subtitleCodecs = Set(
            info.streams.filter { $0.Type == "Subtitle" }.compactMap { $0.Codec?.lowercased() }
        )
        return [
            video.flatMap(resolution),
            video.flatMap(range),
            audio.flatMap(audioName),
            subtitleCodecs.contains("pgssub") ? "PGS" : nil,
        ].compactMap { $0 }
    }

    private static func resolution(_ stream: MediaInfo.Stream) -> String? {
        guard let height = stream.Height else { return nil }
        if height > 1100 { return "4K" }
        if height > 730 { return "1080p" }
        return height > 0 ? "\(height)p" : nil
    }

    private static func range(_ stream: MediaInfo.Stream) -> String? {
        switch stream.VideoRangeType ?? "" {
        case let type where type.hasPrefix("DOVI"): "Dolby Vision"
        case "HDR10Plus": "HDR10+"
        case "HDR10": "HDR10"
        case "HLG": "HLG"
        default: nil
        }
    }

    private static func audioName(_ stream: MediaInfo.Stream) -> String? {
        let profile = stream.Profile ?? ""
        let atmos = profile.contains("Atmos")
        switch stream.Codec?.lowercased() {
        case "truehd": return atmos ? "TrueHD Atmos" : "TrueHD"
        case "eac3": return atmos ? "Dolby Atmos" : "Dolby Digital+"
        case "ac3": return "Dolby Digital"
        case "dts": return profile.contains("MA") ? "DTS-HD MA" : profile.contains(":X") ? "DTS:X" : "DTS"
        case "aac": return (stream.Channels ?? 2) > 2 ? "AAC \(stream.Channels ?? 0)ch" : nil
        case "flac": return "FLAC"
        default: return nil
        }
    }
}
