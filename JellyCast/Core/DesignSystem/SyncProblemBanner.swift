import SwiftUI

/// Over a library shown from the cache: why it could not refresh, and since when it is this old.
/// A tap tries again.
struct SyncProblemBanner: View {
    let message: String
    let syncedAt: Date
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        Button(action: onRetry) {
            HStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JellyCastColors.textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(JellyCastColors.text)
                    Text("Updated \(syncedAt, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(JellyCastColors.textMuted)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isRetrying {
                    ProgressView().tint(JellyCastColors.text)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JellyCastColors.text)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(isRetrying)
        .accessibilityHint("Try again")
    }
}

/// The sync problem over a library shown from the cache.
struct SyncProblemOverlay: View {
    let store: LibraryStore

    var body: some View {
        if let failure = store.syncFailure, let syncedAt = store.snapshot?.syncedAt {
            SyncProblemBanner(
                message: failure, syncedAt: syncedAt, isRetrying: store.syncState == .syncing
            ) { Task { await store.refresh() } }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        SyncProblemBanner(
            message: "You're offline.", syncedAt: .now.addingTimeInterval(-3600), isRetrying: false
        ) {}
        SyncProblemBanner(
            message: "The server can't be reached right now.", syncedAt: .now.addingTimeInterval(-60),
            isRetrying: true
        ) {}
    }
    .padding()
    .background(JellyCastColors.background)
}
