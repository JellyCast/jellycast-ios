import UIKit

/// Loads server images once: decoded ones in a bounded memory cache, responses in a disk cache.
/// Both are keyed without the server's address, so an image stays cached across its addresses.
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession
    private let disk: URLCache
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private static let memoryLimitBytes = 150 * 1024 * 1024
    private static let diskLimitBytes = 400 * 1024 * 1024

    private init() {
        memory.totalCostLimit = Self.memoryLimitBytes
        disk = URLCache(
            memoryCapacity: 0,
            diskCapacity: Self.diskLimitBytes,
            directory: URL.cachesDirectory.appending(path: "images")
        )
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: Self.cacheKey(url) as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        let key = Self.cacheKey(url)
        if let cached = memory.object(forKey: key as NSURL) { return cached }
        if let running = inFlight[key] { return await running.value }
        let task = Task { [session, disk] in await Self.fetch(url, key: key, session: session, disk: disk) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            memory.setObject(image, forKey: key as NSURL, cost: cost)
        }
        return image
    }

    /// The image's path and query; the tag in it changes with the image, so a cached copy never
    /// goes stale.
    private static func cacheKey(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "jellycast"
        components?.host = "server"
        components?.port = nil
        return components?.url ?? url
    }

    @concurrent
    private static func fetch(_ url: URL, key: URL, session: URLSession, disk: URLCache) async -> UIImage? {
        let keyRequest = URLRequest(url: key)
        if let cached = disk.cachedResponse(for: keyRequest) {
            return await UIImage(data: cached.data)?.byPreparingForDisplay()
        }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        disk.storeCachedResponse(CachedURLResponse(response: response, data: data), for: keyRequest)
        return await UIImage(data: data)?.byPreparingForDisplay()
    }
}
