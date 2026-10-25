import BackgroundTasks
import Foundation
import OSLog

/// Fetches the server's HLS transcode of one item segment by segment and appends it into one
/// file: the fMP4 init segment followed by every media segment is a valid fragmented MP4.
/// Progress is saved after each segment, so a new transcode can go on at the next one.
enum CompactDownloader {
    struct Progress {
        let bytes: Int64
        let mediaSeconds: Double
        let totalMediaSeconds: Double
    }

    nonisolated static let fileName = "compact.mp4"
    private static let partName = "compact.part"
    private static let maxWidth = 1920
    private static let maxBitsPerSecond = 5_000_000
    /// A segment normally arrives in well under a second; this long without bytes means the
    /// connection is gone, even when iOS hasn't noticed yet.
    private static let segmentTimeoutSeconds = 20.0
    /// The first segment of a new transcode also waits for the server's disk to spin up.
    private static let firstSegmentTimeoutSeconds = 60.0
    private static let logger = Logger(subsystem: "nl.jellycast.ios", category: "downloads")

    static func run(
        itemID: String, folder: URL, session: Session, onProgress: (Progress) -> Void
    ) async throws {
        let client = session.client
        guard let info = try await client.mediaInfo(itemID: itemID, userID: session.userID) else {
            throw JellyfinError.badStatus(0)
        }
        let partURL = folder.appending(path: partName)
        var progress = CompactProgress.load(in: folder) ?? CompactProgress()
        let file = try AppendFile(url: partURL, truncatingTo: progress.bytes)

        let transcode = try await client.transcodeStream(
            itemID: itemID, mediaSourceID: info.mediaSourceID, userID: session.userID,
            maxWidth: maxWidth, maxBitsPerSecond: maxBitsPerSecond,
            audioStreamIndex: nil, subtitleStreamIndex: nil
        )
        defer {
            Task.detached { try? await client.stopTranscode(playSessionID: transcode.playSessionID) }
        }
        let playlist = try await HLSPlaylist.load(master: transcode.url, authorization: client.authorizationHeader)
        let totalSeconds = playlist.segments.reduce(0) { $0 + $1.seconds }
        var mediaSeconds = playlist.segments.prefix(progress.nextSegment).reduce(0) { $0 + $1.seconds }
        onProgress(Progress(bytes: progress.bytes, mediaSeconds: mediaSeconds, totalMediaSeconds: totalSeconds))

        if progress.nextSegment == 0 {
            try await file.append(try await fetch(playlist.initSegment, client: client, timeout: firstSegmentTimeoutSeconds))
        }
        var isFirstSegment = true
        while progress.nextSegment < playlist.segments.count {
            try Task.checkCancellation()
            let segment = playlist.segments[progress.nextSegment]
            #if DEBUG
            try simulateDropIfAsked(at: progress.nextSegment)
            #endif
            let timeout = isFirstSegment ? firstSegmentTimeoutSeconds : segmentTimeoutSeconds
            try await file.append(try await fetch(segment.url, client: client, timeout: timeout))
            isFirstSegment = false
            progress.nextSegment += 1
            progress.bytes = await file.size
            try progress.save(in: folder)
            mediaSeconds += segment.seconds
            onProgress(Progress(bytes: progress.bytes, mediaSeconds: mediaSeconds, totalMediaSeconds: totalSeconds))
        }
        try await file.close()
        try FileManager.default.moveItem(at: partURL, to: folder.appending(path: fileName))
        CompactProgress.remove(in: folder)
        logger.info("Compact done: \(progress.bytes) bytes")
    }

    /// The bytes an interrupted download already has, for the list after a relaunch.
    static func partialBytes(in folder: URL) -> Int64? {
        CompactProgress.load(in: folder)?.bytes
    }

    private static func fetch(_ url: URL, client: JellyfinClient, timeout: Double) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(client.authorizationHeader, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw JellyfinError.badStatus(status) }
        return data
    }

    #if DEBUG
    private static var simulatedDropDone = false

    /// `-downloadDropAt <segment>` fails that segment once, as a dropped connection would.
    private static func simulateDropIfAsked(at segment: Int) throws {
        let dropAt = UserDefaults.standard.integer(forKey: "downloadDropAt")
        guard dropAt > 0, segment == dropAt, !simulatedDropDone else { return }
        simulatedDropDone = true
        throw URLError(.networkConnectionLost)
    }
    #endif
}

/// Where an interrupted Compact download goes on: the next segment and the bytes written before it.
private nonisolated struct CompactProgress: Codable {
    var nextSegment = 0
    var bytes: Int64 = 0

    private static let name = "compact.progress.json"

    static func load(in folder: URL) -> CompactProgress? {
        guard let data = try? Data(contentsOf: folder.appending(path: name)) else { return nil }
        return try? JSONDecoder().decode(CompactProgress.self, from: data)
    }

    func save(in folder: URL) throws {
        try JSONEncoder().encode(self).write(to: folder.appending(path: Self.name), options: .atomic)
    }

    static func remove(in folder: URL) {
        try? FileManager.default.removeItem(at: folder.appending(path: name))
    }
}

private actor AppendFile {
    private let handle: FileHandle

    init(url: URL, truncatingTo bytes: Int64) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(bytes))
        try handle.seekToEnd()
    }

    var size: Int64 { Int64((try? handle.offset()) ?? 0) }

    func append(_ data: Data) throws {
        try handle.write(contentsOf: data)
    }

    func close() throws {
        try handle.close()
    }
}

/// The variant playlist of a Jellyfin HLS transcode: the fMP4 init segment and the media segments.
nonisolated struct HLSPlaylist: Sendable {
    struct Segment: Sendable {
        let url: URL
        let seconds: Double
    }

    let initSegment: URL
    let segments: [Segment]

    static func load(master: URL, authorization: String) async throws -> HLSPlaylist {
        let masterText = try await text(at: master, authorization: authorization)
        guard let variantPath = uris(in: masterText).first,
              let variantURL = URL(string: variantPath, relativeTo: master)?.absoluteURL
        else { throw JellyfinError.badStatus(0) }
        return try parse(try await text(at: variantURL, authorization: authorization), base: variantURL)
    }

    static func parse(_ text: String, base: URL) throws -> HLSPlaylist {
        var initSegment: URL?
        var segments: [Segment] = []
        var pendingSeconds: Double?
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("#EXT-X-MAP:"), let uri = line.components(separatedBy: "URI=\"").last {
                initSegment = URL(string: String(uri.dropLast()), relativeTo: base)?.absoluteURL
            } else if line.hasPrefix("#EXTINF:") {
                pendingSeconds = Double(line.dropFirst("#EXTINF:".count).prefix { $0 != "," })
            } else if !line.hasPrefix("#"), let seconds = pendingSeconds,
                      let url = URL(string: line, relativeTo: base)?.absoluteURL {
                segments.append(Segment(url: url, seconds: seconds))
                pendingSeconds = nil
            }
        }
        guard let initSegment, !segments.isEmpty else { throw JellyfinError.badStatus(0) }
        return HLSPlaylist(initSegment: initSegment, segments: segments)
    }

    private static func uris(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func text(at url: URL, authorization: String) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Keeps a download the user started running in the background, shown by iOS in the Dynamic Island.
final class ContinuedTask {
    var onExpire: (() -> Void)?

    private let identifier = "nl.jellycast.ios.download.\(UUID().uuidString.prefix(8))"
    private let title: String
    private var task: BGContinuedProcessingTask?
    private var fraction = 0.0
    private var finished = false

    private static let progressUnits: Int64 = 1000
    private static let logger = Logger(subsystem: "nl.jellycast.ios", category: "downloads")

    init(title: String) {
        self.title = title
    }

    func submit() {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated { self.began(task) }
        }
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier, title: title, subtitle: String(localized: "Downloading")
        )
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Self.logger.info("No background time: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setFraction(_ fraction: Double) {
        self.fraction = fraction
        task?.progress.completedUnitCount = Int64(fraction * Double(Self.progressUnits))
    }

    func setSubtitle(_ subtitle: String) {
        task?.updateTitle(title, subtitle: subtitle)
    }

    func finish(success: Bool) {
        finished = true
        task?.setTaskCompleted(success: success)
        task = nil
    }

    private func began(_ task: BGTask) {
        guard let task = task as? BGContinuedProcessingTask else { return }
        guard !finished else {
            task.setTaskCompleted(success: true)
            return
        }
        self.task = task
        task.progress.totalUnitCount = Self.progressUnits
        setFraction(fraction)
        task.expirationHandler = { [weak self] in
            Task { @MainActor in self?.onExpire?() }
        }
    }
}

extension JellyfinClient {
    nonisolated func stopTranscode(playSessionID: String) async throws {
        _ = try await data(
            "Videos/ActiveEncodings", method: "DELETE",
            query: [
                URLQueryItem(name: "deviceId", value: deviceID),
                URLQueryItem(name: "playSessionId", value: playSessionID),
            ]
        )
    }
}
