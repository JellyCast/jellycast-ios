import Foundation

/// Names the user gives devices on this phone ("Living room"), by device id: the TV apps only
/// know names like "chromecast" or "LG webOS TV", the same for both LG TVs.
@Observable
final class DeviceNames {
    private(set) var names: [String: String]

    private static let storageKey = "remoteDeviceNames"

    init() {
        names = UserDefaults.standard.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
    }

    func name(for deviceID: String, fallback: String) -> String {
        names[deviceID] ?? fallback
    }

    /// An empty name goes back to the device's own.
    func rename(_ deviceID: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        names[deviceID] = trimmed.isEmpty ? nil : trimmed
        UserDefaults.standard.set(names, forKey: Self.storageKey)
    }
}
