import Foundation

/// A remote connection to a paired Android TV that stays open while a screen needs it, for the
/// volume keys, with the volume as the TV reports it.
actor AndroidTVControl {
    struct Volume: Sendable, Equatable {
        let level: Int
        let max: Int
        let isMuted: Bool
    }

    enum Key: UInt64, Sendable {
        case volumeUp = 24, volumeDown = 25, mute = 164
    }

    enum Failure: Error { case notConnected }

    private let host: String
    private var channel: TLSChannel?

    private enum VolumeField {
        static let max = 6, level = 7, muted = 8
    }

    init(host: String) {
        self.host = host
    }

    /// Connects and answers the TV until the connection ends or the task is cancelled.
    func run(onReady: @Sendable () async -> Void, onVolume: @Sendable (Volume) async -> Void) async throws {
        let client = try ClientIdentity.load()
        let channel = TLSChannel(host: host, port: AndroidTVRemote.port, identity: client.identity)
        defer {
            channel.close()
            self.channel = nil
        }
        try await withTaskCancellationHandler {
            try await channel.open()
            let features = AndroidTVRemote.features | AndroidTVRemote.volumeFeature
            _ = try await AndroidTVRemote.handshake(channel, features: features)
            try await Task.sleep(for: AndroidTVRemote.inputReady)
            self.channel = channel
            await onReady()
            while true {
                let message = try await channel.receive()
                if let volume = message.message(AndroidTVRemote.Field.volumeLevel) {
                    await onVolume(Volume(
                        level: Int(volume.varint(VolumeField.level) ?? 0),
                        max: Int(volume.varint(VolumeField.max) ?? 0),
                        isMuted: volume.varint(VolumeField.muted) == 1
                    ))
                } else {
                    _ = try await AndroidTVRemote.respond(to: message, on: channel, features: features)
                }
            }
        } onCancel: {
            channel.close()
        }
    }

    func press(_ key: Key) async throws {
        guard let channel else { throw Failure.notConnected }
        try await AndroidTVRemote.press(key.rawValue, on: channel)
    }
}
