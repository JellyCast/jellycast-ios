import Foundation

/// The streaming quality per kind of network, kept on this device.
@Observable
final class QualitySettings {
    static let shared = QualitySettings()

    var local: QualityPreference {
        didSet { defaults.set(local.storageValue, forKey: Self.localKey) }
    }

    var wifi: QualityPreference {
        didSet { defaults.set(wifi.storageValue, forKey: Self.wifiKey) }
    }

    var cellular: QualityPreference {
        didSet { defaults.set(cellular.storageValue, forKey: Self.cellularKey) }
    }

    private let defaults: UserDefaults

    private static let localKey = "quality.local"
    private static let wifiKey = "quality.wifi"
    private static let cellularKey = "quality.cellular"
    private static let localDefault = QualityPreference.fixed(.original)
    private static let wifiDefault = QualityPreference.auto(upTo: .original)
    private static let cellularDefault = QualityPreference.auto(upTo: .p1080)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        local = defaults.string(forKey: Self.localKey).flatMap(QualityPreference.init(storageValue:))
            ?? Self.localDefault
        wifi = defaults.string(forKey: Self.wifiKey).flatMap(QualityPreference.init(storageValue:))
            ?? Self.wifiDefault
        cellular = defaults.string(forKey: Self.cellularKey).flatMap(QualityPreference.init(storageValue:))
            ?? Self.cellularDefault
    }

    func preference(for network: NetworkKind) -> QualityPreference {
        switch network {
        case .local: local
        case .wifi: wifi
        case .cellular: cellular
        }
    }
}
