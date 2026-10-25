import SwiftUI

/// What another device plays, with everything known about it: the player's portrait layout
/// with the device's status where the video would be.
struct RemoteNowPlayingScreen: View {
    let remote: RemoteSessions
    let sessionID: String
    let store: LibraryStore
    let onOpen: (Route) -> Void
    /// Plays here, from where the TV was.
    let onPlayHere: (Playable, StreamSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.layout) private var layout
    @State private var lastSeen: RemoteSession?
    @State private var mediaInfo: MediaInfo?
    @State private var segments: [MediaSegment] = []
    @State private var swipe = SwipeToClose()
    @State private var showsPlayOn = false
    /// While the tabs are scrolled up, the header shrinks to a bar so the tab has the room.
    @State private var isHeaderCompact = false
    @State private var scrollToTopRequest = 0
    @State private var tvVolume: TVVolume?

    private static let dismissAnimation = Duration.milliseconds(500)
    private static let headerAnimation = Animation.smooth(duration: 0.4)

    var body: some View {
        let live = remote.session(id: sessionID)
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                JellyCastColors.background
                    .opacity(1 - swipe.progress(height: proxy.size.height))
                    .ignoresSafeArea()
                if let session = live ?? lastSeen {
                    let isStopped = live == nil
                    let size = proxy.size
                    Group {
                        if layout.isRegular, size.width > size.height,
                           store.index?.playable(id: session.item.id) != nil {
                            info(session, arrangement: .split) {
                                statusHeader(
                                    session, isStopped: isStopped, isCompact: false,
                                    width: (size.width * InfoPanelArrangement.splitLeadingFraction).rounded(),
                                    screenHeight: size.height
                                )
                            }
                        } else {
                            VStack(spacing: 0) {
                                statusHeader(
                                    session, isStopped: isStopped, isCompact: isHeaderCompact,
                                    width: size.width, screenHeight: size.height
                                )
                                info(session, arrangement: .column) { EmptyView() }
                            }
                        }
                    }
                    .background { JellyCastColors.background.ignoresSafeArea(edges: .bottom) }
                    .following(swipe, height: proxy.size.height)
                }
            }
        }
        .presentationBackground(.clear)
        .environment(\.jellyfinClient, store.session.client)
        .onChange(of: live, initial: true) { _, session in
            if let session { lastSeen = session }
        }
        .alert(
            "The TV didn't get that",
            isPresented: Binding(get: { remote.commandFailed }, set: { if !$0 { remote.dismissCommandFailure() } })
        ) {}
        .task(id: (live ?? lastSeen)?.item.id) { await loadMediaInfo(itemID: (live ?? lastSeen)?.item.id) }
        .task(id: pairedHost(live)) { await keepVolume(host: pairedHost(live)) }
        .background {
            if let tvVolume, tvVolume.isConnected {
                HardwareVolumeButtons { tvVolume.press($0) }.frame(width: 1, height: 1)
            }
        }
    }

    private func statusHeader(
        _ session: RemoteSession, isStopped: Bool, isCompact: Bool, width: CGFloat, screenHeight: CGFloat
    ) -> some View {
        RemoteStatusHeader(
            session: session, isStopped: isStopped, isCompact: isCompact, width: width, mediaInfo: mediaInfo,
            segments: segments, volume: tvVolume,
            onClose: { dismiss() },
            onExpand: {
                scrollToTopRequest += 1
                withAnimation(Self.headerAnimation) { isHeaderCompact = false }
            },
            onCommand: { command in Task { await remote.send(command, to: session.id) } }
        )
        .gesture(swipe.gesture(height: screenHeight) { remote.shownSessionID = nil })
    }

    @ViewBuilder
    private func info<Header: View>(
        _ session: RemoteSession, arrangement: InfoPanelArrangement, @ViewBuilder header: () -> Header
    ) -> some View {
        if let playable = store.index?.playable(id: session.item.id) {
            ItemInfoPanel(
                playable: playable, mediaInfo: mediaInfo, store: store, arrangement: arrangement,
                playingOn: session.deviceName,
                scrollToTopRequest: scrollToTopRequest,
                onScrolledDown: { scrolledDown in
                    withAnimation(Self.headerAnimation) { isHeaderCompact = scrolledDown }
                }
            ) { selected in
                select(selected, on: session)
            } header: {
                header()
            } actions: {
                if session.canControl, remote.session(id: session.id) != nil {
                    RailCircleButton(systemImage: "tv", label: "Continue on…", size: 34) { showsPlayOn = true }
                        .sheet(isPresented: $showsPlayOn) {
                            PlayOnSheet(
                                playable: playable, remote: remote,
                                handOffTicks: session.position(at: .now), excludedDeviceID: session.deviceID,
                                onPlayHere: { continueHere(playable, from: session) },
                                onHandOff: { handOver(session) }
                            )
                        }
                }
            }
        } else {
            Text(RemoteFormat.title(session.item))
                .font(.title2.weight(.heavy))
                .foregroundStyle(JellyCastColors.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(layout.margin)
        }
    }

    /// Stops the TV, turns a paired Chromecast off (the TV follows over HDMI) and plays on.
    private func continueHere(_ playable: Playable, from session: RemoteSession) {
        var resumed = playable
        resumed.resume(atTicks: session.position(at: .now))
        let streams = StreamSelection(
            audio: session.audioStreamIndex,
            subtitle: session.subtitleStreamIndex ?? RemoteCommand.subtitlesOff
        )
        dismiss()
        Task {
            // The player is a full-screen cover too; it can't present while this one closes.
            try? await Task.sleep(for: Self.dismissAnimation)
            onPlayHere(resumed, streams)
        }
        Task { await remote.handBack(session) }
    }

    /// Another TV takes it over: this one stops, and the TV bar follows the new one.
    private func handOver(_ session: RemoteSession) {
        dismiss()
        Task { await remote.send(.stop, to: session.id) }
    }

    /// On a TV that takes commands the choice plays there, resuming like on the TV itself;
    /// otherwise it opens the item's page.
    private func select(_ playable: Playable, on session: RemoteSession) {
        guard session.canControl, remote.session(id: session.id) != nil else { return open(playable) }
        let startTicks = playable.watch.played ? 0 : playable.watch.positionTicks
        Task { await remote.send(.play(itemID: playable.id, startTicks: startTicks), to: session.id) }
    }

    private func open(_ playable: Playable) {
        dismiss()
        switch playable {
        case .movie(let movie): onOpen(.movie(id: movie.id))
        case .episode(let episode): onOpen(.series(id: episode.seriesID))
        }
    }

    /// A paired Chromecast that takes commands: its volume can be set over the remote connection.
    private func pairedHost(_ session: RemoteSession?) -> String? {
        guard let session, session.canControl else { return nil }
        return remote.paired.all.first { $0.deviceID == session.deviceID }?.host
    }

    private func keepVolume(host: String?) async {
        guard let host else {
            tvVolume = nil
            return
        }
        let volume = TVVolume(host: host)
        tvVolume = volume
        await volume.run()
    }

    private func loadMediaInfo(itemID: String?) async {
        mediaInfo = nil
        segments = []
        guard let itemID else { return }
        let session = store.session
        async let segmentsRequest = try? session.client.mediaSegments(itemID: itemID)
        mediaInfo = try? await session.client.mediaInfo(itemID: itemID, userID: session.userID)
        segments = await segmentsRequest ?? []
    }
}

/// In place of the video: the still dimmed, which device plays it, and how far it is.
private struct RemoteStatusHeader: View {
    let session: RemoteSession
    let isStopped: Bool
    var isCompact = false
    let width: CGFloat
    let mediaInfo: MediaInfo?
    var segments: [MediaSegment] = []
    var volume: TVVolume?
    let onClose: () -> Void
    var onExpand: () -> Void = {}
    let onCommand: (RemoteCommand) -> Void

    /// Hides the pill right away: the TV's new position only arrives with its next check-in.
    @State private var skippedStartTicks: Int64?

    private static let aspectRatio: CGFloat = 16 / 9
    private static let compactScrimOpacity = 0.88
    private static let controlsLift: CGFloat = 0.3
    private static let scrim = LinearGradient(
        stops: [
            .init(color: JellyCastColors.background.opacity(0.7), location: 0),
            .init(color: JellyCastColors.background.opacity(0.78), location: 0.55),
            .init(color: JellyCastColors.background.opacity(0.96), location: 1),
        ],
        startPoint: .top, endPoint: .bottom
    )

    /// One header that rolls up: the controls lift away and fade while the bar fades in over the
    /// same still, and its height animates, so the tabs below glide along instead of jumping.
    var body: some View {
        let fullHeight = (width / Self.aspectRatio).rounded()
        ZStack(alignment: .top) {
            RemoteImage(ref: session.item.image, type: session.item.imageType, width: width)
                .frame(width: width, height: fullHeight)
            Self.scrim.frame(height: fullHeight)
            JellyCastColors.background.opacity(isCompact ? Self.compactScrimOpacity : 0)
            controls
                .frame(width: width, height: fullHeight)
                .opacity(isCompact ? 0 : 1)
                .offset(y: isCompact ? -fullHeight * Self.controlsLift : 0)
                .allowsHitTesting(!isCompact)
            RemoteCompactHeader(
                session: session, isControllable: isControllable, skippable: skippable(at:),
                onClose: onClose, onExpand: onExpand, onSkip: skip, onCommand: onCommand
            )
            .opacity(isCompact ? 1 : 0)
            .allowsHitTesting(isCompact)
            .accessibilityHidden(!isCompact)
        }
        .frame(width: width, height: isCompact ? RemoteCompactHeader.height : fullHeight, alignment: .top)
        .background(.black)
        .clipped()
    }

    private var controls: some View {
        VStack(spacing: 0) {
            if isControllable {
                RemoteTopBar(
                    session: session, mediaInfo: mediaInfo, volume: volume, onClose: onClose, onCommand: onCommand
                )
                Spacer(minLength: 0)
                RemoteTransport(session: session, volume: volume, onCommand: onCommand)
                Spacer(minLength: 0)
                RemoteScrubber(session: session, skippable: skippable(at:), onSkip: skip) {
                    onCommand(.seek(positionTicks: $0))
                }
            } else {
                HStack {
                    GlassCircleButton(systemImage: "chevron.down", label: "Close", action: onClose)
                    Spacer()
                }
                Spacer(minLength: 0)
                status
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    timeline(at: context.date)
                }
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .accessibilityHidden(isCompact)
    }

    private var isControllable: Bool { session.canControl && !isStopped }

    private func skippable(at date: Date) -> MediaSegment? {
        let segment = MediaSegment.skippable(in: segments, at: Ticks.seconds(session.position(at: date)))
        return segment?.StartTicks == skippedStartTicks ? nil : segment
    }

    private func skip(_ segment: MediaSegment) {
        skippedStartTicks = segment.StartTicks
        onCommand(.seek(positionTicks: segment.EndTicks))
    }

    private var status: some View {
        VStack(spacing: 6) {
            Image(systemName: "tv")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(JellyCastColors.accent)
            Text(headline)
                .font(.title3.weight(.bold))
                .foregroundStyle(JellyCastColors.text)
            if let method = RemoteFormat.playMethod(session.playMethod), !isStopped {
                Text(method)
                    .font(.subheadline)
                    .foregroundStyle(JellyCastColors.textMuted)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        let device = session.deviceName
        if isStopped { return String(localized: "Stopped on \(device)") }
        return session.isPaused
            ? String(localized: "Paused on \(device)") : String(localized: "Playing on \(device)")
    }

    private func timeline(at date: Date) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(RemoteFormat.clock(session.position(at: date)))
                    .foregroundStyle(JellyCastColors.text)
                Spacer()
                if let remaining = RemoteFormat.remainingTicks(session, at: date) {
                    Text(Format.remaining(remaining) ?? "")
                        .foregroundStyle(JellyCastColors.textMuted)
                }
            }
            .font(.footnote.weight(.medium).monospacedDigit())
            WatchProgressBar(progress: RemoteFormat.progress(session, at: date))
        }
        .padding(.horizontal, 8)
    }
}

/// The header while a tab is scrolled up: what plays, pause and how far, in a third of the room.
private struct RemoteCompactHeader: View {
    let session: RemoteSession
    let isControllable: Bool
    let skippable: (Date) -> MediaSegment?
    let onClose: () -> Void
    let onExpand: () -> Void
    let onSkip: (MediaSegment) -> Void
    let onCommand: (RemoteCommand) -> Void

    private static let pauseSize: CGFloat = 44
    private static let progressHeight: CGFloat = 3
    private static let topPadding: CGFloat = 12
    private static let bottomPadding: CGFloat = 10
    private static let barSpacing: CGFloat = 10
    static let height = topPadding + pauseSize + barSpacing + progressHeight + bottomPadding

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: Self.barSpacing) {
                HStack(spacing: 12) {
                    GlassCircleButton(systemImage: "chevron.down", label: "Close", action: onClose)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(RemoteFormat.title(session.item))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(JellyCastColors.text)
                        Text(RemoteFormat.where(session, at: context.date))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(JellyCastColors.textMuted)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Text("Shows the controls"))
                    if isControllable {
                        if let segment = skippable(context.date) {
                            SkipSegmentPill(segment: segment) { onSkip(segment) }
                        }
                        pauseButton
                    }
                }
                WatchProgressBar(
                    progress: RemoteFormat.progress(session, at: context.date), height: Self.progressHeight
                )
            }
        }
        .padding(.top, Self.topPadding)
        .padding(.horizontal, 12)
        .padding(.bottom, Self.bottomPadding)
        .contentShape(.rect)
        .onTapGesture(perform: onExpand)
    }

    private var pauseButton: some View {
        Button {
            onCommand(session.isPaused ? .unpause : .pause)
        } label: {
            Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(JellyCastColors.text)
                .frame(width: Self.pauseSize, height: Self.pauseSize)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(session.isPaused ? "Play" : "Pause")
    }
}

#Preview {
    let store = LibraryStore(session: .preview, snapshot: .preview)
    VStack {
        RemoteStatusHeader(
            session: .preview, isStopped: false, width: 402, mediaInfo: nil, onClose: {}, onCommand: { _ in }
        )
        RemoteStatusHeader(
            session: .preview, isStopped: false, isCompact: true, width: 402, mediaInfo: nil,
            onClose: {}, onCommand: { _ in }
        )
    }
    .environment(\.jellyfinClient, store.session.client)
    .preferredColorScheme(.dark)
}

private extension Playable {
    /// The iPhone player starts where `watch` says, so the TV's position goes there.
    mutating func resume(atTicks ticks: Int64) {
        switch self {
        case .movie(var movie):
            movie.watch.played = false
            movie.watch.positionTicks = ticks
            self = .movie(movie)
        case .episode(var episode):
            episode.watch.played = false
            episode.watch.positionTicks = ticks
            self = .episode(episode)
        }
    }
}
