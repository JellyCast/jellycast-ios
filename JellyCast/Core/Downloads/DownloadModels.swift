import Foundation

nonisolated enum DownloadKind: String, Codable, Sendable {
    /// The server's 1080p HEVC transcode, appended into one fragmented MP4.
    case compact
    /// The file as it is on the server.
    case original
}

nonisolated enum DownloadStatus: Codable, Sendable, Equatable {
    case queued
    case running
    case waitingForNetwork
    case paused
    case done
    case failed(String)

    var isActive: Bool {
        switch self {
        case .queued, .running, .waitingForNetwork: true
        case .paused, .done, .failed: false
        }
    }
}

/// One movie or episode on the device, or on its way there.
nonisolated struct Download: Codable, Sendable, Identifiable, Equatable {
    let playable: Playable
    var kind: DownloadKind
    var status = DownloadStatus.queued
    var bytes: Int64 = 0
    /// The size when known: the original's size, or the Compact file once it is done.
    var totalBytes: Int64?
    /// The expected size before it is known, for the free-space check.
    var estimatedBytes: Int64?
    var mediaSeconds = 0.0
    var totalMediaSeconds: Double?
    var addedAt = Date.now

    var id: String { playable.id }

    var fraction: Double? {
        if status == .done { return 1 }
        if kind == .compact, let totalMediaSeconds, totalMediaSeconds > 0 {
            return min(mediaSeconds / totalMediaSeconds, 1)
        }
        if let totalBytes, totalBytes > 0 { return min(Double(bytes) / Double(totalBytes), 1) }
        return nil
    }

    /// What it takes on disk now, or will take once done.
    var expectedBytes: Int64 {
        status == .done ? bytes : max(totalBytes ?? estimatedBytes ?? 0, bytes)
    }
}

/// The choice offered for one item: Compact unless the original is no bigger.
nonisolated struct DownloadPlan: Sendable, Equatable {
    let compactBytes: Int64?
    let originalBytes: Int64?

    /// Measured on the server's 1080p transcode (5 Mbit/s cap): ~4.9 Mbit/s with stereo AAC.
    static let compactBitsPerSecond = 4_900_000.0

    init(runtimeTicks: Int64?, originalBytes: Int64?) {
        let seconds = runtimeTicks.map(Ticks.seconds) ?? 0
        compactBytes = seconds > 0 ? Int64(seconds * Self.compactBitsPerSecond / 8) : nil
        self.originalBytes = originalBytes
    }

    var offersCompact: Bool {
        guard let compactBytes else { return false }
        guard let originalBytes else { return true }
        return originalBytes > compactBytes
    }

    var defaultKind: DownloadKind { offersCompact ? .compact : .original }

    func bytes(for kind: DownloadKind) -> Int64? {
        kind == .compact ? compactBytes : originalBytes
    }
}
