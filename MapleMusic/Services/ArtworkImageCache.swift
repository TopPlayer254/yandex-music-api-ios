import Foundation
import UIKit

@MainActor
final class ArtworkImageCache {
    static let shared = ArtworkImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    private init() {
        memory.countLimit = 160
        memory.totalCostLimit = 96 * 1_024 * 1_024
        let cache = URLCache(
            memoryCapacity: 32 * 1_024 * 1_024,
            diskCapacity: 256 * 1_024 * 1_024,
            diskPath: "MapleMusicArtwork"
        )
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        if let task = inFlight[url] { return await task.value }

        let session = session
        let task = Task<UIImage?, Never> {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  let image = UIImage(data: data)
            else { return nil }
            return image.preparingForDisplay() ?? image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            let cost = max(Int(image.size.width * image.size.height * image.scale * image.scale * 4), 1)
            memory.setObject(image, forKey: url as NSURL, cost: cost)
        }
        return image
    }
}
