import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// What plays on a TV, on the lock screen and in the Dynamic Island.
struct RemotePlaybackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RemotePlaybackAttributes.self) { context in
            // Clear, so the lock screen's own glass shows through, as with the system's players.
            LockScreenView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(.clear)
        } dynamicIsland: { context in
            let state = context.state
            let isStale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Artwork(artworkID: state.artworkID, size: Artwork.expandedSize)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if state.canControl && !isStale {
                        PlayPauseButton(isPaused: state.isPaused, size: .title)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    TitleLines(state: state, isStale: isStale, showsDevice: false)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressRow(state: state, isStale: isStale)
                        DeviceLine(state: state, isStale: isStale)
                    }
                }
            } compactLeading: {
                BrandMark()
                    .frame(width: Self.compactMarkSize, height: Self.compactMarkSize)
            } compactTrailing: {
                ProgressRing(state: state, isStale: isStale)
            } minimal: {
                ProgressRing(state: state, isStale: isStale)
            }
            .keylineTint(JellyCastColors.accent)
        }
    }

    private static let compactMarkSize: CGFloat = 22
}

private struct LockScreenView: View {
    let state: RemotePlaybackAttributes.ContentState
    let isStale: Bool

    private var showsControls: Bool { state.canControl && !isStale }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Artwork(artworkID: state.artworkID, size: Artwork.lockScreenSize)
                TitleLines(state: state, isStale: isStale, showsDevice: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsControls {
                    PlayPauseButton(isPaused: state.isPaused, size: .title)
                }
            }
            HStack(spacing: 4) {
                if showsControls { SkipButton(intent: SkipBackIntent(), systemImage: "gobackward.10", label: "Back 10 seconds") }
                ProgressRow(state: state, isStale: isStale)
                if showsControls { SkipButton(intent: SkipForwardIntent(), systemImage: "goforward.10", label: "Forward 10 seconds") }
            }
        }
        .padding(16)
    }
}

private struct TitleLines: View {
    let state: RemotePlaybackAttributes.ContentState
    let isStale: Bool
    let showsDevice: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.title)
                .font(.headline)
                .foregroundStyle(.primary)
            if let episodeLine = state.episodeLine {
                Text(episodeLine)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            if showsDevice {
                DeviceLine(state: state, isStale: isStale)
            }
        }
        .lineLimit(1)
    }
}

private struct DeviceLine: View {
    let state: RemotePlaybackAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Group {
            if isStale {
                Text("Open JellyCast to update")
            } else if state.isPaused {
                Text("Paused on \(state.deviceName)")
            } else {
                Text("Playing on \(state.deviceName)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct ProgressRow: View {
    let state: RemotePlaybackAttributes.ContentState
    let isStale: Bool

    private static let remainingWidth: CGFloat = 56

    var body: some View {
        HStack(spacing: 10) {
            bar
            remaining
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(width: Self.remainingWidth, alignment: .trailing)
        }
    }

    @ViewBuilder private var bar: some View {
        if let end = state.endDate, !state.isPaused, !isStale {
            ProgressView(timerInterval: state.startDate...end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.primary)
        } else {
            ProgressView(value: state.progress(at: .now))
                .tint(.primary)
        }
    }

    @ViewBuilder private var remaining: some View {
        if isStale {
            EmptyView()
        } else if let end = state.endDate, !state.isPaused {
            Text(timerInterval: state.startDate...end, countsDown: true)
        } else if let seconds = state.remainingSeconds(at: .now) {
            Text(Duration.seconds(seconds), format: .time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
        }
    }
}

private struct ProgressRing: View {
    let state: RemotePlaybackAttributes.ContentState
    let isStale: Bool

    private static let size: CGFloat = 20

    var body: some View {
        Group {
            if let end = state.endDate, !state.isPaused, !isStale {
                ProgressView(timerInterval: state.startDate...end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(value: state.progress(at: .now))
            }
        }
        .progressViewStyle(.circular)
        .tint(JellyCastColors.accent)
        .frame(width: Self.size, height: Self.size)
    }
}

private struct SkipButton<Intent: LiveActivityIntent>: View {
    let intent: Intent
    let systemImage: String
    let label: LocalizedStringKey

    var body: some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(Text(label))
    }
}

private struct PlayPauseButton: View {
    let isPaused: Bool
    let size: Font

    var body: some View {
        Button(intent: TogglePlaybackIntent()) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(size)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(isPaused ? Text("Play") : Text("Pause"))
    }
}

/// The item's image when the app could share it, otherwise the brand mark.
private struct Artwork: View {
    let artworkID: String?
    let size: CGSize

    static let lockScreenSize = CGSize(width: 72, height: 40)
    static let expandedSize = CGSize(width: 64, height: 36)
    private static let cornerRadius: CGFloat = 6

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                BrandMark()
                    .padding(4)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: Self.cornerRadius))
    }

    private var image: UIImage? {
        guard let artworkID, let url = RemotePlaybackArtworkFiles.url(for: artworkID) else { return nil }
        return UIImage(contentsOfFile: url.path(percentEncoded: false))
    }
}

#Preview("Lock screen", as: .content, using: RemotePlaybackAttributes(deviceID: "preview")) {
    RemotePlaybackLiveActivity()
} contentStates: {
    RemotePlaybackAttributes.ContentState.preview
    RemotePlaybackAttributes.ContentState.preview.toggled(at: .now)
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: RemotePlaybackAttributes(deviceID: "preview")) {
    RemotePlaybackLiveActivity()
} contentStates: {
    RemotePlaybackAttributes.ContentState.preview
}

private extension RemotePlaybackAttributes.ContentState {
    static let preview = Self(
        title: "The Leftovers",
        episodeLine: "S1 · E7 · Solace for Tired Feet",
        deviceName: "chromecast",
        isPaused: false,
        positionSeconds: 23 * 60 + 41,
        positionDate: .now,
        runtimeSeconds: 56 * 60,
        sessionID: "preview",
        canControl: true,
        artworkID: nil
    )
}
