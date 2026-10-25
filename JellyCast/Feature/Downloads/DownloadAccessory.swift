import SwiftUI

/// The running download in the bar above the tab bar: "The Pitt · S1 · E3 · 42%".
struct DownloadAccessory: View {
    let download: Download
    let secondsLeft: Double?
    let onOpen: () -> Void

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private static let progressInset: CGFloat = 24

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                DownloadStateIcon(download: download, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(DownloadStore.title(of: download.playable))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JellyCastColors.text)
                    if placement != .inline {
                        Text(DownloadFormat.statusLine(download, secondsLeft: secondsLeft))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(JellyCastColors.text.opacity(0.8))
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if placement != .inline, let fraction = download.fraction {
                    WatchProgressBar(progress: fraction, height: 2).padding(.horizontal, Self.progressInset)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Shows the downloads"))
    }
}
