import Foundation
import OSLog

/// Sends playback reports one after another, in the order they were made.
final class PlaybackReporter {
    private let client: JellyfinClient
    private let userID: String
    private let queue: AsyncStream<@Sendable () async throws -> Void>.Continuation
    private var stoppedSessions: Set<String> = []

    nonisolated private static let logger = Logger(subsystem: "nl.jellycast.ios", category: "playback")

    init(client: JellyfinClient, userID: String) {
        self.client = client
        self.userID = userID
        let (stream, continuation) = AsyncStream<@Sendable () async throws -> Void>.makeStream()
        queue = continuation
        Task.detached {
            for await report in stream {
                do {
                    try await report()
                } catch {
                    Self.logger.warning("Playback report failed: \(error.localizedDescription)")
                }
            }
        }
    }

    deinit { queue.finish() }

    func start(_ report: PlaybackReport) {
        let client = client
        queue.yield { try await client.reportPlaybackStart(report) }
    }

    /// Ignored after the stop: progress after it makes the server think the item still plays.
    func progress(_ report: PlaybackReport, event: String = "TimeUpdate") {
        guard !stoppedSessions.contains(report.playSessionID) else { return }
        let client = client
        queue.yield { try await client.reportPlaybackProgress(report, event: event) }
    }

    /// `finished` marks the item played after the stop report, which would otherwise keep the position.
    func stop(_ report: PlaybackReport, finished: Bool) {
        guard stoppedSessions.insert(report.playSessionID).inserted else { return }
        let client = client
        let userID = userID
        queue.yield { try await client.reportPlaybackStopped(report) }
        if finished {
            queue.yield { try await client.setPlayed(true, itemID: report.itemID, userID: userID) }
        }
    }

    /// Waits until every report made so far has been sent, so a sync afterwards sees them.
    func flush() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.yield { done.resume() }
        }
    }
}
