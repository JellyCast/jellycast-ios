import Foundation
import Observation
import Security

enum ChatProvider: String, CaseIterable, Identifiable, Sendable {
    case claude, openAI

    var id: Self { self }

    var title: String {
        switch self {
        case .claude: "Claude (Anthropic)"
        case .openAI: "ChatGPT (OpenAI)"
        }
    }
}

/// Which AI service the chat uses and its API key. Without a key there is no Chat tab.
@Observable
final class ChatSettings {
    static let shared = ChatSettings()

    var provider: ChatProvider {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey)
            hasKey = ChatKeychain.key(for: provider) != nil
        }
    }

    var avoidsSpoilers: Bool {
        didSet { UserDefaults.standard.set(avoidsSpoilers, forKey: Self.spoilersKey) }
    }

    var searchesWeb: Bool {
        didSet { UserDefaults.standard.set(searchesWeb, forKey: Self.searchKey) }
    }

    private(set) var hasKey: Bool

    private static let providerKey = "chatProvider"
    private static let spoilersKey = "chatAvoidsSpoilers"
    private static let searchKey = "chatSearchesWeb"

    private init() {
        let provider = UserDefaults.standard.string(forKey: Self.providerKey).flatMap(ChatProvider.init) ?? .claude
        self.provider = provider
        avoidsSpoilers = UserDefaults.standard.object(forKey: Self.spoilersKey) as? Bool ?? true
        searchesWeb = UserDefaults.standard.object(forKey: Self.searchKey) as? Bool ?? true
        hasKey = ChatKeychain.key(for: provider) != nil
    }

    var apiKey: String? { ChatKeychain.key(for: provider) }

    /// "sk-ant-•••• 4f2a": enough to recognise the key without showing it.
    var maskedKey: String? {
        guard let key = apiKey else { return nil }
        return "\(key.prefix(7))•••• \(key.suffix(4))"
    }

    func setKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        ChatKeychain.setKey(trimmed?.isEmpty == false ? trimmed : nil, for: provider)
        hasKey = ChatKeychain.key(for: provider) != nil
    }

    func client() -> (any ChatClient)? {
        guard let key = apiKey else { return nil }
        switch provider {
        case .claude: return ClaudeChatClient(apiKey: key)
        case .openAI: return OpenAIChatClient(apiKey: key)
        }
    }
}

/// One Keychain item per provider, on this device only.
nonisolated enum ChatKeychain {
    private static let service = "nl.jellycast.ios.chat"

    static func key(for provider: ChatProvider) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setKey(_ key: String?, for provider: ChatProvider) {
        SecItemDelete(baseQuery(provider) as CFDictionary)
        guard let key, let data = key.data(using: .utf8) else { return }
        var item = baseQuery(provider)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func baseQuery(_ provider: ChatProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }
}
