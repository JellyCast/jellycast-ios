import Foundation

/// An Android TV this iPhone paired with: it can be woken and started even when JellyCast on it
/// is closed and the TV is in standby.
nonisolated struct PairedTV: Codable, Sendable, Identifiable, Equatable {
    /// The Jellyfin device id of its JellyCast app, to recognise its session.
    let deviceID: String
    var host: String
    var name: String

    var id: String { deviceID }
}

@Observable
final class PairedTVs {
    private(set) var all: [PairedTV]

    private static let storageKey = "pairedAndroidTVs"

    init() {
        let data = UserDefaults.standard.data(forKey: Self.storageKey)
        all = data.flatMap { try? JSONDecoder().decode([PairedTV].self, from: $0) } ?? []
    }

    func contains(_ deviceID: String) -> Bool {
        all.contains { $0.deviceID == deviceID }
    }

    func add(_ tv: PairedTV) {
        all.removeAll { $0.deviceID == tv.deviceID }
        all.append(tv)
        save()
    }

    func forget(_ deviceID: String) {
        all.removeAll { $0.deviceID == deviceID }
        save()
    }

    /// A DHCP lease can move the TV; its session tells where it is now.
    func update(deviceID: String, host: String) {
        guard let index = all.firstIndex(where: { $0.deviceID == deviceID }), all[index].host != host else { return }
        all[index].host = host
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
