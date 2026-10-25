import SwiftUI

/// Above the tab bar while another device plays: what, where, and how far. A tap opens the
/// now playing screen.
struct TVBar: View {
    let session: RemoteSession
    let onOpen: () -> Void

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private static let stillSize = CGSize(width: 48, height: 32)
    /// The muted text color is too dark on the glass over a bright image.
    private static let detailOpacity = 0.8
    /// Keeps the line clear of the capsule's rounded ends.
    private static let progressInset: CGFloat = 24

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                RemoteImage(ref: session.item.image, type: session.item.imageType, width: Self.stillSize.width)
                    .frame(width: Self.stillSize.width, height: Self.stillSize.height)
                    .background(JellyCastColors.surface)
                    .clipShape(.capsule)
                VStack(alignment: .leading, spacing: 1) {
                    Text(RemoteFormat.title(session.item))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JellyCastColors.text)
                    if placement != .inline {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(RemoteFormat.where(session, at: context.date))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(JellyCastColors.text.opacity(Self.detailOpacity))
                        }
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "tv")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(JellyCastColors.accent)
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if placement != .inline {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        WatchProgressBar(progress: RemoteFormat.progress(session, at: context.date), height: 2)
                    }
                    .padding(.horizontal, Self.progressInset)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(RemoteFormat.title(session.item)))
        .accessibilityValue(Text(RemoteFormat.where(session, at: .now)))
        .accessibilityHint(Text("Shows what plays on \(session.deviceName)"))
    }
}

nonisolated enum RemoteFormat {
    /// "Melbourne · The Pacific", or the movie title.
    static func title(_ item: RemoteItem) -> String {
        Format.joined([item.name, item.seriesName])
    }

    /// "Playing on Living room · 32 min left", or "Paused on …".
    static func `where`(_ session: RemoteSession, at date: Date) -> String {
        let device = session.deviceName
        let place = session.isPaused
            ? String(localized: "Paused on \(device)") : String(localized: "Playing on \(device)")
        return Format.joined([place, Format.remaining(remainingTicks(session, at: date))])
    }

    static func remainingTicks(_ session: RemoteSession, at date: Date) -> Int64? {
        session.item.runtimeTicks.map { max($0 - session.position(at: date), 0) }
    }

    static func progress(_ session: RemoteSession, at date: Date) -> Double {
        guard let runtime = session.item.runtimeTicks, runtime > 0 else { return 0 }
        return Double(session.position(at: date)) / Double(runtime)
    }

    /// "23:41", "1:02:05".
    static func clock(_ ticks: Int64) -> String {
        let seconds = Int(Ticks.seconds(ticks))
        let (hours, minutes, rest) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    static func playMethod(_ method: RemoteSession.PlayMethod?) -> String? {
        switch method {
        case .directPlay: String(localized: "Direct play")
        case .directStream: String(localized: "Direct stream")
        case .transcode: String(localized: "Transcode")
        case nil: nil
        }
    }
}

#Preview {
    TabView {
        Tab("Home", systemImage: "house") { Color.clear }
    }
    .tabViewBottomAccessory { TVBar(session: .preview) {} }
    .preferredColorScheme(.dark)
}

extension RemoteSession {
    static let preview = RemoteSession(
        id: "preview",
        deviceID: "preview-device",
        deviceName: "Living room",
        item: RemoteItem(
            id: "episode", name: "Melbourne", seriesName: "The Pacific", seasonNumber: 1, episodeNumber: 3,
            runtimeTicks: 56 * 60 * Ticks.perSecond, image: nil, imageType: .primary
        ),
        positionTicks: (23 * 60 + 41) * Ticks.perSecond,
        isPaused: false,
        playMethod: .directPlay,
        checkedInAt: nil,
        canControl: true,
        audioStreamIndex: 1,
        subtitleStreamIndex: nil
    )
}
