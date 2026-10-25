import Foundation

/// Several episodes at once, and the downloads looking after themselves: watched ones go,
/// kept series stay ahead.
extension DownloadStore {
    /// The unwatched episodes from where the series stands, in order; specials are left out.
    static func upcomingEpisodes(_ progress: SeriesProgress, count: Int) -> [Episode] {
        let regular = progress.episodes.filter { ($0.seasonNumber ?? 0) > 0 }
        let start = progress.next.flatMap { next in regular.firstIndex { $0.id == next.id } } ?? regular.startIndex
        return Array(regular[start...].filter { !$0.watch.played }.prefix(count))
    }

    /// The upcoming episodes this device doesn't have or fetch yet.
    func missingEpisodes(_ progress: SeriesProgress, count: Int = DownloadSettings.seriesBatch) -> [Episode] {
        Self.upcomingEpisodes(progress, count: count).filter { download(for: $0.id) == nil }
    }

    /// Each episode's default choice and size, from the server's file info.
    func plans(for episodes: [Episode]) async -> [(episode: Episode, kind: DownloadKind, bytes: Int64?)] {
        var plans: [(episode: Episode, kind: DownloadKind, bytes: Int64?)] = []
        for episode in episodes {
            let plan = await plan(for: .episode(episode)).plan
            plans.append((episode, plan.defaultKind, plan.bytes(for: plan.defaultKind)))
        }
        return plans
    }

    /// Queues the episodes in order as far as the free space reaches; returns how many went in.
    @discardableResult
    func enqueue(_ plans: [(episode: Episode, kind: DownloadKind, bytes: Int64?)]) -> Int {
        var free = freeBytes ?? .max
        var queued = 0
        for plan in plans {
            let bytes = plan.bytes ?? 0
            guard bytes <= free else { break }
            free -= bytes
            enqueue(.episode(plan.episode), kind: plan.kind, estimatedBytes: plan.bytes)
            queued += 1
        }
        return queued
    }

    /// Run after every library sync: removes what was watched a day ago, and at home tops up
    /// the kept series.
    func tidy(index: LibraryIndex) async {
        let settings = DownloadSettings.shared
        if settings.removesWatched {
            for download in finished where isWatchedLongAgo(download, index: index) {
                remove(download.id)
            }
        }
        guard settings.keepsSeriesAhead, canReachServer else { return }
        for seriesID in settings.keptSeriesIDs {
            guard let progress = index.progress(of: seriesID) else { continue }
            let missing = missingEpisodes(progress)
            if !missing.isEmpty { enqueue(await plans(for: missing)) }
        }
    }

    /// Only a watch after the download counts, so an item downloaded to see again stays.
    private func isWatchedLongAgo(_ download: Download, index: LibraryIndex) -> Bool {
        guard let watch = index.playable(id: download.id)?.watch, watch.played,
              let lastPlayed = watch.lastPlayed, lastPlayed > download.addedAt else { return false }
        return Date.now.timeIntervalSince(lastPlayed) > DownloadSettings.watchedGraceSeconds
    }
}
