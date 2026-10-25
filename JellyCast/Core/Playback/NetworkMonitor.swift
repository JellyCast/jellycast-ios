import Foundation
import Network
import Synchronization

/// The kind of network the server is reached over; each has its own streaming quality.
enum NetworkKind {
    /// The server is on the same local network as the device.
    case local
    case wifi
    case cellular
}

/// Whether the device has a network, and whether it is metered. A personal hotspot counts as
/// metered, like mobile data, because iOS marks both as expensive.
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isCellular = false
    private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let expensive = path.isExpensive
            let online = path.status == .satisfied
            Task { @MainActor in
                NetworkMonitor.shared.update(isCellular: expensive, isOnline: online)
            }
        }
        monitor.start(queue: DispatchQueue(label: "nl.jellycast.network-monitor"))
    }

    /// Local beats metered: a server in the device's own subnet is reached directly.
    func kind(serverURL: URL) -> NetworkKind {
        if LocalNetwork.contains(serverURL: serverURL) { return .local }
        return isCellular ? .cellular : .wifi
    }

    private func update(isCellular: Bool, isOnline: Bool) {
        self.isOnline = isOnline
        guard isCellular != self.isCellular else { return }
        self.isCellular = isCellular
        ConnectionMeter.shared.reset()
    }
}

/// The most recent connection speed, measured while fetching the original file. Auto uses it
/// only while it is fresh and from the same network.
nonisolated final class ConnectionMeter: Sendable {
    static let shared = ConnectionMeter()

    private struct Sample { let bytesPerSecond: Double; let measuredAt: ContinuousClock.Instant }

    private let latest = Mutex<Sample?>(nil)

    private static let freshFor = Duration.seconds(10 * 60)

    func record(bytesPerSecond: Double) {
        latest.withLock { $0 = Sample(bytesPerSecond: bytesPerSecond, measuredAt: .now) }
    }

    func reset() {
        latest.withLock { $0 = nil }
    }

    var freshBytesPerSecond: Double? {
        latest.withLock { sample in
            guard let sample, ContinuousClock.now - sample.measuredAt < Self.freshFor else { return nil }
            return sample.bytesPerSecond
        }
    }
}
