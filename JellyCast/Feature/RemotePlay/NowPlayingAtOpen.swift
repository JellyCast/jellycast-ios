import Foundation

/// Opening the app while a TV plays opens that TV's now playing screen, once per open.
enum NowPlayingAtOpen {
    /// A slower first answer comes when the user is already busy in the app.
    static let answerWindow = Duration.seconds(5)

    /// The session to show for the first answer after opening, or nil to leave it to the TV bar.
    static func session(
        _ current: RemoteSession?,
        answeredAfter elapsed: Duration,
        isPlayingHere: Bool,
        isPresenting: Bool
    ) -> RemoteSession? {
        guard elapsed <= answerWindow, !isPlayingHere, !isPresenting else { return nil }
        return current
    }
}
