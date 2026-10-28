import AVKit
import AetherEngine
import OSLog

/// Picture in Picture on every video route: around the engine's AVPlayerLayer on the native
/// routes, around its sample buffer layer on the software route. Starts by itself when the app
/// goes to the background while the video plays.
@Observable
final class PictureInPicture: NSObject, AVPictureInPictureControllerDelegate,
    AVPictureInPictureSampleBufferPlaybackDelegate
{
    private(set) var isPossible = false
    /// Set from the moment the window starts opening, so the background handling sees it in time.
    private(set) var isActive = false
    private var controller: AVPictureInPictureController?
    private weak var engine: AetherEngine?
    private var softwareSource: SoftwarePiPSource?
    private var attachedLayer: CALayer?
    private var possibleObservation: NSKeyValueObservation?

    nonisolated private static let logger = Logger(subsystem: "nl.jellycast.ios", category: "pip")

    func attach(to engine: AetherEngine) {
        self.engine = engine
        let contentSource: AVPictureInPictureController.ContentSource
        let layer: CALayer
        if engine.videoRoute == .software, let source = engine.softwarePiPSource {
            guard source.layer !== attachedLayer else { return }
            softwareSource = source
            layer = source.layer
            contentSource = .init(sampleBufferDisplayLayer: source.layer, playbackDelegate: self)
        } else if let playerLayer = engine.nativePlayerLayer {
            guard playerLayer !== attachedLayer else { return }
            softwareSource = nil
            layer = playerLayer
            contentSource = .init(playerLayer: playerLayer)
        } else {
            return
        }
        Self.logger.info("PiP attached to the \(engine.videoRoute.rawValue, privacy: .public) route")
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        possibleObservation = controller.observe(
            \.isPictureInPicturePossible, options: [.initial, .new]
        ) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            Self.logger.info("PiP possible: \(possible, privacy: .public)")
            Task { @MainActor in self?.isPossible = possible }
        }
        attachedLayer = layer
        self.controller = controller
    }

    /// The software route's window draws its own play button; it asks again after this.
    func playbackChanged() {
        guard softwareSource != nil else { return }
        controller?.invalidatePlaybackState()
    }

    /// Brings the video back from the floating window, as when the app comes to the front again.
    func stopIfActive() {
        guard let controller, controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }

    // MARK: AVPictureInPictureControllerDelegate (AVKit calls these on the main thread)

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        Self.logger.info("PiP starts")
        MainActor.assumeIsolated {
            isActive = true
            engine?.pictureInPictureActive = true
        }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Error
    ) {
        Self.logger.error("PiP failed to start: \(error, privacy: .public)")
        MainActor.assumeIsolated {
            isActive = false
            engine?.pictureInPictureActive = false
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        MainActor.assumeIsolated {
            isActive = false
            engine?.pictureInPictureActive = false
        }
    }

    // MARK: AVPictureInPictureSampleBufferPlaybackDelegate (software route)

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController, setPlaying playing: Bool
    ) {
        MainActor.assumeIsolated { softwareSource?.setPlaying(playing) }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ controller: AVPictureInPictureController
    ) -> CMTimeRange {
        MainActor.assumeIsolated {
            softwareSource?.timeRange() ?? CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
        }
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ controller: AVPictureInPictureController
    ) -> Bool {
        MainActor.assumeIsolated { softwareSource?.isPaused ?? true }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        MainActor.assumeIsolated { softwareSource?.skip(by: skipInterval.seconds) }
        completionHandler()
    }
}
