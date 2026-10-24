import AppKit
import BoltunKit
import ImageIO
import SwiftUI

@MainActor
final class ImageStore {
    static let shared = ImageStore()

    private let cache = NSCache<NSString, NSImage>()
    private var inflight: [String: Task<NSImage?, Never>] = [:]
    private var failures: [String: Date] = [:]
    var fetcher: @Sendable (URL, APIClient?) async throws -> Data = { url, client in
        if let client { return try await client.data(at: url) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError.invalidResponse }
        return data
    }

    init(costLimit: Int = 96 << 20) {
        cache.totalCostLimit = costLimit
        cache.countLimit = 1500
    }

    static func key(_ url: URL, maxPixel: CGFloat) -> String {
        "\(url.absoluteString)#\(Int(maxPixel))"
    }

    static func authorizedClient(for url: URL, client: APIClient?) -> APIClient? {
        guard let client else { return nil }
        let base = client.baseURL
        guard url.scheme == base.scheme, url.host() == base.host(), url.port == base.port else { return nil }
        return client
    }

    func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        cache.object(forKey: Self.key(url, maxPixel: maxPixel) as NSString)
    }

    func insert(_ image: NSImage, for url: URL, maxPixel: CGFloat) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: Self.key(url, maxPixel: maxPixel) as NSString, cost: cost)
    }

    func image(for url: URL, client: APIClient?, maxPixel: CGFloat) async -> NSImage? {
        let key = Self.key(url, maxPixel: maxPixel)
        if let hit = cache.object(forKey: key as NSString) { return hit }
        if let failedAt = failures[key], Date().timeIntervalSince(failedAt) < 60 { return nil }
        if let running = inflight[key] { return await running.value }
        let authorized = Self.authorizedClient(for: url, client: client)
        let fetch = fetcher
        let task = Task<NSImage?, Never> {
            guard let data = try? await fetch(url, authorized) else { return nil }
            let decoded = await Task.detached(priority: .utility) { ImageDecoder.decode(data, maxPixel: maxPixel) }.value
            return decoded.map { NSImage(cgImage: $0.image, size: NSSize(width: $0.image.width, height: $0.image.height)) }
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        if let image {
            insert(image, for: url, maxPixel: maxPixel)
        } else {
            failures[key] = Date()
        }
        return image
    }

    func removeAll() {
        cache.removeAllObjects()
        failures.removeAll()
    }
}

struct DecodedImage: @unchecked Sendable {
    let image: CGImage
}

enum ImageDecoder {
    static func decode(_ data: Data, maxPixel: CGFloat) -> DecodedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return DecodedImage(image: image)
    }
}

struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    let client: APIClient?
    var maxPixel: CGFloat = 256
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var loaded: NSImage?

    var body: some View {
        let image = loaded ?? url.flatMap { ImageStore.shared.cached($0, maxPixel: maxPixel) }
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url, ImageStore.shared.cached(url, maxPixel: maxPixel) == nil else { return }
            loaded = await ImageStore.shared.image(for: url, client: client, maxPixel: maxPixel)
        }
    }
}
