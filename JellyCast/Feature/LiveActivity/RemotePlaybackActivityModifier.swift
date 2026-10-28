import SwiftUI

extension View {
    /// Mirrors the TV bar's session in the Live Activity while the app runs. Playing in the app
    /// comes first: the lock screen and Dynamic Island then show that play instead.
    func remotePlaybackActivity(
        _ remote: RemoteSessions, client: JellyfinClient, yieldsTo playsHere: Bool
    ) -> some View {
        modifier(RemotePlaybackActivityModifier(remote: remote, client: client, playsHere: playsHere))
    }
}

private struct RemotePlaybackActivityModifier: ViewModifier {
    let remote: RemoteSessions
    let client: JellyfinClient
    let playsHere: Bool

    func body(content: Content) -> some View {
        content
            .task { await start() }
            .onChange(of: remote.answeredAt) { update() }
            .onChange(of: remote.sessions) { update() }
            .onChange(of: playsHere) { update() }
    }

    private func start() async {
        RemotePlaybackActivity.shared.attach(remote)
        #if DEBUG
        if isPreview { await RemotePlaybackActivity.shared.showPreview() }
        #endif
    }

    /// Only after an answer: before it, no session says nothing about the TV.
    private func update() {
        guard remote.answeredAt != nil, !isPreview else { return }
        RemotePlaybackActivity.shared.show(playsHere ? nil : remote.current, client: client)
    }

    private var isPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(RemotePlaybackActivity.previewArgument)
        #else
        false
        #endif
    }
}
