import Foundation
import Network

/// Serves cached items to the player over loopback HTTP with byte ranges, so the engine reads the
/// original file through `StreamCache` instead of straight from the server.
nonisolated final class LocalStreamServer: @unchecked Sendable {
    static let shared = LocalStreamServer()

    private let queue = DispatchQueue(label: "nl.jellycast.stream-server")
    private let lock = NSLock()
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var caches: [String: StreamCache] = [:]

    private static let headerLimitBytes = 16 * 1024

    func url(for cache: StreamCache) async throws -> URL {
        lock.withLock { caches[cache.itemID] = cache }
        let port = try await startIfNeeded()
        guard let url = URL(string: "http://127.0.0.1:\(port.rawValue)/\(cache.itemID)") else {
            throw URLError(.badURL)
        }
        return url
    }

    func remove(itemID: String) {
        lock.withLock { caches[itemID] = nil }
    }

    private func startIfNeeded() async throws -> NWEndpoint.Port {
        if let port = lock.withLock({ self.port }) { return port }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            Task { await self.serve(connection) }
        }
        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            let resumed = Mutex(false)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port, resumed.claim() else { return }
                    continuation.resume(returning: port)
                case .failed(let error):
                    guard resumed.claim() else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        lock.withLock {
            self.listener = listener
            self.port = port
        }
        return port
    }

    private func serve(_ connection: NWConnection) async {
        defer { connection.cancel() }
        guard let request = try? await Self.readRequest(connection),
              let cache = lock.withLock({ caches[request.itemID] })
        else {
            let notFound = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            try? await Self.send(Data(notFound.utf8), on: connection)
            return
        }
        let total = cache.totalBytes
        let start = min(request.rangeStart ?? 0, max(0, total - 1))
        let end = min(request.rangeEnd ?? (total - 1), total - 1)
        guard start <= end else {
            let unsatisfiable = "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(total)\r\n"
                + "Connection: close\r\n\r\n"
            try? await Self.send(Data(unsatisfiable.utf8), on: connection)
            return
        }
        let status = request.rangeStart == nil ? "200 OK" : "206 Partial Content"
        var header = "HTTP/1.1 \(status)\r\nContent-Type: application/octet-stream\r\nAccept-Ranges: bytes\r\n"
        header += "Content-Length: \(end - start + 1)\r\n"
        if request.rangeStart != nil { header += "Content-Range: bytes \(start)-\(end)/\(total)\r\n" }
        header += "Connection: close\r\n\r\n"
        guard (try? await Self.send(Data(header.utf8), on: connection)) != nil, !request.isHead else { return }

        var offset = start
        while offset <= end {
            await cache.noteRead(offset: offset)
            let chunk = cache.chunk(containing: offset)
            guard let data = try? await cache.data(chunk: chunk) else { return }
            let chunkStart = Int64(chunk) * StreamCache.chunkBytes
            let from = Int(offset - chunkStart)
            let to = Int(min(end + 1, chunkStart + Int64(data.count)) - chunkStart)
            guard from < to else { return }
            guard (try? await Self.send(data.subdata(in: from..<to), on: connection)) != nil else { return }
            offset = chunkStart + Int64(to)
        }
    }

    private struct Request {
        let itemID: String
        let rangeStart: Int64?
        let rangeEnd: Int64?
        let isHead: Bool
    }

    private static func readRequest(_ connection: NWConnection) async throws -> Request? {
        var buffer = Data()
        let terminator = Data("\r\n\r\n".utf8)
        while buffer.range(of: terminator) == nil {
            guard buffer.count < headerLimitBytes else { return nil }
            guard let received = try await receive(on: connection) else { return nil }
            buffer.append(received)
        }
        guard let text = String(data: buffer, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }
        let itemID = String(requestLine[1].drop(while: { $0 == "/" }))
        var rangeStart: Int64?
        var rangeEnd: Int64?
        for line in lines.dropFirst() where line.lowercased().hasPrefix("range:") {
            let spec = line.dropFirst("range:".count).trimmingCharacters(in: .whitespaces)
            guard spec.hasPrefix("bytes=") else { continue }
            let bounds = spec.dropFirst("bytes=".count).split(separator: "-", omittingEmptySubsequences: false)
            rangeStart = bounds.first.flatMap { Int64($0) }
            rangeEnd = bounds.count > 1 ? Int64(bounds[1]) : nil
        }
        return Request(
            itemID: itemID, rangeStart: rangeStart, rangeEnd: rangeEnd, isHead: requestLine[0] == "HEAD"
        )
    }

    private static func receive(on connection: NWConnection) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                if let error { continuation.resume(throwing: error) } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(returning: isComplete ? nil : Data())
                }
            }
        }
    }

    private static func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
}

/// A flag that can be claimed once from any thread.
private nonisolated final class Mutex: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed: Bool

    init(_ claimed: Bool) { self.claimed = claimed }

    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}
