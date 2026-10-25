import Foundation
import OSLog

/// The downloads on this device and the queue: one download runs at a time, the rest wait.
/// Each item has its own folder in Application Support (excluded from backup); the list itself
/// is `index.json` next to them.
@Observable
final class DownloadStore {
    /// How fast the running download goes, for the time left.
    struct Rate: Equatable {
        let itemID: String
        let bytesPerSecond: Double
        let mediaSecondsPerSecond: Double
    }

    static let shared = DownloadStore()

    private(set) var downloads: [Download] = []
    private(set) var rate: Rate?
    private(set) var isStarted = false

    private var session: Session?
    private weak var library: LibraryStore?
    private var runningID: String?
    private var runningTask: Task<Void, Never>?
    private var runStart: (date: Date, bytes: Int64, mediaSeconds: Double)?
    private let original = OriginalDownloader()

    private static let logger = Logger(subsystem: "nl.jellycast.ios", category: "downloads")
    private static let indexName = "index.json"
    private static let serverCheckTimeoutSeconds = 5.0
    private static let serverCheckInterval = Duration.seconds(3)

    private init() {
        downloads = Self.loadIndex()
        original.onUpdate = { [weak self] update in self?.apply(update) }
    }

    // MARK: Files

    nonisolated static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    nonisolated static func folder(itemID: String) -> URL {
        directory.appending(path: itemID, directoryHint: .isDirectory)
    }

    nonisolated static func prepareFolder(itemID: String) throws -> URL {
        var folder = folder(itemID: itemID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        return folder
    }

    /// The finished download of an item, if it has one.
    nonisolated static func localFile(itemID: String) -> URL? {
        let folder = folder(itemID: itemID)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let name = names.first { $0 == CompactDownloader.fileName }
            ?? names.first { $0.hasPrefix(OriginalDownloader.filePrefix) && !$0.hasSuffix(".resume") }
        return name.map { folder.appending(path: $0) }
    }

    // MARK: Start-up

    /// Recreates the background session at launch, so a file finished while the app was gone lands.
    func attach() {
        original.attach()
    }

    /// Picks up the downloads after a launch: adopts folders the list doesn't know yet and goes on
    /// with the queue.
    func start(library: LibraryStore) async {
        self.library = library
        session = library.session
        adoptFolders(index: library.index)
        let runningOriginals = await original.runningItemIDs()
        for position in downloads.indices where downloads[position].status.isActive {
            let isRunningOriginal = downloads[position].kind == .original
                && runningOriginals.contains(downloads[position].id)
            if isRunningOriginal {
                runningID = downloads[position].id
                downloads[position].status = .running
            } else {
                downloads[position].status = .queued
            }
        }
        save()
        pump()
        isStarted = true
        if let index = library.index { await tidy(index: index) }
    }

    /// The spike left files without a list entry; the library knows what they are.
    private func adoptFolders(index: LibraryIndex?) {
        guard let index else { return }
        let itemIDs = (try? FileManager.default.contentsOfDirectory(atPath: Self.directory.path)) ?? []
        for itemID in itemIDs where !downloads.contains(where: { $0.id == itemID }) {
            guard let playable = index.playable(id: itemID) else { continue }
            let folder = Self.folder(itemID: itemID)
            if let file = Self.localFile(itemID: itemID) {
                let kind: DownloadKind = file.lastPathComponent == CompactDownloader.fileName ? .compact : .original
                let size = Self.fileSize(file)
                downloads.append(Download(playable: playable, kind: kind, status: .done, bytes: size, totalBytes: size))
            } else if let bytes = CompactDownloader.partialBytes(in: folder) {
                downloads.append(Download(playable: playable, kind: .compact, status: .paused, bytes: bytes))
            }
        }
    }

    // MARK: Reading

    func download(for itemID: String) -> Download? {
        downloads.first { $0.id == itemID }
    }

    /// The download that runs now.
    var current: Download? {
        runningID.flatMap(download(for:))
    }

    var active: [Download] {
        downloads.filter { $0.status.isActive || $0.status == .paused || isFailed($0) }
    }

    var finished: [Download] {
        downloads.filter { $0.status == .done }
    }

    var usedBytes: Int64 {
        downloads.reduce(0) { $0 + $1.bytes }
    }

    /// What the queue still needs on top of what it has.
    var reservedBytes: Int64 {
        downloads.filter { $0.status != .done }.reduce(0) { $0 + max($1.expectedBytes - $1.bytes, 0) }
    }

    var freeBytes: Int64? {
        let values = try? URL.applicationSupportDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage.map { max($0 - reservedBytes, 0) }
    }

    /// The server is only reachable at home, so downloads start when it answers. The library's
    /// server check decides, not the address: a host name or a VPN reaches it too.
    var canReachServer: Bool {
        guard NetworkMonitor.shared.isOnline, let library else { return false }
        return !library.isServerUnreachable
    }

    /// A downloaded movie or episode, or a series with at least one downloaded episode.
    func isOnDevice(_ itemID: String) -> Bool {
        downloads.contains { download in
            guard download.status == .done else { return false }
            if download.id == itemID { return true }
            if case .episode(let episode) = download.playable { return episode.seriesID == itemID }
            return false
        }
    }

    /// What a download of this item would take, from the server's file info.
    func plan(for playable: Playable) async -> (plan: DownloadPlan, info: MediaInfo?) {
        var info: MediaInfo?
        if let session {
            info = (try? await session.client.mediaInfo(itemID: playable.id, userID: session.userID)) ?? nil
        }
        return (DownloadPlan(runtimeTicks: playable.runtimeTicks, originalBytes: info?.sizeBytes), info)
    }

    /// Asks the server again, for a tap that would otherwise be refused on an old answer.
    func recheckServer() async {
        await library?.checkServer()
    }

    /// Seconds until the running download is done, from its speed so far.
    func secondsLeft(_ download: Download) -> Double? {
        guard let rate, rate.itemID == download.id else { return nil }
        if download.kind == .compact, let total = download.totalMediaSeconds, rate.mediaSecondsPerSecond > 0 {
            return max(total - download.mediaSeconds, 0) / rate.mediaSecondsPerSecond
        }
        if let total = download.totalBytes, rate.bytesPerSecond > 0 {
            return Double(max(total - download.bytes, 0)) / rate.bytesPerSecond
        }
        return nil
    }

    private func isFailed(_ download: Download) -> Bool {
        if case .failed = download.status { return true }
        return false
    }

    // MARK: Changing

    func enqueue(_ playable: Playable, kind: DownloadKind, estimatedBytes: Int64?) {
        guard download(for: playable.id) == nil else { return }
        downloads.append(Download(
            playable: playable, kind: kind,
            totalBytes: kind == .original ? estimatedBytes : nil, estimatedBytes: estimatedBytes
        ))
        save()
        pump()
    }

    func pause(_ itemID: String) {
        update(itemID) { $0.status = .paused }
        if runningID == itemID { stopRunning(itemID) }
        save()
        pump()
    }

    func resume(_ itemID: String) {
        update(itemID) { $0.status = .queued }
        save()
        pump()
    }

    func pauseAll() {
        for download in downloads where download.status.isActive { pause(download.id) }
    }

    func remove(_ itemID: String) {
        let wasRunning = runningID == itemID
        if wasRunning { stopRunning(itemID) }
        if download(for: itemID)?.kind == .original { Task { await original.cancel(itemID: itemID) } }
        downloads.removeAll { $0.id == itemID }
        try? FileManager.default.removeItem(at: Self.folder(itemID: itemID))
        save()
        if wasRunning { pump() }
    }

    private func stopRunning(_ itemID: String) {
        runningTask?.cancel()
        runningTask = nil
        if download(for: itemID)?.kind == .original { Task { await original.pause(itemID: itemID) } }
        runningID = nil
        rate = nil
    }

    // MARK: Running

    private func pump() {
        guard runningID == nil, let session,
              let next = downloads.filter({ $0.status == .queued }).min(by: { $0.addedAt < $1.addedAt })
        else { return }
        runningID = next.id
        update(next.id) { $0.status = .running }
        runStart = nil
        rate = nil
        save()
        switch next.kind {
        case .compact: runCompact(next, session: session)
        case .original:
            do {
                _ = try Self.prepareFolder(itemID: next.id)
                original.start(itemID: next.id, session: session)
            } catch {
                finish(next.id, status: .failed(error.localizedDescription))
            }
        }
    }

    private func runCompact(_ download: Download, session: Session) {
        let itemID = download.id
        let backgroundTask = ContinuedTask(title: Self.title(of: download.playable))
        backgroundTask.onExpire = { [weak self] in self?.runningTask?.cancel() }
        backgroundTask.submit()
        runningTask = Task {
            while !Task.isCancelled {
                do {
                    let folder = try Self.prepareFolder(itemID: itemID)
                    try await CompactDownloader.run(itemID: itemID, folder: folder, session: session) { progress in
                        self.compactProgressed(itemID, progress)
                        backgroundTask.setFraction(progress.mediaSeconds / max(progress.totalMediaSeconds, 1))
                    }
                    let size = Self.fileSize(folder.appending(path: CompactDownloader.fileName))
                    update(itemID) {
                        $0.bytes = size
                        $0.totalBytes = size
                    }
                    backgroundTask.finish(success: true)
                    finish(itemID, status: .done)
                    return
                } catch is CancellationError {
                    break
                } catch where Self.isNetworkInterruption(error) {
                    Self.logger.info("Waiting for the network: \(error.localizedDescription, privacy: .public)")
                    update(itemID) { $0.status = .waitingForNetwork }
                    backgroundTask.setSubtitle(String(localized: "Waiting for the network"))
                    guard await Self.waitForServer(session.client) else { break }
                    update(itemID) { $0.status = .running }
                    backgroundTask.setSubtitle(String(localized: "Downloading"))
                } catch {
                    Self.logger.error("Compact failed: \(error.localizedDescription, privacy: .public)")
                    backgroundTask.finish(success: false)
                    finish(itemID, status: .failed(error.localizedDescription))
                    return
                }
            }
            // Cancelled: paused by the user, removed, or iOS took the background time away.
            backgroundTask.finish(success: false)
            if runningID == itemID {
                finish(itemID, status: .paused)
            }
        }
    }

    private func compactProgressed(_ itemID: String, _ progress: CompactDownloader.Progress) {
        update(itemID) {
            $0.bytes = progress.bytes
            $0.mediaSeconds = progress.mediaSeconds
            $0.totalMediaSeconds = progress.totalMediaSeconds
            if let totalMediaSeconds = $0.totalMediaSeconds, totalMediaSeconds > 0, progress.mediaSeconds > 0 {
                $0.estimatedBytes = Int64(Double(progress.bytes) / progress.mediaSeconds * totalMediaSeconds)
            }
        }
        updateRate(itemID)
    }

    private func apply(_ update: OriginalDownloader.Update) {
        switch update {
        case .progress(let itemID, let bytes, let totalBytes):
            self.update(itemID) {
                $0.bytes = bytes
                if let totalBytes { $0.totalBytes = totalBytes }
            }
            updateRate(itemID)
        case .finished(let itemID, let bytes):
            self.update(itemID) {
                $0.bytes = bytes
                $0.totalBytes = bytes
            }
            finish(itemID, status: .done)
        case .failed(let itemID, let message):
            finish(itemID, status: .failed(message))
        }
    }

    /// Measured from the first progress of this run, which for a resumed download already
    /// includes what earlier runs fetched.
    private func updateRate(_ itemID: String) {
        guard let download = download(for: itemID) else { return }
        guard let runStart else {
            runStart = (Date.now, download.bytes, download.mediaSeconds)
            return
        }
        let seconds = Date.now.timeIntervalSince(runStart.date)
        guard seconds > 1 else { return }
        rate = Rate(
            itemID: itemID,
            bytesPerSecond: Double(download.bytes - runStart.bytes) / seconds,
            mediaSecondsPerSecond: (download.mediaSeconds - runStart.mediaSeconds) / seconds
        )
    }

    private func finish(_ itemID: String, status: DownloadStatus) {
        update(itemID) { $0.status = status }
        if runningID == itemID {
            runningID = nil
            runningTask = nil
            rate = nil
        }
        save()
        pump()
    }

    private func update(_ itemID: String, _ change: (inout Download) -> Void) {
        guard let position = downloads.firstIndex(where: { $0.id == itemID }) else { return }
        change(&downloads[position])
    }

    /// A dropped or stalled connection, as opposed to the server refusing the request.
    private nonisolated static func isNetworkInterruption(_ error: Error) -> Bool {
        if case JellyfinError.unreachable = error { return true }
        return error is URLError
    }

    /// Checks every few seconds until the server answers again; false when the wait is cancelled.
    private static func waitForServer(_ client: JellyfinClient) async -> Bool {
        while !Task.isCancelled {
            if NetworkMonitor.shared.isOnline,
               (try? await client.publicInfo(timeout: serverCheckTimeoutSeconds)) != nil {
                return true
            }
            try? await Task.sleep(for: serverCheckInterval)
        }
        return false
    }

    static func title(of playable: Playable) -> String {
        switch playable {
        case .movie(let movie): movie.name
        case .episode(let episode): "\(episode.seriesName) · \(Format.seasonEpisode(episode))"
        }
    }

    // MARK: Persistence

    private static func loadIndex() -> [Download] {
        guard let data = try? Data(contentsOf: directory.appending(path: indexName)) else { return [] }
        return (try? JSONDecoder().decode([Download].self, from: data)) ?? []
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(downloads).write(to: Self.directory.appending(path: Self.indexName), options: .atomic)
        } catch {
            Self.logger.error("Saving the download list failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private nonisolated static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
