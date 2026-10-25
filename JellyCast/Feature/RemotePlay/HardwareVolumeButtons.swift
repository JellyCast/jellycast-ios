import AVFoundation
import MediaPlayer
import SwiftUI

/// While on screen, the iPhone's volume buttons press the TV's. iOS has no API for the buttons,
/// so each press is read from the phone's output volume and undone through a volume view, which
/// also keeps the system volume indicator away.
struct HardwareVolumeButtons: UIViewRepresentable {
    let onPress: (AndroidTVControl.Key) -> Void

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        // Fully hidden, the system shows its own indicator again.
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        context.coordinator.start(with: view)
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        context.coordinator.onPress = onPress
    }

    static func dismantleUIView(_ view: MPVolumeView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPress: onPress)
    }

    final class Coordinator {
        var onPress: (AndroidTVControl.Key) -> Void
        private weak var volumeView: MPVolumeView?
        private var observation: NSKeyValueObservation?
        private var baseline: Float = 0.5
        private var original: Float?
        private var activatedSession = false

        /// Away from the ends, so both buttons change the volume and can be read.
        private static let baselineRange: ClosedRange<Float> = 0.1...0.9
        private static let tolerance: Float = 0.001
        /// The volume view's slider ignores a value set in the same run loop turn as its creation.
        private static let resetDelay = 0.01

        init(onPress: @escaping (AndroidTVControl.Key) -> Void) {
            self.onPress = onPress
        }

        func start(with view: MPVolumeView) {
            volumeView = view
            Task {
                activatedSession = await Self.activateSession()
                let session = AVAudioSession.sharedInstance()
                let current = session.outputVolume
                original = current
                baseline = min(max(current, Self.baselineRange.lowerBound), Self.baselineRange.upperBound)
                if abs(baseline - current) > Self.tolerance { setVolume(baseline) }
                observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
                    guard let value = change.newValue else { return }
                    Task { @MainActor in self?.volumeChanged(to: value) }
                }
            }
        }

        func stop() {
            observation?.invalidate()
            observation = nil
            if let original { setVolume(original) }
            if activatedSession {
                Task.detached {
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
            }
        }

        private func volumeChanged(to value: Float) {
            guard abs(value - baseline) > Self.tolerance else { return }
            onPress(value > baseline ? .volumeUp : .volumeDown)
            setVolume(baseline)
        }

        private func setVolume(_ value: Float) {
            let slider = volumeView?.subviews.compactMap { $0 as? UISlider }.first
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.resetDelay) {
                slider?.value = value
            }
        }

        /// The output volume is only reported while the session is active; mixing keeps other
        /// apps' audio playing. The player sets its own category again when it loads.
        @concurrent
        private static func activateSession() async -> Bool {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.ambient, options: .mixWithOthers)
                try session.setActive(true)
                return true
            } catch {
                return false
            }
        }
    }
}
