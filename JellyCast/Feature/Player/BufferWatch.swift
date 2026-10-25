import Foundation

/// How far the play is loaded ahead, and whether the connection keeps up: while playing, a
/// connection that keeps up grows the buffer or holds it at its cap; one that doesn't lets it
/// run down. Only a hint follows; the quality never changes by itself.
@Observable
final class BufferWatch {
    enum Hint: Equatable {
        case lowerQualityHelps(StreamLevel)
        case connectionTooSlow
    }

    /// The engine waits for data in the middle of a play.
    private(set) var isStalled = false
    /// Seconds loaded ahead of the play position.
    private(set) var aheadSeconds: Double = 0
    private(set) var hint: Hint?

    private struct Sample {
        let at: ContinuousClock.Instant
        let aheadSeconds: Double
    }

    private var samples: [Sample] = []
    private var lastHintAt: ContinuousClock.Instant?

    /// The buffer has to run down over this much playing time before it counts.
    private static let window = Duration.seconds(30)
    private static let minimumDropSeconds = 5.0
    /// Above this the buffer can run down a while longer; a hint would come too early.
    private static let lowAheadSeconds = 60.0
    /// After a hint, the watch stays quiet for this long, so the hint doesn't nag.
    private static let hintPause = Duration.seconds(5 * 60)

    /// One sample a second. Only playing time counts: a pause, a seek or the end of the file
    /// coming into the buffer starts the window anew.
    func record(
        aheadSeconds: Double, isPlaying: Bool, reachesEnd: Bool, lowerLevel: () -> StreamLevel?
    ) {
        self.aheadSeconds = aheadSeconds
        guard isPlaying, !reachesEnd else {
            samples = []
            return
        }
        let now = ContinuousClock.now
        samples = samples.filter { now - $0.at <= Self.window }
            + [Sample(at: now, aheadSeconds: aheadSeconds)]
        guard let oldest = samples.first, now - oldest.at >= Self.window * 0.9,
              oldest.aheadSeconds - aheadSeconds >= Self.minimumDropSeconds,
              aheadSeconds < Self.lowAheadSeconds
        else { return }
        if let lastHintAt, now - lastHintAt < Self.hintPause { return }
        lastHintAt = now
        samples = []
        hint = lowerLevel().map(Hint.lowerQualityHelps) ?? .connectionTooSlow
    }

    func bufferingChanged(_ isBuffering: Bool) {
        isStalled = isBuffering
    }

    /// A seek empties the buffer on purpose; the run-down before it says nothing any more.
    func seeked() {
        samples = []
    }

    func dismissHint() {
        hint = nil
    }

    /// Ends the watch for this load; the pause after a hint carries over to the next one.
    func stop() {
        isStalled = false
        aheadSeconds = 0
        samples = []
        hint = nil
    }
}
