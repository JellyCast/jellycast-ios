import Foundation
import Security

/// A signed-in user on one server. Stored in the Keychain, because it holds the access token.
nonisolated struct Session: Codable, Sendable, Equatable {
    let serverURL: URL
    let serverID: String
    let serverName: String
    let userID: String
    let userName: String
    let accessToken: String
}

nonisolated enum SessionStorage {
    private static let keychainService = "nl.jellycast.ios"
    private static let keychainAccount = "session"
    private static let deviceIDKey = "deviceID"
    private static let lastServerAddressKey = "lastServerAddress"

    /// Jellyfin keys sign-ins by device id, so it stays the same across launches.
    static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDKey) { return existing }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: deviceIDKey)
        return created
    }

    /// The kind of device, as the server and the TVs show it. `UIDevice` is main-actor only, and
    /// the client builds its header off the main actor.
    static let deviceName: String = {
        if ProcessInfo.processInfo.isiOSAppOnMac { return "Mac" }
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? hardwareModel
        return model.hasPrefix("iPad") ? "iPad" : "iPhone"
    }()

    private static var hardwareModel: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    static var lastServerAddress: String? {
        get { UserDefaults.standard.string(forKey: lastServerAddressKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastServerAddressKey) }
    }

    static func load() -> Session? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    static func save(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        delete()
        var item = baseQuery
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
    }
}

extension Session {
    nonisolated var client: JellyfinClient {
        JellyfinClient(
            serverURL: serverURL, deviceID: SessionStorage.deviceID, accessToken: accessToken,
            followsActiveAddress: true
        )
    }

    nonisolated func using(_ address: URL) -> Session {
        Session(
            serverURL: address, serverID: serverID, serverName: serverName,
            userID: userID, userName: userName, accessToken: accessToken
        )
    }
}
