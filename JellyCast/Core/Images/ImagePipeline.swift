import UIKit

/// Loads server images once: decoded ones in a bounded memory cache, responses in a disk cache.
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private static let memoryLimitBytes = 150 * 1024 * 1024
    private static let diskLimitBytes = 400 * 1024 * 1024

    private init() {
        memory.totalCostLimit = Self.memoryLimitBytes
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 0,
            diskCapacity: Self.diskLimitBytes,
            directory: URL.cachesDirectory.appending(path: "images")
        )
        // The tag in every image URL changes with the image, so a cached copy never goes stale.
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        if let running = inFlight[url] { return await running.value }
        let task = Task { [session] in await Self.fetch(url, session: session) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            memory.setObject(image, forKey: url as NSURL, cost: cost)
        }
        return image
    }

    @concurrent
    private static func fetch(_ url: URL, session: URLSession) async -> UIImage? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return await UIImage(data: data)?.byPreparingForDisplay()
    }
}
