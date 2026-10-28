import AVFoundation
import AetherEngine
import OSLog
import SwiftUI

/// The play that outlives the player screen: shown full size, minimized to the mini player, or none.
@Observable
final class NowPlaying {
    private(set) var session: PlayerSession?
    private(set) var startError: String?
    var isExpanded = false {
        didSet { OrientationLock.playerExpanded(isExpanded) }
    }
    /// The mini player's size, kept between plays: small in the corner, or the full portrait width.
    var isMiniPlayerLarge = false
    let pip = PictureInPicture()
    let system = SystemNowPlaying()
    private var detachedPlayer: (layer: AVPlayerLayer, player: AVPlayer)?
    private var backgroundHandOff: Task<Void, Never>?

    private static let logger = Logger(subsystem: "nl.jellycast.ios", category: "player")
    private static let pictureInPictureStartWait = Duration.seconds(1)

    func play(
        _ playable: Playable, store: LibraryStore, streams: StreamSelection? = nil, queue: PlayQueue? = nil
    ) {
        startError = nil
        isExpanded = true
        if let session {
            session.follow(playable, queue: queue)
            guard session.playable.id != playable.id else { return }
            Task { await session.play(playable, streams: streams) }
            return
        }
        do {
            let session = PlayerSession(playable: playable, engine: try AetherEngine(), store: store)
            session.requestedStreams = streams
            session.follow(playable, queue: queue)
            self.session = session
            Task { await session.load() }
        } catch {
            isExpanded = false
            startError = String(localized: "The player could not start.")
        }
    }

    func dismissStartError() {
        startError = nil
    }

    func minimize() {
        isExpanded = false
    }

    func close() {
        guard let session else { return }
        self.session = nil
        isExpanded = false
        backgroundHandOff?.cancel()
        detachedPlayer = nil
        system.clear()
        session.stop()
        session.engine.stop()
    }

    /// iOS pauses a player whose video is on screen when the app leaves. Without its layer the
    /// native route plays on as sound; the software route drops its video by itself. The layer
    /// stays until PiP had its chance: the automatic start can come after the scene backgrounds,
    /// and a window around a layer without a player never opens.
    func enteredBackground() {
        guard let engine = session?.engine, !pip.isActive else { return }
        Self.logger.info(
            "Background: PiP possible \(self.pip.isPossible, privacy: .public), route \(engine.videoRoute.rawValue, privacy: .public)"
        )
        let wasPlaying = engine.state == .playing
        backgroundHandOff?.cancel()
        backgroundHandOff = Task {
            if pip.isPossible {
                do { try await Task.sleep(for: Self.pictureInPictureStartWait) } catch { return }
            }
            guard !pip.isActive, let layer = engine.nativePlayerLayer, let player = layer.player else { return }
            layer.player = nil
            detachedPlayer = (layer, player)
            if wasPlaying, engine.state != .playing { engine.play() }
            Self.logger.info("In the background without PiP, playing on as sound")
        }
    }

    func becameActive() {
        backgroundHandOff?.cancel()
        backgroundHandOff = nil
        pip.stopIfActive()
        if let detachedPlayer, detachedPlayer.layer.player == nil {
            detachedPlayer.layer.player = detachedPlayer.player
        }
        detachedPlayer = nil
        guard let engine = session?.engine, engine.needsForegroundVideoRestore else { return }
        Task {
            do {
                try await engine.reloadAtCurrentPosition()
            } catch is CancellationError {
            } catch {
                Self.logger.error("Restoring the video after the background failed: \(error)")
            }
        }
    }

    /// At the end of an item: the next item of the list or the next episode, or the end of the play.
    func itemEnded() {
        guard let session else { return }
        if session.nextItem != nil {
            Task { await session.playNext() }
        } else {
            close()
        }
    }
}

/// Keeps reporting and PiP going for as long as something plays, whichever screen shows it.
struct NowPlayingObserver: View {
    let nowPlaying: NowPlaying
    let session: PlayerSession
    @ObservedObject var engine: AetherEngine
    let client: JellyfinClient

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: session.playable.id) {
                await nowPlaying.system.show(session.playable, engine: engine, client: client)
            }
            .onReceive(engine.$state) { state in
                session.stateChanged(state)
                playbackChanged()
                if state == .ended { nowPlaying.itemEnded() }
            }
            .onReceive(engine.$isBuffering) { session.bufferingChanged($0) }
            .onReceive(engine.$duration) { _ in playbackChanged() }
            .onReceive(engine.seekEvents) { event in
                guard case .landed = event.outcome else { return }
                session.seeked()
                playbackChanged()
            }
            .onReceive(engine.$videoRoute) { _ in attachPictureInPicture() }
            .onReceive(engine.$currentAVPlayer) { _ in attachPictureInPicture() }
            .onReceive(engine.$softwarePiPSource) { _ in attachPictureInPicture() }
    }

    /// `@Published` sends before the value is stored, and the route is published before its
    /// layer exists; reading them a turn later sees both.
    private func attachPictureInPicture() {
        Task { nowPlaying.pip.attach(to: engine) }
    }

    private func playbackChanged() {
        Task {
            nowPlaying.system.update()
            nowPlaying.pip.playbackChanged()
        }
    }
}

/// The small player above the tab bar after a swipe down: the video keeps playing; a tap opens
/// the player again, a pinch switches between the corner size and the full portrait width.
struct MiniPlayer: View {
    let nowPlaying: NowPlaying
    let session: PlayerSession
    @ObservedObject var engine: AetherEngine
    let width: CGFloat

    @GestureState private var pinchScale: CGFloat = 1

    static let smallWidth: CGFloat = 200
    private static let cornerRadius: CGFloat = 12
    private static let pinchThreshold: CGFloat = 0.15
    private static let pinchFeedbackRange: ClosedRange<CGFloat> = 0.8...1.25

    var body: some View {
        ZStack {
            Color.black
            AetherPlayerSurface(engine: engine)
            if session.loadError != nil {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(JellyCastColors.text)
                    .accessibilityLabel("This item doesn't play")
            } else if session.startPhase != .started || session.buffer.isStalled {
                ProgressView().tint(JellyCastColors.text)
            }
            VStack {
                HStack {
                    PlayerIconButton(
                        systemImage: engine.state == .playing ? "pause.fill" : "play.fill",
                        label: "Play or pause", size: iconSize
                    ) { engine.togglePlayPause() }
                    Spacer()
                    PlayerIconButton(systemImage: "xmark", label: "Close", size: iconSize) { nowPlaying.close() }
                }
                .shadow(color: .black.opacity(0.6), radius: 4)
                Spacer()
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .clipShape(.rect(cornerRadius: Self.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(JellyCastColors.rail))
        .contentShape(.rect(cornerRadius: Self.cornerRadius))
        .scaleEffect(
            min(max(pinchScale, Self.pinchFeedbackRange.lowerBound), Self.pinchFeedbackRange.upperBound),
            anchor: .bottomTrailing
        )
        .onTapGesture { nowPlaying.isExpanded = true }
        .gesture(pinch)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(session.playable.name)
    }

    private var iconSize: CGFloat { nowPlaying.isMiniPlayerLarge ? 19 : 15 }

    private var pinch: some Gesture {
        MagnifyGesture()
            .updating($pinchScale) { value, scale, _ in scale = value.magnification }
            .onEnded { value in
                let large: Bool
                if value.magnification > 1 + Self.pinchThreshold {
                    large = true
                } else if value.magnification < 1 - Self.pinchThreshold {
                    large = false
                } else {
                    return
                }
                withAnimation(.spring(duration: 0.3)) { nowPlaying.isMiniPlayerLarge = large }
            }
    }
}
