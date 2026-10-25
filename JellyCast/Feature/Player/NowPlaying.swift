import AetherEngine
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
        session.stop()
        session.engine.stop()
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

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(engine.$state) { state in
                session.stateChanged(state)
                if state == .ended { nowPlaying.itemEnded() }
            }
            .onReceive(engine.$isBuffering) { session.bufferingChanged($0) }
            .onReceive(engine.seekEvents) { event in
                if case .landed = event.outcome { session.seeked() }
            }
            .onReceive(engine.$videoRoute) { _ in nowPlaying.pip.attach(to: engine) }
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
