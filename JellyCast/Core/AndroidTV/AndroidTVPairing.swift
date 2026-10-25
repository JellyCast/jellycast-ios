import CryptoKit
import Foundation

/// One-time pairing with an Android TV (port 6467): the TV shows a six-character code, and the
/// iPhone proves it saw it with a hash over both certificates. After that the TV trusts this
/// iPhone's certificate on the remote port.
nonisolated final class AndroidTVPairing: @unchecked Sendable {
    enum Failure: Error { case refused, wrongCode, noCertificate }

    private let channel: TLSChannel
    private let clientCertificate: SecCertificate

    static let port: UInt16 = 6467
    private static let protocolVersion: UInt64 = 2
    private static let statusOK: UInt64 = 200
    private static let hexadecimal: UInt64 = 3
    private static let codeLength: UInt64 = 6
    private static let inputRole: UInt64 = 1

    private enum Field {
        static let protocolVersion = 1, status = 2
        static let pairingRequest = 10, pairingRequestAck = 11
        static let options = 20, configuration = 30, configurationAck = 31
        static let secret = 40, secretAck = 41
    }

    init(host: String) throws {
        let client = try ClientIdentity.load()
        clientCertificate = client.certificate
        channel = TLSChannel(host: host, port: Self.port, identity: client.identity)
    }

    /// Ends with the code on the TV screen.
    func start(clientName: String) async throws {
        try await channel.open()
        try await send { $0.message(Field.pairingRequest) { request in
            request.string(1, "atvremote")
            request.string(2, clientName)
        } }
        try await expect(Field.pairingRequestAck)
        try await send { $0.message(Field.options) { options in
            options.message(1) { encoding in
                encoding.varint(1, Self.hexadecimal)
                encoding.varint(2, Self.codeLength)
            }
            options.varint(3, Self.inputRole)
        } }
        try await expect(Field.options)
        try await send { $0.message(Field.configuration) { configuration in
            configuration.message(1) { encoding in
                encoding.varint(1, Self.hexadecimal)
                encoding.varint(2, Self.codeLength)
            }
            configuration.varint(2, Self.inputRole)
        } }
        try await expect(Field.configurationAck)
    }

    func finish(code: String) async throws {
        defer { channel.close() }
        guard let secret = secret(for: code) else { throw Failure.wrongCode }
        try await send { $0.message(Field.secret) { $0.bytes(1, secret) } }
        try await expect(Field.secretAck)
    }

    func cancel() {
        channel.close()
    }

    /// SHA-256 over client modulus and exponent, server modulus and exponent, and the code after
    /// its first byte; that first byte is a check digit and must equal the hash's first byte.
    private func secret(for code: String) -> [UInt8]? {
        let bytes = Self.hexBytes(code.uppercased())
        guard bytes.count == 3,
              let client = ClientIdentity.rsaComponents(of: clientCertificate),
              let serverCertificate = channel.serverCertificate,
              let server = ClientIdentity.rsaComponents(of: serverCertificate)
        else { return nil }
        var hash = SHA256()
        for part in [client.modulus, client.exponent, server.modulus, server.exponent, Array(bytes[1...])] {
            hash.update(data: Data(part))
        }
        let digest = Array(hash.finalize())
        return digest.first == bytes[0] ? digest : nil
    }

    private func send(_ build: (inout ProtoWriter) -> Void) async throws {
        var message = ProtoWriter()
        message.varint(Field.protocolVersion, Self.protocolVersion)
        message.varint(Field.status, Self.statusOK)
        build(&message)
        try await channel.send(message)
    }

    private func expect(_ field: Int) async throws {
        let message = try await channel.receive()
        guard message.varint(Field.status) == Self.statusOK else {
            throw message.varint(Field.status) == 402 ? Failure.wrongCode : Failure.refused
        }
        guard message.has(field) else { throw Failure.refused }
    }

    private static func hexBytes(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
            guard let byte = UInt8(text[index..<next], radix: 16) else { return [] }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
