import SwiftUI

/// Close, which device, its audio and subtitles, and stop.
struct RemoteTopBar: View {
    let session: RemoteSession
    let mediaInfo: MediaInfo?
    var volume: TVVolume?
    let onClose: () -> Void
    let onCommand: (RemoteCommand) -> Void

    @State private var showsTracks = false
    @State private var showsVolume = false

    private static let volumeShownFor = Duration.seconds(2)

    var body: some View {
        HStack(spacing: 4) {
            GlassCircleButton(systemImage: "chevron.down", label: "Close", action: onClose)
            Spacer(minLength: 0)
            if session.item.seriesName != nil {
                PlayerIconButton(systemImage: "forward.end.fill", label: "Next episode") { onCommand(.nextEpisode) }
            }
            if let mediaInfo, session.playMethod == .directPlay {
                PlayerIconButton(systemImage: PlayerSheet.tracksSymbol, label: "Audio and subtitles") {
                    showsTracks = true
                }
                .sheet(isPresented: $showsTracks) {
                    RemoteTrackSheet(session: session, mediaInfo: mediaInfo, onCommand: onCommand)
                }
            }
            PlayerIconButton(systemImage: "stop.fill", label: "Stop on the TV") { onCommand(.stop) }
        }
        .overlay {
            Group {
                if showsVolume, let level = volume?.volume {
                    TVVolumeLevel(volume: level)
                } else {
                    Label(session.deviceName, systemImage: "tv")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JellyCastColors.text)
                        .labelStyle(DeviceLabelStyle())
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Self.titleInset)
            .animation(.easeOut(duration: 0.2), value: showsVolume)
        }
        .task(id: volume?.changedAt) {
            guard volume?.changedAt != nil else { return }
            showsVolume = true
            try? await Task.sleep(for: Self.volumeShownFor)
            if !Task.isCancelled { showsVolume = false }
        }
    }

    /// Keeps the device name clear of the buttons on both sides.
    private static let titleInset: CGFloat = 136
}

/// The TV's volume for a moment after a press, in place of the device name.
private struct TVVolumeLevel: View {
    let volume: AndroidTVControl.Volume

    private static let barWidth: CGFloat = 64

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: volume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(JellyCastColors.accent)
            if volume.max > 0 {
                WatchProgressBar(progress: Double(volume.level) / Double(volume.max))
                    .frame(width: Self.barWidth)
            } else {
                Text(verbatim: "\(volume.level)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(JellyCastColors.text)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("TV volume \(volume.level)"))
    }
}

private struct DeviceLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(JellyCastColors.accent)
            configuration.title
        }
    }
}

/// The TV's own tracks, by the server's stream index. Only offered for direct play: there every
/// track is in the stream the TV plays.
private struct RemoteTrackSheet: View {
    let session: RemoteSession
    let mediaInfo: MediaInfo
    let onCommand: (RemoteCommand) -> Void

    var body: some View {
        TrackSheet(
            audio: TrackSheet.choices(mediaInfo.audioStreams),
            selectedAudio: session.audioStreamIndex,
            subtitles: TrackSheet.subtitleChoices(mediaInfo.subtitleStreams),
            selectedSubtitle: session.subtitleStreamIndex == RemoteCommand.subtitlesOff
                ? nil : session.subtitleStreamIndex,
            onSelectAudio: { onCommand(.audioStream(index: $0)) },
            onSelectSubtitle: { onCommand(.subtitleStream(index: $0 ?? RemoteCommand.subtitlesOff)) }
        )
    }
}

/// Back 10 s, play or pause, forward 10 s; with the TV's volume on the sides once it can be set.
struct RemoteTransport: View {
    let session: RemoteSession
    var volume: TVVolume?
    let onCommand: (RemoteCommand) -> Void

    private static let volumeSize: CGFloat = 40

    private static let skipTicks = 10 * Ticks.perSecond
    private static let skipSize: CGFloat = 48
    private static let playSize: CGFloat = 68

    var body: some View {
        let showsVolume = volume?.isConnected == true
        HStack(spacing: showsVolume ? 26 : 44) {
            if showsVolume { volumeButton("speaker.wave.1.fill", label: "TV volume down", key: .volumeDown) }
            skipButton("gobackward.10", label: "Back 10 seconds", by: -Self.skipTicks)
            Button {
                onCommand(session.isPaused ? .unpause : .pause)
            } label: {
                Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(JellyCastColors.text)
                    .frame(width: Self.playSize, height: Self.playSize)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel(session.isPaused ? "Play" : "Pause")
            skipButton("goforward.10", label: "Forward 10 seconds", by: Self.skipTicks)
            if showsVolume { volumeButton("speaker.wave.3.fill", label: "TV volume up", key: .volumeUp) }
        }
    }

    private func volumeButton(_ systemImage: String, label: LocalizedStringKey, key: AndroidTVControl.Key) -> some View {
        Button {
            volume?.press(key)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(JellyCastColors.text)
                .frame(width: Self.volumeSize, height: Self.volumeSize)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }

    private func skipButton(_ systemImage: String, label: LocalizedStringKey, by ticks: Int64) -> some View {
        Button {
            let target = session.position(at: .now) + ticks
            let end = session.item.runtimeTicks ?? target
            onCommand(.seek(positionTicks: min(max(target, 0), end)))
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(JellyCastColors.text)
                .frame(width: Self.skipSize, height: Self.skipSize)
                .contentShape(.circle)
        }
        .buttonStyle(PressedOpacityButtonStyle())
        .accessibilityLabel(label)
    }
}

/// The time and a bar to drag; the TV seeks once the finger lets go. During an intro, recap or
/// preview the skip pill takes the place of the time left.
struct RemoteScrubber: View {
    let session: RemoteSession
    var skippable: (Date) -> MediaSegment? = { _ in nil }
    var onSkip: (MediaSegment) -> Void = { _ in }
    let onSeek: (Int64) -> Void

    @State private var scrubFraction: Double?

    private static let knobSize: CGFloat = 14
    private static let barHeight: CGFloat = 4
    private static let touchHeight: CGFloat = 28

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fraction = scrubFraction ?? RemoteFormat.progress(session, at: context.date)
            VStack(spacing: 4) {
                times(fraction: fraction, at: context.date)
                bar(fraction: fraction)
            }
        }
        .padding(.horizontal, 8)
    }

    private func times(fraction: Double, at date: Date) -> some View {
        let runtime = session.item.runtimeTicks ?? 0
        let position = scrubFraction.map { Int64($0 * Double(runtime)) } ?? session.position(at: date)
        let skip = scrubFraction == nil ? skippable(date) : nil
        return HStack {
            Text(Format.joined([
                RemoteFormat.clock(position), session.isPaused ? String(localized: "paused") : nil,
            ]))
            .foregroundStyle(JellyCastColors.text)
            Spacer()
            Text(Format.remaining(max(runtime - position, 0)) ?? "")
                .foregroundStyle(JellyCastColors.textMuted)
                .opacity(skip == nil ? 1 : 0)
                .overlay(alignment: .trailing) {
                    if let skip { SkipSegmentPill(segment: skip) { onSkip(skip) }.fixedSize() }
                }
        }
        .font(.footnote.weight(.medium).monospacedDigit())
        .animation(.easeOut(duration: 0.2), value: skip)
    }

    private func bar(fraction: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                WatchProgressBar(progress: fraction, height: Self.barHeight)
                Circle()
                    .fill(JellyCastColors.text)
                    .frame(width: Self.knobSize, height: Self.knobSize)
                    .offset(x: width * fraction - Self.knobSize / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in scrubFraction = min(max(value.location.x / width, 0), 1) }
                    .onEnded { _ in
                        if let scrubFraction, let runtime = session.item.runtimeTicks {
                            onSeek(Int64(scrubFraction * Double(runtime)))
                        }
                        scrubFraction = nil
                    }
            )
        }
        .frame(height: Self.touchHeight)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue(Text(RemoteFormat.clock(session.position(at: .now))))
    }
}

/// "Skip intro" as a glass capsule, sending the TV to the end of the segment.
struct SkipSegmentPill: View {
    let segment: MediaSegment
    let action: () -> Void

    private static let height: CGFloat = 32

    var body: some View {
        Button(action: action) {
            Label(segment.skipTitle, systemImage: "forward.end.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(JellyCastColors.text)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: Self.height)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }
}
