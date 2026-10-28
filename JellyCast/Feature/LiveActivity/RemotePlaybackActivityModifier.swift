import SwiftUI

extension View {
    /// Mirrors the TV bar's session in the Live Activity while the app runs.
    func remotePlaybackActivity(_ remote: RemoteSessions, client: JellyfinClient) -> some View {
        modifier(RemotePlaybackActivityModifier(remote: remote, client: client))
    }
}

private struct RemotePlaybackActivityModifier: ViewModifier {
    let remote: RemoteSessions
    let client: JellyfinClient

    func body(content: Content) -> some View {
        content
            .task { await start() }
            .onChange(of: remote.answeredAt) { update() }
            .onChange(of: remote.sessions) { update() }
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
        RemotePlaybackActivity.shared.show(remote.current, client: client)
    }

    private var isPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(RemotePlaybackActivity.previewArgument)
        #else
        false
        #endif
    }
}
