import Foundation

/// The stream caches in use: the one playing and the one warmed up on a detail screen.
final class StreamCaches {
    static let shared = StreamCaches()

    private var caches: [String: StreamCache] = [:]
    private var opening: [String: Task<StreamCache, Error>] = [:]
    private var order: [String] = []

    private static let keptCaches = 2

    /// Parts left behind when the app was stopped mid-play.
    private init() {
        try? FileManager.default.removeItem(at: URL.cachesDirectory.appending(path: "stream"))
    }

    func cache(
        itemID: String, mediaSourceID: String, bitsPerSecond: Int, session: Session
    ) async throws -> StreamCache {
        if let cache = caches[itemID] { return cache }
        if let running = opening[itemID] { return try await running.value }
        let client = session.client
        let task = Task {
            try await StreamCache.open(
                itemID: itemID,
                remoteURL: client.originalStreamURL(itemID: itemID, mediaSourceID: mediaSourceID),
                authorization: client.authorizationHeader,
                bitsPerSecond: bitsPerSecond
            )
        }
        opening[itemID] = task
        defer { opening[itemID] = nil }
        let cache = try await task.value
        keep(cache)
        return cache
    }

    /// Wakes the server's disk and measures the connection while the user is still choosing.
    func warmUp(itemID: String, session: Session) async {
        guard caches[itemID] == nil,
              let info = try? await session.client.mediaInfo(itemID: itemID, userID: session.userID),
              let cache = try? await cache(
                itemID: itemID, mediaSourceID: info.mediaSourceID,
                bitsPerSecond: info.bitsPerSecond, session: session
              )
        else { return }
        await cache.warmUp()
    }

    /// Drops a cache after playback; its part file goes with it.
    func release(itemID: String) {
        caches[itemID] = nil
        order.removeAll { $0 == itemID }
        LocalStreamServer.shared.remove(itemID: itemID)
    }

    private func keep(_ cache: StreamCache) {
        caches[cache.itemID] = cache
        order.removeAll { $0 == cache.itemID }
        order.append(cache.itemID)
        while order.count > Self.keptCaches {
            let dropped = order.removeFirst()
            caches[dropped] = nil
            LocalStreamServer.shared.remove(itemID: dropped)
        }
    }
}
