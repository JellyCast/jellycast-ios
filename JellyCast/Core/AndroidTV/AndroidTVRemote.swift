import Foundation
import Network

/// Wakes a paired Android TV, turns the TV on and opens a link on it (port 6466), the way the
/// Google TV app does.
nonisolated enum AndroidTVRemote {
    static let port: UInt16 = 6466

    enum Field {
        static let configure = 1, setActive = 2, pingRequest = 8, pingResponse = 9
        static let keyInject = 10, start = 40, volumeLevel = 50, appLink = 90
    }

    /// Ping, keys, power and app links; the TV answers with what it supports too.
    static let features: UInt64 = 1 | 2 | 32 | 512
    /// Asks the TV to report its volume as well.
    static let volumeFeature: UInt64 = 64
    /// Power, not WAKEUP: asleep, the TV's remote service ignores WAKEUP. Only sent when the TV
    /// itself reports it is off, so it never switches it off.
    private static let powerKey: UInt64 = 26
    private static let homeKey: UInt64 = 3
    private static let shortPress: UInt64 = 3
    /// Waking, Home and the link together; a sleeping Chromecast is up within a few seconds.
    private static let deadline = Duration.seconds(8)
    private static let linkSettle = Duration.milliseconds(800)
    /// Lets One Touch Play reach the TV before the link replaces the home screen.
    private static let homeSettle = Duration.milliseconds(700)
    /// The TV registers its virtual remote only after the handshake; keys sent earlier are lost.
    static let inputReady = Duration.milliseconds(600)

    enum Failure: Error { case timedOut }

    static func wakeAndOpen(host: String, link: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await run(host: host, link: link) }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw Failure.timedOut
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    /// Power when the TV reports it is on; the Chromecast then puts the TV in standby over HDMI.
    static func turnOff(host: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let client = try ClientIdentity.load()
                let channel = TLSChannel(host: host, port: port, identity: client.identity)
                defer { channel.close() }
                try await channel.open()
                guard try await handshake(channel) else { return }
                try await Task.sleep(for: inputReady)
                try await press(powerKey, on: channel)
                try await Task.sleep(for: linkSettle)
            }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw Failure.timedOut
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private static func run(host: String, link: String) async throws {
        let client = try ClientIdentity.load()
        let channel = TLSChannel(host: host, port: port, identity: client.identity)
        defer { channel.close() }
        try await channel.open()
        let isOn = try await handshake(channel)
        try await Task.sleep(for: inputReady)
        if !isOn {
            try await press(powerKey, on: channel)
            try await waitUntilOn(channel)
        }
        // The Chromecast stays awake when only the TV was turned off, and opening a link sends
        // nothing over HDMI-CEC. Home does: One Touch Play turns the TV on and selects this input.
        try await press(homeKey, on: channel)
        try await Task.sleep(for: homeSettle)
        try await send(channel) { $0.message(Field.appLink) { $0.string(1, link) } }
        try await Task.sleep(for: linkSettle)
    }

    /// Answers the TV's configure and set-active messages until it says whether it is on.
    static func handshake(_ channel: TLSChannel, features: UInt64 = features) async throws -> Bool {
        while true {
            let message = try await channel.receive()
            if let started = try await respond(to: message, on: channel, features: features) { return started }
        }
    }

    private static func waitUntilOn(_ channel: TLSChannel) async throws {
        while true {
            let message = try await channel.receive()
            if try await respond(to: message, on: channel) == true { return }
        }
    }

    /// The on/off state when the message carries it, otherwise `nil` after answering it.
    static func respond(
        to message: ProtoMessage, on channel: TLSChannel, features: UInt64 = features
    ) async throws -> Bool? {
        if message.has(Field.configure) {
            try await send(channel) { $0.message(Field.configure) { configure in
                configure.varint(1, features)
                configure.message(2) { info in
                    info.string(1, "iPhone")
                    info.string(2, "Apple")
                    info.varint(3, 1)
                    info.string(4, "1")
                    info.string(5, "atvremote")
                    info.string(6, "1.0.0")
                }
            } }
        } else if message.has(Field.setActive) {
            try await send(channel) { $0.message(Field.setActive) { $0.varint(1, features) } }
        } else if let ping = message.message(Field.pingRequest) {
            try await send(channel) { $0.message(Field.pingResponse) { $0.varint(1, ping.varint(1) ?? 0) } }
        } else if let start = message.message(Field.start) {
            return start.varint(1) == 1
        }
        return nil
    }

    static func press(_ key: UInt64, on channel: TLSChannel) async throws {
        try await send(channel) { $0.message(Field.keyInject) { inject in
            inject.varint(1, key)
            inject.varint(2, shortPress)
        } }
    }

    private static func send(_ channel: TLSChannel, _ build: (inout ProtoWriter) -> Void) async throws {
        var message = ProtoWriter()
        build(&message)
        try await channel.send(message)
    }
}

nonisolated extension AndroidTVRemote {
    private static let probeTimeout = Duration.milliseconds(1500)

    /// Whether the TV's remote port answers from where the iPhone is now. Waking needs a direct
    /// connection, which away from home only works if the VPN routes the home network.
    static func isReachable(host: String) async -> Bool {
        let connection = NWConnection(
            host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 6466, using: .tcp
        )
        defer { connection.cancel() }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { await ready(connection) }
            group.addTask {
                try? await Task.sleep(for: probeTimeout)
                return false
            }
            let reachable = await group.next() ?? false
            group.cancelAll()
            connection.cancel()
            return reachable
        }
    }

    private static func ready(_ connection: NWConnection) async -> Bool {
        await withCheckedContinuation { continuation in
            let resumed = ProbeOnce()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: if resumed.claim() { continuation.resume(returning: true) }
                case .failed, .waiting, .cancelled: if resumed.claim() { continuation.resume(returning: false) }
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }
}

private nonisolated final class ProbeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.withLock {
            defer { done = true }
            return !done
        }
    }
}
