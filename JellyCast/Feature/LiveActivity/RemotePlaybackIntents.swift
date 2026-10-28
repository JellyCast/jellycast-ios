import AppIntents
import Foundation

nonisolated enum RemotePlaybackAction: Sendable {
    case playPause
    case skip(seconds: Double)
}

/// Live Activity buttons run in the app's process; the app sets `perform` at launch. In the widget
/// extension it stays nil, which is fine because the system never runs the intents there.
enum RemotePlaybackActions {
    static var perform: ((RemotePlaybackAction) async -> Void)?
    static let skipSeconds = 10.0

    static func run(_ action: RemotePlaybackAction) async {
        await perform?(action)
    }
}

struct TogglePlaybackIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Play or pause on the TV"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await RemotePlaybackActions.run(.playPause)
        return .result()
    }
}

struct SkipBackIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Back 10 seconds on the TV"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await RemotePlaybackActions.run(.skip(seconds: -RemotePlaybackActions.skipSeconds))
        return .result()
    }
}

struct SkipForwardIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Forward 10 seconds on the TV"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await RemotePlaybackActions.run(.skip(seconds: RemotePlaybackActions.skipSeconds))
        return .result()
    }
}
