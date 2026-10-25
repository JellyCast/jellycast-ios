import Foundation
import OSLog

/// A position reached in a download, with when it was watched.
nonisolated struct OfflinePosition: Codable, Sendable, Equatable {
    let itemID: String
    let positionTicks: Int64
    let played: Bool
    let watchedAt: Date
}

/// Positions watched in downloads, kept on the device until the server has them. Saved next to
/// the downloads, so a position survives the app being closed in airplane mode.
@Observable
final class OfflineProgress {
    static let shared = OfflineProgress()

    private(set) var pending: [String: OfflinePosition] = [:]
    private var isSending = false

    private static let logger = Logger(subsystem: "nl.jellycast.ios", category: "downloads")
    private static let fileName = "progress.json"

    private static var file: URL {
        DownloadStore.directory.appending(path: fileName)
    }

    private init() {
        if let data = try? Data(contentsOf: Self.file),
           let saved = try? JSONDecoder().decode([OfflinePosition].self, from: data) {
            pending = Dictionary(saved.map { ($0.itemID, $0) }, uniquingKeysWith: { $0.watchedAt > $1.watchedAt ? $0 : $1 })
        }
    }

    func record(itemID: String, positionTicks: Int64, finished: Bool) {
        pending[itemID] = OfflinePosition(
            itemID: itemID, positionTicks: finished ? 0 : positionTicks, played: finished, watchedAt: .now
        )
        save()
    }

    /// Sends what the server doesn't have yet; the most recent position wins, so one watched
    /// later on a TV stays. Returns whether the server changed.
    func send(client: JellyfinClient, userID: String) async -> Bool {
        guard !isSending, !pending.isEmpty else { return false }
        isSending = true
        defer { isSending = false }
        var changed = false
        for position in pending.values.sorted(by: { $0.watchedAt < $1.watchedAt }) {
            do {
                let server = try await client.position(itemID: position.itemID, userID: userID)
                if Self.isNewer(position, than: server) {
                    try await client.setPosition(
                        ItemPosition(
                            positionTicks: position.positionTicks, played: position.played || server.played,
                            lastPlayed: position.watchedAt
                        ),
                        itemID: position.itemID, userID: userID
                    )
                    changed = true
                }
                if pending[position.itemID] == position { pending[position.itemID] = nil }
                save()
            } catch {
                Self.logger.warning("Offline position not sent: \(error.localizedDescription, privacy: .public)")
                return changed
            }
        }
        return changed
    }

    static func isNewer(_ position: OfflinePosition, than server: ItemPosition) -> Bool {
        guard let lastPlayed = server.lastPlayed else { return true }
        return position.watchedAt > lastPlayed
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: DownloadStore.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(Array(pending.values)).write(to: Self.file, options: .atomic)
        } catch {
            Self.logger.error("Offline positions not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
