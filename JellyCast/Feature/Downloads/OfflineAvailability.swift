import SwiftUI

extension EnvironmentValues {
    /// The server can't be reached, so only what is on the device can be opened or played.
    @Entry var isOffline = false
}

extension View {
    /// Dims an item that isn't on the device while offline and ignores taps on it.
    func availableOffline(_ itemID: String) -> some View {
        modifier(OfflineAvailability(itemID: itemID))
    }
}

private struct OfflineAvailability: ViewModifier {
    let itemID: String

    @Environment(\.isOffline) private var isOffline

    private static let dimmedOpacity = 0.35

    func body(content: Content) -> some View {
        let isUnavailable = isOffline && !DownloadStore.shared.isOnDevice(itemID)
        content
            .opacity(isUnavailable ? Self.dimmedOpacity : 1)
            .allowsHitTesting(!isUnavailable)
            .accessibilityHint(isUnavailable ? Text("Not downloaded") : Text(""))
    }
}
