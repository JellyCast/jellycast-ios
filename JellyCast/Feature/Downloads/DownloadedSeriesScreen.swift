import SwiftUI

/// The downloaded episodes of one series, in order; a tap plays one.
struct DownloadedSeriesScreen: View {
    let store: LibraryStore
    let seriesID: String

    @Environment(AppNavigation.self) private var navigation

    private static let stillSize = CGSize(width: 136, height: 76.5)

    var body: some View {
        List {
            ForEach(episodes, id: \.download.id) { item in
                Button {
                    navigation.play(.episode(item.episode))
                } label: {
                    row(item.episode, download: item.download)
                }
                .buttonStyle(PressedOpacityButtonStyle())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                .swipeActions {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        DownloadStore.shared.remove(item.download.id)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(JellyCastColors.background)
        .navigationTitle(seriesName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.index?.seriesByID[seriesID] != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Series page", systemImage: "info.circle") { navigation.open(.series(id: seriesID)) }
                }
            }
        }
    }

    /// The library's copy of each episode, so its watch state is current.
    private var episodes: [(episode: Episode, download: Download)] {
        DownloadStore.shared.finished
            .sorted { EpisodeOrder.precedes($0.playable, $1.playable) }
            .compactMap { download in
                guard case .episode(let saved) = download.playable, saved.seriesID == seriesID else { return nil }
                return (store.index?.episodesByID[saved.id] ?? saved, download)
            }
    }

    private var seriesName: String {
        store.index?.seriesByID[seriesID]?.name ?? episodes.first?.episode.seriesName ?? ""
    }

    private func row(_ episode: Episode, download: Download) -> some View {
        HStack(spacing: 12) {
            RemoteImage(
                ref: episode.still ?? episode.seriesBackdrop,
                type: episode.still == nil ? .backdrop : .primary,
                width: Self.stillSize.width
            )
            .frame(width: Self.stillSize.width, height: Self.stillSize.height)
            .background(JellyCastColors.surface)
            .opacity(episode.watch.played ? 0.55 : 1)
            .clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(Format.seasonEpisode(episode)).font(.footnote).foregroundStyle(JellyCastColors.textMuted)
                Text(episode.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(episode.watch.played ? JellyCastColors.textMuted : JellyCastColors.text)
                    .lineLimit(2)
                Text(DownloadFormat.sizeLine(download)).font(.footnote).foregroundStyle(JellyCastColors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DownloadButton(playable: .episode(episode))
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }
}
