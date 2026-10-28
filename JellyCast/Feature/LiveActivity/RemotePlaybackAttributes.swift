import ActivityKit
import Foundation

/// What plays on one of the user's TVs, for the Live Activity on the lock screen and in the
/// Dynamic Island. Compiled into the app and the widget extension.
nonisolated struct RemotePlaybackAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// The series or the movie.
        var title: String
        /// "S1 · E7 · Left Behind" for an episode.
        var episodeLine: String?
        var deviceName: String
        var isPaused: Bool
        var positionSeconds: Double
        /// When the TV was at `positionSeconds`.
        var positionDate: Date
        var runtimeSeconds: Double?
        /// The server session the buttons send to.
        var sessionID: String
        /// Without remote control the TV can only be watched: no buttons.
        var canControl: Bool
        /// A small image the app wrote to the shared container, if it could.
        var artworkID: String?

        /// Where playback would have started had it run without pauses; the timers count from it.
        var startDate: Date { positionDate.addingTimeInterval(-positionSeconds) }

        var endDate: Date? { runtimeSeconds.map { startDate.addingTimeInterval($0) } }

        func position(at date: Date) -> Double {
            let position = isPaused ? positionSeconds : date.timeIntervalSince(startDate)
            guard let runtimeSeconds else { return max(position, 0) }
            return min(max(position, 0), runtimeSeconds)
        }

        func progress(at date: Date) -> Double {
            guard let runtimeSeconds, runtimeSeconds > 0 else { return 0 }
            return position(at: date) / runtimeSeconds
        }

        func remainingSeconds(at date: Date) -> Double? {
            runtimeSeconds.map { max($0 - position(at: date), 0) }
        }

        /// The same playback, `seconds` further along, as the TV will report it after a seek.
        func seeked(by seconds: Double, at date: Date) -> ContentState {
            var state = self
            let target = position(at: date) + seconds
            state.positionSeconds = runtimeSeconds.map { min(max(target, 0), $0) } ?? max(target, 0)
            state.positionDate = date
            return state
        }

        func toggled(at date: Date) -> ContentState {
            var state = self
            state.positionSeconds = position(at: date)
            state.positionDate = date
            state.isPaused.toggle()
            return state
        }
    }

    /// The TV: a new TV is a new activity, a new item on the same TV only an update.
    let deviceID: String
}

/// The App Group container both targets can read: a Live Activity can't load from the network.
nonisolated enum RemotePlaybackArtworkFiles {
    static let appGroup = "group.nl.jellycast.ios"

    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "LiveActivityArtwork", directoryHint: .isDirectory)
    }

    static func url(for artworkID: String) -> URL? {
        directory?.appending(path: artworkID + ".jpg")
    }
}
