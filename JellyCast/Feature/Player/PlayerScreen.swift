import AetherEngine
import SwiftUI

/// The player: in portrait the video on top with the info below, turned sideways full screen.
/// On the iPad landscape puts the info beside the video, and full screen is a choice.
/// A swipe down leaves full screen, or else hands the video to the mini player; the play itself
/// lives in `NowPlaying`.
struct PlayerScreen: View {
    let nowPlaying: NowPlaying
    let session: PlayerSession
    @ObservedObject var engine: AetherEngine
    let store: LibraryStore

    @State private var showsControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var scrubSeconds: Double?
    @State private var isFullscreen = false
    @State private var isVideoOnly = false
    @State private var swipe = SwipeToClose()
    @State private var sheet: PlayerSheet?
    @Environment(RemoteSessions.self) private var remote: RemoteSessions?
    @Environment(\.layout) private var layout
    @State private var panelMemory = InfoPanelMemory()

    private static let controlsTimeout = Duration.seconds(3)
    private static let videoAspectRatio: CGFloat = 16 / 9

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            let fullscreen = layout.isRegular ? isVideoOnly : landscape
            ZStack(alignment: .top) {
                Color.black.opacity(1 - swipe.progress(height: proxy.size.height)).ignoresSafeArea()
                Group {
                    if layout.isRegular, landscape, !isVideoOnly {
                        infoPanel(arrangement: .split) {
                            videoArea(fullscreen: false, insets: proxy.safeAreaInsets)
                                .frame(height: splitVideoHeight(width: proxy.size.width))
                                .gesture(swipe.gesture(height: proxy.size.height, onClose: swipedDown))
                                .zIndex(1)
                        }
                        // Black like the video's own bars, so the picture doesn't sit in a box.
                        .background { Color.black.ignoresSafeArea(edges: .bottom) }
                    } else {
                        VStack(spacing: 0) {
                            videoArea(fullscreen: fullscreen, insets: proxy.safeAreaInsets)
                                .frame(height: fullscreen ? nil : proxy.size.width / Self.videoAspectRatio)
                                .ignoresSafeArea(edges: fullscreen ? .all : [])
                                .gesture(
                                    swipe.gesture(
                                        height: proxy.size.height, slidesAway: !fullscreen,
                                        onClose: swipedDown
                                    )
                                )
                                .zIndex(1)
                            if !fullscreen {
                                infoPanel(arrangement: .column) { EmptyView() }
                                    .background { JellyCastColors.background.ignoresSafeArea(edges: .bottom) }
                            }
                        }
                    }
                }
                .following(swipe, height: proxy.size.height)
            }
            .onChange(of: fullscreen, initial: true) { _, value in isFullscreen = value }
        }
        .statusBarHidden(isFullscreen)
        .persistentSystemOverlays(isFullscreen ? .hidden : .automatic)
        .presentationBackground(.clear)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .tracks: PlayerTrackSheet(engine: engine, session: session)
            case .quality: QualitySheet(session: session)
            case .playOn:
                if let remote {
                    PlayOnSheet(
                        playable: session.playable, remote: remote,
                        handOffTicks: Int64(engine.clock.currentTime * Double(Ticks.perSecond)),
                        handOffStreams: session.currentStreams,
                        onPlayHere: nil, onHandOff: { nowPlaying.close() }
                    )
                }
            }
        }
        .onChange(of: sheet) { _, sheet in
            if sheet == nil { scheduleHide() } else { showControls() }
        }
        .environment(\.jellyfinClient, store.session.client)
        .task { await followDeviceRotation() }
        .onChange(of: session.startPhase == .started, initial: true) { _, started in
            if started { scheduleHide() }
        }
        .onChange(of: engine.state == .playing) { _, playing in
            if playing, showsControls { scheduleHide() }
        }
    }

    /// The video fills the split's left column edge to edge.
    private func splitVideoHeight(width: CGFloat) -> CGFloat {
        (width * InfoPanelArrangement.splitLeadingFraction).rounded() / Self.videoAspectRatio
    }

    private func infoPanel<Header: View>(
        arrangement: InfoPanelArrangement, @ViewBuilder header: () -> Header
    ) -> some View {
        ItemInfoPanel(
            playable: session.playable, mediaInfo: session.mediaInfo, store: store, arrangement: arrangement,
            surface: arrangement == .split ? .black : JellyCastColors.background, memory: panelMemory
        ) { next in
            nowPlaying.play(next, store: store)
        } header: {
            header()
        } actions: {
            if remote != nil {
                RailCircleButton(systemImage: "tv", label: "Continue on…", size: 34) { sheet = .playOn }
            }
        }
    }

    private func videoArea(fullscreen: Bool, insets: EdgeInsets) -> some View {
        let started = session.startPhase == .started
        return ZStack {
            Color.black
            AetherPlayerSurface(engine: engine)
            if started {
                TapToSeekLayer(engine: engine, onSingleTap: toggleControls)
            }
            PlayerSubtitleOverlay(engine: engine, clock: engine.clock).allowsHitTesting(false)
            if showsControls, started {
                PlayerControlsOverlay(
                    engine: engine, session: session, pip: nowPlaying.pip, isFullscreen: fullscreen,
                    title: title, subtitle: subtitle,
                    scrubSeconds: $scrubSeconds, onToggleFullscreen: toggleFullscreen,
                    onInteraction: scheduleHide,
                    onShowSheet: { sheet = $0 }
                )
                .padding(controlsPadding(fullscreen: fullscreen, insets: insets))
                .transition(.opacity)
            }
            if !fullscreen, started {
                ScrubBar(
                    engine: engine, scrubSeconds: $scrubSeconds, showsKnob: showsControls,
                    bufferedAheadSeconds: session.buffer.aheadSeconds, barHeight: 3,
                    onInteraction: scheduleHide
                )
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: 13)
            }
            SegmentPills(session: session, clock: engine.clock)
                .padding(.trailing, max(insets.trailing, 12))
                .padding(.bottom, segmentPillsBottom(fullscreen: fullscreen, insets: insets))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            if started, session.buffer.isStalled, !showsControls, session.loadError == nil {
                StallIndicator().allowsHitTesting(false)
            }
            if let loadError = session.loadError {
                PlayerErrorView(message: loadError, session: session)
            } else if !started {
                StartOverlay(session: session)
            }
        }
    }

    private func controlsPadding(fullscreen: Bool, insets: EdgeInsets) -> EdgeInsets {
        guard fullscreen else { return EdgeInsets(top: 4, leading: 14, bottom: 6, trailing: 6) }
        return EdgeInsets(
            top: max(insets.top, 12), leading: max(insets.leading, 20),
            bottom: max(insets.bottom, 8), trailing: max(insets.trailing, 20)
        )
    }

    private func segmentPillsBottom(fullscreen: Bool, insets: EdgeInsets) -> CGFloat {
        switch (fullscreen, showsControls) {
        case (true, true): 110
        case (true, false): max(insets.bottom, 24)
        case (false, true): 56
        case (false, false): 14
        }
    }

    private func toggleFullscreen() {
        setFullscreen(!isFullscreen)
        scheduleHide()
    }

    private func swipedDown() {
        if isFullscreen {
            setFullscreen(false)
        } else {
            nowPlaying.minimize()
        }
    }

    /// The iPhone turns the screen; the iPad, held either way, switches to the video alone and back.
    private func setFullscreen(_ fullscreen: Bool) {
        if layout.isRegular {
            withAnimation(.easeOut(duration: 0.2)) { isVideoOnly = fullscreen }
        } else {
            OrientationLock.rotate(to: fullscreen ? .landscape : .portrait)
        }
    }

    private func followDeviceRotation() async {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        defer { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
        for await _ in NotificationCenter.default.notifications(named: UIDevice.orientationDidChangeNotification) {
            OrientationLock.deviceRotated(to: UIDevice.current.orientation)
        }
    }

    private var title: String {
        switch session.playable {
        case .movie(let movie): movie.name
        case .episode(let episode): episode.seriesName
        }
    }

    private var subtitle: String? {
        switch session.playable {
        case .movie(let movie): movie.year.map(String.init)
        case .episode(let episode): Format.joined([Format.seasonEpisode(episode), episode.name])
        }
    }

    private func toggleControls() {
        withAnimation(.easeOut(duration: 0.2)) { showsControls.toggle() }
        if showsControls { scheduleHide() }
    }

    /// While a sheet is open the controls stay; they hide again a while after it closes.
    private func showControls() {
        hideControlsTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { showsControls = true }
    }

    private func scheduleHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: Self.controlsTimeout)
            guard !Task.isCancelled, engine.state == .playing, scrubSeconds == nil, sheet == nil else { return }
            withAnimation(.easeOut(duration: 0.2)) { showsControls = false }
        }
    }
}

enum PlayerSheet: Identifiable {
    case tracks, quality, playOn

    static let tracksSymbol = "speaker.wave.2.bubble"

    var id: Self { self }
}

/// The slow-connection hint when the buffer runs down, "Skip intro" while an intro, recap or preview plays,
/// and "Next episode" in the credits.
private struct SegmentPills: View {
    let session: PlayerSession
    @ObservedObject var clock: PlaybackClock

    private static let hintTimeout = Duration.seconds(10)

    var body: some View {
        let now = clock.currentTime
        Group {
            if let hint = session.buffer.hint {
                pill(
                    hintTitle(hint), systemImage: "wifi.exclamationmark", action: session.buffer.dismissHint
                )
                    .task(id: hint) {
                        try? await Task.sleep(for: Self.hintTimeout)
                        if !Task.isCancelled { session.buffer.dismissHint() }
                    }
            } else if let segment = session.skippableSegment(at: now) {
                pill(segment.skipTitle, systemImage: "forward.end.fill") {
                    Task { await session.engine.seek(to: segment.endSeconds) }
                }
            } else if session.isInCredits(at: now), let next = session.nextItem {
                pill(nextTitle(next), systemImage: "forward.fill") {
                    Task { await session.playNext() }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.skippableSegment(at: now)?.StartTicks)
        .animation(.easeOut(duration: 0.2), value: session.buffer.hint)
    }

    private func nextTitle(_ next: Playable) -> String {
        switch next {
        case .episode(let episode) where session.queue == nil:
            String(localized: "Next episode · \(Format.seasonEpisode(episode))")
        case .episode(let episode):
            String(localized: "Next · \(episode.seriesName) \(Format.seasonEpisode(episode))")
        case .movie(let movie):
            String(localized: "Next · \(movie.name)")
        }
    }

    private func hintTitle(_ hint: BufferWatch.Hint) -> String {
        switch hint {
        case .lowerQualityHelps(let level):
            String(localized: "Slow connection · \(level.shortName) under the gear plays smoother")
        case .connectionTooSlow:
            String(localized: "The connection can't keep up with this file")
        }
    }

    private func pill(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(JellyCastColors.text)
                .padding(.horizontal, 18)
                .frame(height: 40)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }
}

/// The engine keeps the decoded cues around the play position; only those on screen now are drawn.
private struct PlayerSubtitleOverlay: View {
    @ObservedObject var engine: AetherEngine
    @ObservedObject var clock: PlaybackClock

    private static let textBottomFraction = 0.07
    private static let textSizeFraction = 0.05
    private static let textSizeRange: ClosedRange<CGFloat> = 13...30

    var body: some View {
        GeometryReader { proxy in
            let videoRect = fittedVideoRect(in: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(visibleCues) { cue in
                    switch cue.body {
                    case .image(let image):
                        Image(decorative: image.cgImage, scale: 1)
                            .resizable()
                            .frame(width: image.position.width * videoRect.width,
                                   height: image.position.height * videoRect.height)
                            .offset(x: videoRect.minX + image.position.minX * videoRect.width,
                                    y: videoRect.minY + image.position.minY * videoRect.height)
                    case .text, .richText:
                        Text(cue.text ?? "")
                            .font(.system(size: textSize(videoRect), weight: .medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black, radius: 2)
                            .padding(.horizontal, 12)
                            .padding(.bottom, videoRect.height * Self.textBottomFraction)
                            .frame(width: videoRect.width, height: videoRect.height, alignment: .bottom)
                            .offset(x: videoRect.minX, y: videoRect.minY)
                    }
                }
            }
        }
    }

    private var visibleCues: [SubtitleCue] {
        let now = clock.sourceTime
        return engine.subtitleCues.filter { $0.startTime <= now && now < $0.endTime }
    }

    private func textSize(_ videoRect: CGRect) -> CGFloat {
        min(max(videoRect.height * Self.textSizeFraction, Self.textSizeRange.lowerBound), Self.textSizeRange.upperBound)
    }

    private func fittedVideoRect(in size: CGSize) -> CGRect {
        let width = CGFloat(engine.sourceVideoWidth)
        let height = CGFloat(engine.sourceVideoHeight)
        guard width > 0, height > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = min(size.width / width, size.height / height)
        let fitted = CGSize(width: width * scale, height: height * scale)
        return CGRect(
            x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2,
            width: fitted.width, height: fitted.height
        )
    }
}
