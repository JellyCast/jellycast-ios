import AVKit
import AetherEngine
import SwiftUI

/// The controls over the video: tracks, AirPlay and PiP top right, transport in the middle,
/// time and the full-screen button at the bottom. The title only shows in full screen.
struct PlayerControlsOverlay: View {
    @ObservedObject var engine: AetherEngine
    let session: PlayerSession
    let pip: PictureInPicture
    let isFullscreen: Bool
    let title: String
    let subtitle: String?
    @Binding var scrubSeconds: Double?
    let onToggleFullscreen: () -> Void
    let onInteraction: () -> Void
    let onShowSheet: (PlayerSheet) -> Void

    /// No layer behind the controls; a shadow on the icons keeps them readable on light scenes.
    private static let iconShadowOpacity = 0.6
    private static let iconShadowRadius: CGFloat = 4

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    if isFullscreen { titleBlock }
                    Spacer(minLength: 0)
                    topButtons
                }
                Spacer(minLength: 0)
                if isFullscreen {
                    ScrubBar(
                        engine: engine, scrubSeconds: $scrubSeconds, showsKnob: true,
                        bufferedAheadSeconds: session.buffer.aheadSeconds, barHeight: 4,
                        onInteraction: onInteraction
                    )
                }
                HStack {
                    PlayerTimeLabel(
                        engine: engine, scrubSeconds: scrubSeconds,
                        bufferedAheadSeconds: session.buffer.aheadSeconds
                    )
                    Spacer()
                    if session.activePreference.isAuto, let level = session.level {
                        Text("Auto · \(level.shortName)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(JellyCastColors.textMuted)
                            .lineLimit(1)
                    }
                    PlayerIconButton(
                        systemImage: isFullscreen
                            ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                        label: isFullscreen ? "Exit full screen" : "Full screen", size: 22,
                        action: onToggleFullscreen
                    )
                }
            }
            PlayPauseButton(engine: engine, isStalled: session.buffer.isStalled, onInteraction: onInteraction)
        }
        .shadow(color: .black.opacity(Self.iconShadowOpacity), radius: Self.iconShadowRadius)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.headline).foregroundStyle(JellyCastColors.text)
            if let subtitle {
                Text(subtitle).font(.footnote).foregroundStyle(JellyCastColors.textMuted)
            }
        }
        .lineLimit(1)
        .padding(.top, 6)
        .allowsHitTesting(false)
    }

    private var topButtons: some View {
        HStack(spacing: 4) {
            if pip.isPossible {
                PlayerIconButton(systemImage: "pip.enter", label: "Picture in Picture") {
                    pip.toggle()
                    onInteraction()
                }
            }
            PlayerIconButton(systemImage: "tv", label: "Continue on…") { onShowSheet(.playOn) }
            AirPlayButton().frame(width: PlayerIconButton.hitSize, height: PlayerIconButton.hitSize)
            PlayerIconButton(systemImage: PlayerSheet.tracksSymbol, label: "Audio and subtitles") {
                onShowSheet(.tracks)
            }
            PlayerIconButton(systemImage: "gearshape", label: "Quality") { onShowSheet(.quality) }
        }
    }
}

/// A plain white icon, as in the YouTube player: no glass behind it.
struct PlayerIconButton: View {
    static let hitSize: CGFloat = 44

    let systemImage: String
    let label: LocalizedStringKey
    var size: CGFloat = 19
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(JellyCastColors.text)
                .frame(width: Self.hitSize, height: Self.hitSize)
                .contentShape(.rect)
        }
        .buttonStyle(PressedOpacityButtonStyle())
        .accessibilityLabel(label)
    }
}

/// Auto or a fixed level for the rest of this play; Auto follows the setting for this network.
struct QualitySheet: View {
    let session: PlayerSession

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetTitle(title: String(localized: "Quality"), subtitle: measured)
                CheckedSheetRow(title: autoTitle, isChecked: session.activePreference.isAuto) {
                    choose(autoPreference)
                }
                ForEach(session.offeredLevels, id: \.self) { level in
                    CheckedSheetRow(
                        title: level.label(sourceBitsPerSecond: session.mediaInfo?.bitsPerSecond),
                        isChecked: session.activePreference == .fixed(level)
                    ) {
                        choose(.fixed(level))
                    }
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var autoPreference: QualityPreference {
        let setting = session.networkPreference
        return setting.isAuto ? setting : .auto(upTo: .original)
    }

    private var autoTitle: String {
        guard session.activePreference.isAuto, let level = session.level else { return String(localized: "Auto") }
        return String(localized: "Auto · \(level.shortName)")
    }

    /// What this play measured, or else the last measurement on this network.
    private var measured: String? {
        let bits = session.connectionBitsPerSecond ?? ConnectionMeter.shared.freshBytesPerSecond.map { $0 * 8 }
        return bits.map { String(localized: "Measured \(Format.megabits(Int($0)))") }
    }

    private func choose(_ preference: QualityPreference) {
        dismiss()
        guard preference != session.activePreference else { return }
        Task { await session.changeQuality(to: preference) }
    }
}

/// Only play and pause in the middle; a double tap on either half of the video jumps.
private struct PlayPauseButton: View {
    @ObservedObject var engine: AetherEngine
    let isStalled: Bool
    let onInteraction: () -> Void

    private static let size: CGFloat = 64
    private static let backgroundOpacity = 0.35

    var body: some View {
        if isStalled {
            ProgressView()
                .tint(JellyCastColors.text)
                .controlSize(.large)
                .frame(width: Self.size, height: Self.size)
                .background(.black.opacity(Self.backgroundOpacity), in: .circle)
                .accessibilityLabel("Waiting for the connection")
        } else {
            Button {
                engine.togglePlayPause()
                onInteraction()
            } label: {
                Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(JellyCastColors.text)
                    .frame(width: Self.size, height: Self.size)
                    .background(.black.opacity(Self.backgroundOpacity), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(PressedOpacityButtonStyle())
            .accessibilityLabel("Play or pause")
        }
    }
}

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = UIColor(JellyCastColors.text)
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
