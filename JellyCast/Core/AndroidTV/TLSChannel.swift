import Foundation
import Network
import Security

/// One TLS connection to an Android TV with this iPhone's certificate, carrying
/// length-prefixed protobuf messages. The TV's own certificate is self-signed, so any is accepted
/// and kept: pairing hashes it.
nonisolated final class TLSChannel: @unchecked Sendable {
    enum Failure: Error { case closed, timedOut, unreadable }

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "nl.jellycast.androidtv")
    private var buffer: [UInt8] = []
    private(set) var serverCertificate: SecCertificate?

    /// On the home network a TV answers within milliseconds; longer means it can't be reached.
    private static let connectTimeout = Duration.seconds(3)

    init(host: String, port: UInt16, identity: SecIdentity) {
        let tls = NWProtocolTLS.Options()
        if let localIdentity = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, localIdentity)
        }
        let box = CertificateBox()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            box.certificate = (SecTrustCopyCertificateChain(secTrust) as? [SecCertificate])?.first
            complete(true)
        }, queue)
        connection = NWConnection(
            host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 6466,
            using: NWParameters(tls: tls)
        )
        certificateBox = box
    }

    private let certificateBox: CertificateBox

    func open() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.waitUntilReady() }
            group.addTask {
                try await Task.sleep(for: Self.connectTimeout)
                throw Failure.timedOut
            }
            defer { group.cancelAll() }
            try await group.next()
        }
        serverCertificate = certificateBox.certificate
    }

    func send(_ message: ProtoWriter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(message.framed), completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    func receive() async throws -> ProtoMessage {
        while true {
            var index = 0
            if let length = ProtoMessage.readVarint(buffer, &index), buffer.count >= index + Int(length) {
                let body = Array(buffer[index..<index + Int(length)])
                buffer.removeFirst(index + Int(length))
                guard let message = ProtoMessage(body) else { throw Failure.unreadable }
                return message
            }
            buffer += try await receiveChunk()
        }
    }

    func close() {
        connection.cancel()
    }

    /// Cancelling ends the connection, so a waiting continuation always resumes.
    private func waitUntilReady() async throws {
        try await withTaskCancellationHandler {
            try await startAndWait()
        } onCancel: {
            connection.cancel()
        }
    }

    private func startAndWait() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = ResumeOnce()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: if resumed.claim() { continuation.resume() }
                case .failed(let error), .waiting(let error):
                    if resumed.claim() { continuation.resume(throwing: error) }
                case .cancelled: if resumed.claim() { continuation.resume(throwing: Failure.closed) }
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func receiveChunk() async throws -> [UInt8] {
        try await withTaskCancellationHandler {
            try await receiveFromConnection()
        } onCancel: {
            connection.cancel()
        }
    }

    private func receiveFromConnection() async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: Array(data))
                } else if isComplete {
                    continuation.resume(throwing: Failure.closed)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}

private nonisolated final class CertificateBox: @unchecked Sendable {
    var certificate: SecCertificate?
}

private nonisolated final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.withLock {
            defer { done = true }
            return !done
        }
    }
}
