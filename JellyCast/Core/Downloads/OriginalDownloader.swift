import Foundation
import OSLog

/// Fetches original files with a background `URLSession`, which keeps going while the app is
/// suspended, waits out a lost connection by itself, and relaunches the app to hand over the file.
nonisolated final class OriginalDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    enum Update: Sendable {
        case progress(itemID: String, bytes: Int64, totalBytes: Int64?)
        case finished(itemID: String, bytes: Int64)
        case failed(itemID: String, message: String)
    }

    /// Called on the main actor.
    @MainActor var onUpdate: ((Update) -> Void)?

    static let filePrefix = "original."
    private static let resumeDataName = "original.resume"
    private static let identifier = "nl.jellycast.ios.download.original"
    private static let logger = Logger(subsystem: "nl.jellycast.ios", category: "downloads")
    private static let progressStepBytes: Int64 = 8 * 1024 * 1024

    private let lock = NSLock()
    private var session: URLSession?
    private var lastReported: [Int: Int64] = [:]

    @MainActor func attach() {
        _ = backgroundSession()
    }

    /// The item IDs the background session is still fetching.
    @MainActor func runningItemIDs() async -> Set<String> {
        let tasks = await backgroundSession().allTasks
        return Set(tasks.filter { $0.state == .running || $0.state == .suspended }.compactMap(\.taskDescription))
    }

    @MainActor func start(itemID: String, session: Session) {
        let folder = DownloadStore.folder(itemID: itemID)
        let resumeURL = folder.appending(path: Self.resumeDataName)
        let task: URLSessionDownloadTask
        let downloadURL = Self.downloadURL(itemID: itemID, server: session.client.serverURL)
        let resumeData = (try? Data(contentsOf: resumeURL)).flatMap { Self.retargeted($0, to: downloadURL) }
        try? FileManager.default.removeItem(at: resumeURL)
        if let resumeData {
            task = backgroundSession().downloadTask(withResumeData: resumeData)
        } else {
            var request = URLRequest(url: downloadURL)
            request.setValue(session.client.authorizationHeader, forHTTPHeaderField: "Authorization")
            task = backgroundSession().downloadTask(with: request)
        }
        task.taskDescription = itemID
        task.resume()
    }

    /// Moves running downloads to the address the server is used on now, keeping what they have.
    @MainActor func moveToActiveAddress(session: Session) async {
        let server = session.client.serverURL
        for task in await backgroundSession().allTasks {
            guard let download = task as? URLSessionDownloadTask, let itemID = task.taskDescription,
                  task.state == .running || task.state == .suspended,
                  task.currentRequest?.url?.host() != server.host() || task.currentRequest?.url?.port != server.port
            else { continue }
            if let data = await download.cancelByProducingResumeData(),
               let folder = try? DownloadStore.prepareFolder(itemID: itemID) {
                try? data.write(to: folder.appending(path: Self.resumeDataName))
            }
            start(itemID: itemID, session: session)
        }
    }

    private static func downloadURL(itemID: String, server: URL) -> URL {
        server.appending(path: "Items/\(itemID)/Download")
    }

    /// Resume data holds the address the download began on; a download goes on elsewhere only when
    /// that address in it is replaced. Nil when the data has an unknown shape.
    private static func retargeted(_ resumeData: Data, to url: URL) -> Data? {
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard var plist = try? PropertyListSerialization.propertyList(
            from: resumeData, options: [], format: &format
        ) as? [String: Any] else { return nil }
        plist["NSURLSessionDownloadURL"] = url.absoluteString
        for key in ["NSURLSessionResumeOriginalRequest", "NSURLSessionResumeCurrentRequest"] {
            guard let archived = plist[key] as? Data else { continue }
            guard let request = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURLRequest.self, from: archived),
                  let moved = request.mutableCopy() as? NSMutableURLRequest
            else { return nil }
            moved.url = url
            guard let rearchived = try? NSKeyedArchiver.archivedData(withRootObject: moved, requiringSecureCoding: false)
            else { return nil }
            plist[key] = rearchived
        }
        return try? PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
    }

    /// Stops the download and keeps what it has, so `start` goes on from there.
    @MainActor func pause(itemID: String) async {
        for task in await backgroundSession().allTasks where task.taskDescription == itemID {
            guard let download = task as? URLSessionDownloadTask else { continue }
            if let data = await download.cancelByProducingResumeData(),
               let folder = try? DownloadStore.prepareFolder(itemID: itemID) {
                try? data.write(to: folder.appending(path: Self.resumeDataName))
            }
        }
    }

    @MainActor func cancel(itemID: String) async {
        for task in await backgroundSession().allTasks where task.taskDescription == itemID {
            task.cancel()
        }
    }

    private func backgroundSession() -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        if let session { return session }
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.timeoutIntervalForRequest = 120
        let created = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session = created
        return created
    }

    private func send(_ update: Update) {
        Task { @MainActor in self.onUpdate?(update) }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let itemID = downloadTask.taskDescription else { return }
        lock.lock()
        let last = lastReported[downloadTask.taskIdentifier] ?? 0
        let due = totalBytesWritten - last >= Self.progressStepBytes
        if due { lastReported[downloadTask.taskIdentifier] = totalBytesWritten }
        lock.unlock()
        guard due else { return }
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        send(.progress(itemID: itemID, bytes: totalBytesWritten, totalBytes: total))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        guard let itemID = downloadTask.taskDescription else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            send(.failed(itemID: itemID, message: JellyfinError.badStatus(status).localizedDescription))
            return
        }
        let suggested = (downloadTask.response?.suggestedFilename ?? "") as NSString
        let fileExtension = suggested.pathExtension.isEmpty ? "mkv" : suggested.pathExtension
        do {
            let folder = try DownloadStore.prepareFolder(itemID: itemID)
            let destination = folder.appending(path: Self.filePrefix + fileExtension)
            try? FileManager.default.removeItem(at: destination)
            // The file at `location` is gone once this method returns.
            try FileManager.default.moveItem(at: location, to: destination)
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            Self.logger.info("Original done: \(size) bytes")
            send(.finished(itemID: itemID, bytes: size))
        } catch {
            send(.failed(itemID: itemID, message: error.localizedDescription))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let itemID = task.taskDescription else { return }
        if (error as? URLError)?.code == .cancelled { return }
        Self.logger.error("Original failed: \(error.localizedDescription, privacy: .public)")
        if var resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            if let server = ActiveServerAddress.url,
               let moved = Self.retargeted(resumeData, to: Self.downloadURL(itemID: itemID, server: server)) {
                resumeData = moved
            }
            let resumed = session.downloadTask(withResumeData: resumeData)
            resumed.taskDescription = itemID
            resumed.resume()
            return
        }
        send(.failed(itemID: itemID, message: error.localizedDescription))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            BackgroundDownloadEvents.completionHandler?()
            BackgroundDownloadEvents.completionHandler = nil
        }
    }
}

@MainActor
enum BackgroundDownloadEvents {
    static var completionHandler: (() -> Void)?
}
