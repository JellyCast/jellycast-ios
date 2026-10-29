import Foundation
import Synchronization

/// The address the signed-in server is used on right now.
nonisolated enum ActiveServerAddress {
    private static let current = Mutex<URL?>(nil)

    static var url: URL? { current.withLock { $0 } }

    static func set(_ url: URL?) {
        current.withLock { $0 = url }
    }
}

/// The addresses a server answers on, in the order the user prefers them. Kept per server id
/// outside the Keychain: they hold no secret and outlive a sign-out.
nonisolated enum ServerAddressBook {
    private static let key = "serverAddresses"

    static func addresses(serverID: String, signedInAt address: URL) -> [URL] {
        let saved = (book[serverID] ?? []).compactMap(URL.init(string:))
        return saved.contains(address) ? saved : saved + [address]
    }

    static func save(_ addresses: [URL], serverID: String) {
        var updated = book
        updated[serverID] = addresses.map(\.absoluteString)
        UserDefaults.standard.set(updated, forKey: key)
    }

    private static var book: [String: [String]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
    }
}

/// Picks the address to use: the first one in the user's order that answers as this server.
nonisolated enum ServerAddressPicker {
    enum Outcome: Equatable, Sendable {
        case reached(URL)
        case failed(ServerProblem)
    }

    /// A server on the LAN answers in milliseconds, so once a less preferred address has answered
    /// the ones above it get only this long to answer too.
    private static let preferredGraceSeconds = 1.5

    private enum Answer: Sendable {
        case address(index: Int, reached: Bool, offline: Bool)
        case graceOver
    }

    static func pick(_ addresses: [URL], serverID: String, timeoutSeconds: Double) async -> Outcome {
        var reached = [Bool?](repeating: nil, count: addresses.count)
        var isOffline = false
        var isGraceOver = false
        var hasGraceStarted = false
        return await withTaskGroup(of: Answer.self) { group in
            for (index, address) in addresses.enumerated() {
                group.addTask {
                    let probe = await probe(address, serverID: serverID, timeoutSeconds: timeoutSeconds)
                    return .address(index: index, reached: probe.reached, offline: probe.offline)
                }
            }
            for await answer in group {
                switch answer {
                case .address(let index, let answered, let offline):
                    reached[index] = answered
                    isOffline = isOffline || offline
                case .graceOver:
                    isGraceOver = true
                }
                if let first = firstUsable(reached, isGraceOver: isGraceOver) {
                    group.cancelAll()
                    return .reached(addresses[first])
                }
                if !reached.contains(where: { $0 != false }) {
                    group.cancelAll()
                    break
                }
                if !hasGraceStarted, reached.contains(true) {
                    hasGraceStarted = true
                    group.addTask {
                        try? await Task.sleep(for: .seconds(preferredGraceSeconds))
                        return .graceOver
                    }
                }
            }
            return .failed(isOffline ? .offline : .unreachable)
        }
    }

    /// The most preferred address that answered, once every address above it has failed or had
    /// its grace.
    private static func firstUsable(_ reached: [Bool?], isGraceOver: Bool) -> Int? {
        for (index, answer) in reached.enumerated() {
            switch answer {
            case true?: return index
            case false?: continue
            case nil: if !isGraceOver { return nil }
            }
        }
        return nil
    }

    static func probe(
        _ address: URL, serverID: String, timeoutSeconds: Double
    ) async -> (reached: Bool, offline: Bool) {
        let client = JellyfinClient(serverURL: address, deviceID: SessionStorage.deviceID)
        do {
            let info = try await client.publicInfo(timeout: timeoutSeconds)
            return (info.id == serverID, false)
        } catch JellyfinError.unreachable(let reason) {
            return (false, reason.code == .notConnectedToInternet)
        } catch {
            return (false, false)
        }
    }
}
