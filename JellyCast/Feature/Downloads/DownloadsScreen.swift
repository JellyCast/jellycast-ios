import SwiftUI

/// What is on this device and what is on its way: the running download and the queue on top,
/// then every movie and every series with downloaded episodes.
struct DownloadsScreen: View {
    let store: LibraryStore

    @Environment(AppNavigation.self) private var navigation

    private var downloads: DownloadStore { .shared }

    var body: some View {
        List {
            StorageSummary(downloads: downloads)
                .plainRow()
            if let expiry = BuildExpiry.date {
                BuildExpiryNote(date: expiry)
                    .plainRow()
            }
            if !downloads.active.isEmpty {
                Section {
                    ForEach(downloads.active) { download in
                        ActiveDownloadRow(download: download, secondsLeft: downloads.secondsLeft(download))
                            .plainRow()
                            .swipeActions { removeAction([download.id]) }
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        DownloadsSectionTitle("In progress")
                        Spacer()
                        if downloads.active.contains(where: \.status.isActive) {
                            Button("Pause all") { downloads.pauseAll() }
                                .font(.subheadline)
                                .foregroundStyle(JellyCastColors.accent)
                        }
                    }
                }
            }
            if !groups.isEmpty {
                Section {
                    ForEach(groups) { group in
                        Button {
                            open(group)
                        } label: {
                            FinishedGroupRow(group: group, store: store)
                        }
                        .buttonStyle(PressedOpacityButtonStyle())
                        .plainRow()
                        .swipeActions { removeAction(group.downloads.map(\.id), seriesID: group.seriesID) }
                    }
                } header: {
                    DownloadsSectionTitle("On this \(UIDevice.current.localizedModel)")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(JellyCastColors.background)
        .overlay {
            if downloads.downloads.isEmpty {
                ContentUnavailableView {
                    Label("No downloads yet", systemImage: "arrow.down.circle")
                } description: {
                    Text("At home, download a movie or episode with the arrow button to watch it anywhere.")
                }
            }
        }
        .navigationTitle("Downloads")
    }

    private var groups: [DownloadGroup] {
        DownloadGroup.groups(of: downloads.finished)
    }

    private func open(_ group: DownloadGroup) {
        switch group.kind {
        case .movie(let id): navigation.open(.movie(id: id))
        case .series(let id, _): navigation.open(.downloadedSeries(id: id))
        }
    }

    /// Removing a whole series also stops keeping it ahead.
    private func removeAction(_ itemIDs: [String], seriesID: String? = nil) -> some View {
        Button("Remove", systemImage: "trash", role: .destructive) {
            itemIDs.forEach(downloads.remove)
            if let seriesID { DownloadSettings.shared.stopKeeping(seriesID: seriesID) }
        }
    }
}

/// One movie, or all downloaded episodes of one series.
struct DownloadGroup: Identifiable {
    enum Kind {
        case movie(id: String)
        case series(id: String, name: String)
    }

    let kind: Kind
    let downloads: [Download]

    var id: String {
        switch kind {
        case .movie(let id), .series(let id, _): id
        }
    }

    var bytes: Int64 { downloads.reduce(0) { $0 + $1.bytes } }

    var seriesID: String? {
        if case .series(let id, _) = kind { return id }
        return nil
    }

    /// Most recently added first; a series sorts by its newest episode.
    static func groups(of downloads: [Download]) -> [DownloadGroup] {
        var seriesOrder: [String] = []
        var bySeries: [String: [Download]] = [:]
        var groups: [(Date, DownloadGroup)] = []
        for download in downloads {
            switch download.playable {
            case .movie(let movie):
                groups.append((download.addedAt, DownloadGroup(kind: .movie(id: movie.id), downloads: [download])))
            case .episode(let episode):
                if bySeries[episode.seriesID] == nil { seriesOrder.append(episode.seriesID) }
                bySeries[episode.seriesID, default: []].append(download)
            }
        }
        for seriesID in seriesOrder {
            guard let episodes = bySeries[seriesID], case .episode(let first) = episodes[0].playable else { continue }
            let sorted = episodes.sorted { EpisodeOrder.precedes($0.playable, $1.playable) }
            let newest = episodes.map(\.addedAt).max() ?? .distantPast
            groups.append((newest, DownloadGroup(kind: .series(id: seriesID, name: first.seriesName), downloads: sorted)))
        }
        return groups.sorted { $0.0 > $1.0 }.map(\.1)
    }
}

enum EpisodeOrder {
    static func precedes(_ lhs: Playable, _ rhs: Playable) -> Bool {
        guard case .episode(let a) = lhs, case .episode(let b) = rhs else { return false }
        return (a.seasonNumber ?? 0, a.episodeNumber ?? 0) < (b.seasonNumber ?? 0, b.episodeNumber ?? 0)
    }

    /// "S3 E4–E6", "S1 E9 – S2 E2", or "S3 E4" for one.
    static func range(_ episodes: [Episode]) -> String? {
        guard let first = episodes.first, let last = episodes.last else { return nil }
        func short(_ episode: Episode) -> String { Format.seasonEpisode(episode).replacingOccurrences(of: " · ", with: " ") }
        if first.id == last.id { return short(first) }
        if first.seasonNumber == last.seasonNumber, let number = last.episodeNumber {
            return "\(short(first))–E\(number)"
        }
        return "\(short(first)) – \(short(last))"
    }
}

private struct DownloadsSectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(.footnote.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(JellyCastColors.textMuted)
    }
}

/// "2 movies · 3 episodes · 8.9 GB of 256 GB", with a bar of JellyCast, the rest and free space.
private struct StorageSummary: View {
    let downloads: DownloadStore

    private static let barHeight: CGFloat = 6

    var body: some View {
        let volume = VolumeSpace.current
        VStack(alignment: .leading, spacing: 8) {
            Text(summary(totalBytes: volume?.total))
                .font(.subheadline)
                .foregroundStyle(JellyCastColors.text)
            if let volume, volume.total > 0 {
                GeometryReader { proxy in
                    let used = CGFloat(downloads.usedBytes) / CGFloat(volume.total) * proxy.size.width
                    let other = CGFloat(max(volume.total - volume.free - downloads.usedBytes, 0))
                        / CGFloat(volume.total) * proxy.size.width
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [JellyCastColors.progressStart, JellyCastColors.progressEnd],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: max(used, 2))
                        Rectangle().fill(JellyCastColors.textMuted.opacity(0.45)).frame(width: other)
                        Spacer(minLength: 0)
                    }
                    .background(JellyCastColors.rail)
                    .clipShape(.capsule)
                }
                .frame(height: Self.barHeight)
                HStack(spacing: 14) {
                    Text("JellyCast \(DownloadFormat.bytes(downloads.usedBytes))")
                    Text("Other \(DownloadFormat.bytes(max(volume.total - volume.free - downloads.usedBytes, 0)))")
                    Text("Free \(DownloadFormat.bytes(volume.free))")
                }
                .font(.caption)
                .foregroundStyle(JellyCastColors.textMuted)
            }
        }
        .padding(.bottom, 8)
    }

    private func summary(totalBytes: Int64?) -> String {
        let finished = downloads.finished
        let movies = finished.filter { if case .movie = $0.playable { true } else { false } }.count
        let episodes = finished.count - movies
        let used = DownloadFormat.bytes(downloads.usedBytes)
        return Format.joined([
            movies > 0 ? String(localized: "\(movies) movies") : nil,
            episodes > 0 ? String(localized: "\(episodes) episodes") : nil,
            totalBytes.map { String(localized: "\(used) of \(DownloadFormat.bytes($0))") } ?? used,
        ])
    }
}

nonisolated struct VolumeSpace {
    let total: Int64
    let free: Int64

    static var current: VolumeSpace? {
        let values = try? URL.applicationSupportDirectory.resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        )
        guard let total = values?.volumeTotalCapacity, let free = values?.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return VolumeSpace(total: Int64(total), free: free)
    }
}

private struct DownloadPoster: View {
    let playable: Playable

    static let size = CGSize(width: 60, height: 90)

    var body: some View {
        RemoteImage(ref: ref, width: Self.size.width)
            .frame(width: Self.size.width, height: Self.size.height)
            .background(JellyCastColors.surface)
            .clipShape(.rect(cornerRadius: 8))
    }

    private var ref: ImageRef? {
        switch playable {
        case .movie(let movie): movie.poster
        case .episode(let episode): episode.seriesPoster
        }
    }
}

private struct ActiveDownloadRow: View {
    let download: Download
    let secondsLeft: Double?

    var body: some View {
        HStack(spacing: 14) {
            DownloadPoster(playable: download.playable)
            VStack(alignment: .leading, spacing: 3) {
                Text(DownloadStore.title(of: download.playable))
                    .font(.headline)
                    .foregroundStyle(JellyCastColors.text)
                    .lineLimit(2)
                Text(DownloadFormat.sizeLine(download))
                    .font(.subheadline)
                    .foregroundStyle(JellyCastColors.textMuted)
                Text(DownloadFormat.statusLine(download, secondsLeft: secondsLeft))
                    .font(.subheadline)
                    .foregroundStyle(isMoving ? JellyCastColors.accent : JellyCastColors.textMuted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DownloadButton(playable: download.playable)
        }
        .padding(.vertical, 8)
    }

    private var isMoving: Bool {
        download.status == .running || download.status == .waitingForNetwork
    }
}

private struct FinishedGroupRow: View {
    let group: DownloadGroup
    let store: LibraryStore

    var body: some View {
        HStack(spacing: 14) {
            DownloadPoster(playable: group.downloads[0].playable)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(JellyCastColors.text)
                    .lineLimit(2)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(JellyCastColors.textMuted)
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(JellyCastColors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(JellyCastColors.textMuted)
                .frame(width: 34)
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }

    private var title: String {
        switch group.kind {
        case .movie: group.downloads[0].playable.name
        case .series(_, let name): name
        }
    }

    private var detail: String {
        let size = DownloadFormat.bytes(group.bytes)
        switch group.kind {
        case .movie:
            return Format.joined([
                String(localized: "Movie"), Format.runtime(group.downloads[0].playable.runtimeTicks), size,
            ])
        case .series:
            let episodes = group.downloads.compactMap { if case .episode(let e) = $0.playable { e } else { nil } }
            return Format.joined([
                String(localized: "\(episodes.count) episodes"), EpisodeOrder.range(episodes), size,
            ])
        }
    }

    /// Watch state from the library, which knows what was watched since the download.
    private var status: String {
        let current = group.downloads.map { store.index?.playable(id: $0.id) ?? $0.playable }
        switch group.kind {
        case .movie:
            let playable = current[0]
            let watch: String = if playable.watch.played {
                String(localized: "watched")
            } else if playable.watch.isInProgress, let remaining = Format.remaining(playable.remainingTicks) {
                remaining
            } else {
                String(localized: "not watched")
            }
            return Format.joined([DownloadFormat.kind(group.downloads[0].kind), watch])
        case .series:
            let unwatched = current.filter { !$0.watch.played }.count
            return unwatched == 0 ? String(localized: "All watched") : String(localized: "\(unwatched) not watched")
        }
    }
}

private extension View {
    func plainRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    }
}
