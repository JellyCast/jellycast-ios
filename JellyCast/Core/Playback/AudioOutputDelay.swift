import AVFoundation
import Foundation

/// A Bluetooth or car audio output, by the identity iOS gives it.
struct AudioDevice: Identifiable, Equatable, Codable {
    let id: String
    let name: String
}

/// The lip-sync correction per wireless audio device, set once in the player and applied whenever
/// that device plays. Car stereos often report less latency than they add, so the picture runs
/// ahead of the sound even though iOS corrects for what the device reports.
@Observable
final class AudioOutputDelay {
    static let shared = AudioOutputDelay()
    static let maxMilliseconds = 500
    static let stepMilliseconds = 10

    /// The wireless device playing right now, `nil` on the speaker, wired outputs and AirPlay
    /// (AirPlay keeps its own sync).
    private(set) var currentDevice: AudioDevice?
    /// Every device with a correction, by id.
    private(set) var saved: [String: Saved]

    struct Saved: Codable, Equatable {
        var name: String
        var milliseconds: Int
    }

    private let defaults: UserDefaults
    private static let storageKey = "audioOutputDelay.devices"
    private static let wirelessPorts: Set<AVAudioSession.Port> = [
        .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .carAudio,
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        saved = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: Saved].self, from: $0) } ?? [:]
        refreshRoute()
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
                self?.refreshRoute()
            }
        }
    }

    /// The correction for the device playing now, in milliseconds the audio is late.
    var currentMilliseconds: Int {
        currentDevice.flatMap { saved[$0.id]?.milliseconds } ?? 0
    }

    /// What the engine takes: positive delays audio, so a late device moves it earlier.
    var engineAudioDelaySeconds: Double {
        -Double(currentMilliseconds) / 1000
    }

    func set(_ milliseconds: Int, for device: AudioDevice) {
        let clamped = min(max(milliseconds, 0), Self.maxMilliseconds)
        saved[device.id] = Saved(name: device.name, milliseconds: clamped)
        save()
    }

    func remove(id: String) {
        saved[id] = nil
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func refreshRoute() {
        let output = AVAudioSession.sharedInstance().currentRoute.outputs
            .first { Self.wirelessPorts.contains($0.portType) }
        currentDevice = output.map { AudioDevice(id: $0.uid, name: $0.portName) }
    }
}
