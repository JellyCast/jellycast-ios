import Foundation

/// The original file of one item, fetched from the server in chunks into a sparse file on disk.
/// The player reads through it, and the prefetcher fills it ahead of the play position.
actor StreamCache {
    nonisolated let itemID: String
    nonisolated let totalBytes: Int64
    nonisolated let bitsPerSecond: Int

    private let remoteURL: URL
    private let authorization: String
    private let fileURL: URL
    private let handle: FileHandle
    private var present = Set<Int>()
    private var inFlight: [Int: Task<Data, Error>] = [:]
    private var measuredBytesPerSecond: Double?
    private var fetchCount = 0
    private var prefetchTask: Task<Void, Never>?
    private var readChunk = 0

    nonisolated static let chunkBytes: Int64 = 2 * 1024 * 1024
    private static let throughputSmoothing = 0.3

    private init(
        itemID: String, remoteURL: URL, authorization: String, totalBytes: Int64, bitsPerSecond: Int
    ) throws {
        self.itemID = itemID
        self.remoteURL = remoteURL
        self.authorization = authorization
        self.totalBytes = totalBytes
        self.bitsPerSecond = bitsPerSecond
        let directory = URL.cachesDirectory.appending(path: "stream", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "\(itemID).part")
        try? FileManager.default.removeItem(at: fileURL)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try FileHandle(forUpdating: fileURL)
    }

    deinit {
        try? handle.close()
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Asks the server for the file size with a one-byte range request.
    static func open(
        itemID: String, remoteURL: URL, authorization: String, bitsPerSecond: Int
    ) async throws -> StreamCache {
        var request = URLRequest(url: remoteURL)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              let range = http.value(forHTTPHeaderField: "Content-Range"),
              let total = range.split(separator: "/").last.flatMap({ Int64($0) }), total > 0
        else { throw JellyfinError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0) }
        return try StreamCache(
            itemID: itemID, remoteURL: remoteURL, authorization: authorization,
            totalBytes: total, bitsPerSecond: bitsPerSecond
        )
    }

    var bytesPerSecond: Double? { measuredBytesPerSecond }

    nonisolated var chunkCount: Int { Int((totalBytes + Self.chunkBytes - 1) / Self.chunkBytes) }

    nonisolated func chunk(containing offset: Int64) -> Int { Int(offset / Self.chunkBytes) }

    /// The bytes of one chunk, from disk when present, otherwise fetched once and kept.
    func data(chunk: Int) async throws -> Data {
        if present.contains(chunk) {
            try handle.seek(toOffset: UInt64(Int64(chunk) * Self.chunkBytes))
            return try handle.read(upToCount: Int(length(of: chunk))) ?? Data()
        }
        if let running = inFlight[chunk] { return try await running.value }
        // The task stores the chunk itself, so it is present by the time any waiter resumes.
        let task = Task {
            defer { inFlight[chunk] = nil }
            let data = try await fetch(chunk: chunk)
            try handle.seek(toOffset: UInt64(Int64(chunk) * Self.chunkBytes))
            try handle.write(contentsOf: data)
            present.insert(chunk)
            return data
        }
        inFlight[chunk] = task
        return try await task.value
    }

    /// Where the player reads now; the prefetcher stays ahead of it.
    func noteRead(offset: Int64) {
        readChunk = chunk(containing: offset)
    }

    /// Bytes present without a gap from `offset` on.
    func contiguousBytes(from offset: Int64) -> Int64 {
        var chunk = chunk(containing: offset)
        while chunk < chunkCount, present.contains(chunk) { chunk += 1 }
        return max(0, min(totalBytes, Int64(chunk) * Self.chunkBytes) - offset)
    }

    func bytesAheadOfRead() -> Int64 {
        contiguousBytes(from: Int64(readChunk) * Self.chunkBytes)
    }

    /// Keeps fetching the chunks after the read position, up to `aheadBytes` ahead of it.
    func startPrefetch(from offset: Int64, aheadBytes: Int64) {
        readChunk = chunk(containing: offset)
        let aheadChunks = Int(max(1, aheadBytes / Self.chunkBytes))
        prefetchTask?.cancel()
        prefetchTask = Task {
            while !Task.isCancelled {
                let window = readChunk..<min(chunkCount, readChunk + aheadChunks)
                guard let next = window.first(where: { !present.contains($0) }) else {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                do {
                    _ = try await data(chunk: next)
                } catch {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    func stopPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    /// The first and last chunk: wakes the server's disk, measures the connection, and has the
    /// MKV cues at hand.
    func warmUp() async {
        _ = try? await data(chunk: 0)
        _ = try? await data(chunk: chunkCount - 1)
        if chunkCount > 2 { _ = try? await data(chunk: 1) }
    }

    private func length(of chunk: Int) -> Int64 {
        min(Self.chunkBytes, totalBytes - Int64(chunk) * Self.chunkBytes)
    }

    private func fetch(chunk: Int) async throws -> Data {
        let start = Int64(chunk) * Self.chunkBytes
        let end = start + length(of: chunk) - 1
        var request = URLRequest(url: remoteURL)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        let began = ContinuousClock.now
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 206, Int64(data.count) == end - start + 1 else {
            throw JellyfinError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let seconds = (ContinuousClock.now - began) / .seconds(1)
        fetchCount += 1
        // The first fetch includes the server's disk spinning up (~7 s), not the connection.
        if seconds > 0, fetchCount > 1 {
            let sample = Double(data.count) / seconds
            let smoothed = measuredBytesPerSecond.map {
                $0 * (1 - Self.throughputSmoothing) + sample * Self.throughputSmoothing
            } ?? sample
            measuredBytesPerSecond = smoothed
            ConnectionMeter.shared.record(bytesPerSecond: smoothed)
        }
        return data
    }
}
