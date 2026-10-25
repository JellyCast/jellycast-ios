import Foundation

/// The volume of a paired Android TV while its now playing screen is open: keys go over the
/// remote connection, which the TV passes on to the TV set or soundbar like its own remote.
@Observable
final class TVVolume {
    private(set) var isConnected = false
    /// As the TV reports it; with HDMI-CEC this may be the Chromecast's own level.
    private(set) var volume: AndroidTVControl.Volume?
    /// The last press, so the level shows for a moment.
    private(set) var changedAt: Date?

    private let control: AndroidTVControl
    private var lastPress: Task<Void, Never>?

    private static let retryDelay = Duration.seconds(3)

    init(host: String) {
        control = AndroidTVControl(host: host)
    }

    /// Keeps the connection open, reconnecting after a drop, until the task is cancelled.
    func run() async {
        while !Task.isCancelled {
            try? await control.run(
                onReady: { @MainActor in self.isConnected = true },
                onVolume: { @MainActor volume in self.volume = volume }
            )
            isConnected = false
            try? await Task.sleep(for: Self.retryDelay)
        }
    }

    /// Presses go out in order, also when the buttons are pressed quickly.
    func press(_ key: AndroidTVControl.Key) {
        guard isConnected else { return }
        changedAt = .now
        let previous = lastPress
        lastPress = Task {
            await previous?.value
            try? await control.press(key)
        }
    }
}
