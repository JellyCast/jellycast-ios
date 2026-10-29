import SwiftUI

extension View {
    /// On the iPad what plays on a TV, else the running download, sits as a pill in the top bar
    /// beside the tabs instead of in a bar along the bottom; the bottom stays free for the mini
    /// player, which can show at the same time.
    func topBarPill() -> some View {
        modifier(TopBarPill())
    }
}

private struct TopBarPill: ViewModifier {
    @Environment(RemoteSessions.self) private var remote
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.layout) private var layout
    @State private var width: CGFloat = 0

    /// Below this the tabs leave room for the image only: the iPad in portrait.
    private static let titleFromWidth: CGFloat = 1000

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .toolbar {
                if layout.isRegular {
                    if let session = remote.current {
                        ToolbarItem(placement: .topBarTrailing) {
                            TVPill(session: session, showsTitle: showsTitle) { remote.show(session) }
                        }
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    } else if navigation.tab != .downloads, let download = DownloadStore.shared.current {
                        ToolbarItem(placement: .topBarTrailing) {
                            DownloadPill(download: download, showsTitle: showsTitle) { navigation.tab = .downloads }
                        }
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    }
                }
            }
    }

    private var showsTitle: Bool {
        width >= Self.titleFromWidth
    }
}

/// The still with a pause sign over it while paused, the title, and the position as a line
/// along the bottom; without the title the position is a ring around the still.
private struct TVPill: View {
    let session: RemoteSession
    let showsTitle: Bool
    let onOpen: () -> Void

    private static let stillSize = CGSize(width: 36, height: 24)
    private static let ringSize: CGFloat = 30
    private static let titleMaxWidth: CGFloat = 220

    var body: some View {
        Button(action: onOpen) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let progress = RemoteFormat.progress(session, at: context.date)
                if showsTitle {
                    HStack(spacing: 8) {
                        still(width: Self.stillSize.width, height: Self.stillSize.height)
                        Text(RemoteFormat.title(session.item))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(JellyCastColors.text)
                            .lineLimit(1)
                            .frame(maxWidth: Self.titleMaxWidth, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                            // Under the title only: across the still it ran into the
                            // capsule's rounded ends.
                            .overlay(alignment: .bottom) {
                                WatchProgressBar(progress: progress, height: 2).offset(y: 6)
                            }
                    }
                    .padding(.trailing, 4)
                } else {
                    still(width: Self.ringSize - 6, height: Self.ringSize - 6)
                        .padding(3)
                        .overlay {
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(JellyCastColors.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(RemoteFormat.title(session.item)))
        .accessibilityValue(Text(RemoteFormat.where(session, at: .now)))
        .accessibilityHint(Text("Shows what plays on \(session.deviceName)"))
    }

    private func still(width: CGFloat, height: CGFloat) -> some View {
        RemoteImage(ref: session.item.image, type: session.item.imageType, width: Self.stillSize.width)
            .frame(width: width, height: height)
            .background(JellyCastColors.surface)
            .overlay {
                if session.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(JellyCastColors.text)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                }
            }
            .clipShape(.capsule)
    }
}

private struct DownloadPill: View {
    let download: Download
    let showsTitle: Bool
    let onOpen: () -> Void

    private static let titleMaxWidth: CGFloat = 220

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                DownloadStateIcon(download: download, size: 30)
                if showsTitle {
                    Text(DownloadStore.title(of: download.playable))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JellyCastColors.text)
                        .lineLimit(1)
                        .frame(maxWidth: Self.titleMaxWidth, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.trailing, 4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(DownloadStore.title(of: download.playable)))
        .accessibilityHint(Text("Shows the downloads"))
    }
}
