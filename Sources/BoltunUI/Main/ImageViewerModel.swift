import AppKit
import BoltunKit
import Observation
import UniformTypeIdentifiers

enum ImageViewerQuality: Equatable {
    case preview
    case full
}

struct ImageViewerContent {
    let fileId: String
    let image: NSImage
    let documentSize: CGSize
    let animates: Bool
    let quality: ImageViewerQuality
}

struct ImageViewerPlaceholderSource: Equatable {
    let url: URL
    let maxPixel: CGFloat
}

@MainActor
@Observable
final class ImageViewerModel {
    let workspace: Workspace
    private(set) var gallery: [FileInfo]
    private(set) var index: Int
    private(set) var content: ImageViewerContent?
    private(set) var pixelSize: CGSize
    private(set) var isLoading = false
    private(set) var failure: String?
    private(set) var original: Data?
    private(set) var zoom = ImageZoomState()
    private(set) var display: ImageViewerDisplay
    @ObservationIgnored private(set) weak var canvas: ImageCanvasControl?
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored var onPixelSizeResolved: (CGSize) -> Void = { _ in }
    @ObservationIgnored private(set) var decodedPixel: CGFloat = 0
    @ObservationIgnored private var sourceType: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var isUpgrading = false
    @ObservationIgnored private var hasZoomReport = false

    init(workspace: Workspace, file: FileInfo, gallery: [FileInfo], display: ImageViewerDisplay) {
        let normalized = ImageGallery.normalized(gallery, selecting: file)
        self.workspace = workspace
        self.gallery = normalized
        self.index = ImageGallery.index(of: file, in: normalized)
        self.display = display
        self.pixelSize = Self.pixelSize(of: file)
    }

    var file: FileInfo { gallery[index] }
    var client: APIClient { workspace.session.client }
    var details: String { ImageViewerFormat.details(file: file, pixelSize: pixelSize) }
    var position: String? { ImageGallery.position(index: index, count: gallery.count) }
    var canGoBack: Bool { ImageGallery.index(from: index, offset: -1, count: gallery.count) != nil }
    var canGoForward: Bool { ImageGallery.index(from: index, offset: 1, count: gallery.count) != nil }
    var canCopy: Bool { original != nil }
    var isDownloading: Bool { workspace.downloading.contains(file.id) }

    static func pixelSize(of file: FileInfo) -> CGSize {
        file.width > 0 && file.height > 0 ? CGSize(width: file.width, height: file.height) : .zero
    }

    static func placeholderSources(for file: FileInfo, client: APIClient) -> [ImageViewerPlaceholderSource] {
        let paneURL = ChannelFileThumbnail.thumbnailURL(for: file, client: client)
        let paneSource = paneURL.map { ImageViewerPlaceholderSource(url: $0, maxPixel: ChannelFileThumbnail.maxPixel(size: ChannelFileThumbnail.defaultSize)) }
        return [ImageViewerPlaceholderSource(url: ImageThumbnail.url(for: file, client: client), maxPixel: ImageThumbnail.maxPixel), paneSource].compactMap(\.self)
    }

    func start() {
        load()
    }

    func show(_ file: FileInfo, gallery: [FileInfo]) {
        let normalized = ImageGallery.normalized(gallery, selecting: file)
        guard file.id != self.file.id || normalized.map(\.id) != self.gallery.map(\.id) else { return }
        let reload = file.id != self.file.id
        self.gallery = normalized
        index = ImageGallery.index(of: file, in: normalized)
        if reload { load() }
    }

    func navigate(_ offset: Int) {
        guard let target = ImageGallery.index(from: index, offset: offset, count: gallery.count) else { return }
        index = target
        workspace.previewFile = file
        load()
    }

    func perform(_ action: ImageViewerAction) {
        switch action {
        case .close: onClose()
        case .zoom(let command): zoom(command)
        case .navigate(let offset): navigate(offset)
        case .copy: copy()
        case .download: download()
        }
    }

    func attach(_ canvas: ImageCanvasControl) {
        self.canvas = canvas
        canvas.show(content)
    }

    func zoom(_ command: ImageZoomCommand) {
        canvas?.perform(command)
    }

    func zoomChanged(_ state: ImageZoomState) {
        hasZoomReport = true
        if zoom != state { zoom = state }
        upgradeIfNeeded()
    }

    func displayChanged(_ value: ImageViewerDisplay) {
        if display != value { display = value }
        upgradeIfNeeded()
    }

    func download() {
        let file = file
        Task { await workspace.download(file) }
    }

    func openInDefaultApp() async {
        guard let url = await workspace.previewCopy(of: file) else { return }
        workspace.openExternal(url)
    }

    @discardableResult
    func copy() -> Bool {
        guard let original else { return false }
        let pasteboard = workspace.pasteboard
        pasteboard.clearContents()
        if sourceType == UTType.png.identifier { return pasteboard.setData(original, forType: .png) }
        guard let image = NSImage(data: original) else { return false }
        return pasteboard.writeObjects([image])
    }

    func release() {
        generation += 1
        tasks.forEach { $0.cancel() }
        tasks = []
        setContent(nil)
        original = nil
        sourceType = nil
        decodedPixel = 0
        isUpgrading = false
        isLoading = false
    }

    private func load() {
        release()
        let file = file
        let current = generation
        pixelSize = Self.pixelSize(of: file)
        failure = nil
        isLoading = true
        if let cached = cachedPlaceholder(for: file) {
            showPlaceholder(cached, fileId: file.id)
        } else if file.hasPreviewImage {
            tasks.append(Task { [weak self] in await self?.loadPreview(file, generation: current) })
        }
        tasks.append(Task { [weak self] in await self?.loadOriginal(file, generation: current) })
    }

    private func cachedPlaceholder(for file: FileInfo) -> NSImage? {
        Self.placeholderSources(for: file, client: client).lazy.compactMap { ImageStore.shared.cached($0.url, maxPixel: $0.maxPixel) }.first
    }

    private func isCurrent(_ value: Int) -> Bool {
        !Task.isCancelled && generation == value
    }

    private func showPlaceholder(_ image: NSImage, fileId: String) {
        guard content == nil else { return }
        let size = pixelSize.width > 0 ? pixelSize : image.size
        setContent(ImageViewerContent(fileId: fileId, image: image, documentSize: size, animates: false, quality: .preview))
    }

    private func loadPreview(_ file: FileInfo, generation current: Int) async {
        let source = ImageViewerPlaceholderSource(url: client.filePreviewURL(id: file.id), maxPixel: ImageThumbnail.maxPixel)
        guard let image = await ImageStore.shared.image(for: source.url, client: client, maxPixel: source.maxPixel), isCurrent(current) else { return }
        showPlaceholder(image, fileId: file.id)
    }

    private func loadOriginal(_ file: FileInfo, generation current: Int) async {
        let data: Data
        do {
            data = try await client.data(at: client.fileURL(id: file.id))
        } catch {
            guard isCurrent(current) else { return }
            fail("Couldn't load image: \(APIError.wrap(error).localizedDescription)")
            return
        }
        guard isCurrent(current) else { return }
        let hint = pixelSize
        let display = display
        let decoded = await Task.detached(priority: .userInitiated) { ImageViewerDecoding.decode(data, hint: hint, display: display) }.value
        guard isCurrent(current) else { return }
        guard let decoded else {
            fail("This image format isn't supported.")
            return
        }
        let wasUnknown = pixelSize.width <= 0
        original = data
        sourceType = decoded.properties?.type
        if let size = decoded.properties?.pixelSize, size.width > 0, size.height > 0 { pixelSize = size }
        let image: NSImage
        if decoded.animated, let animated = NSImage(data: data) {
            image = animated
            decodedPixel = max(pixelSize.width, pixelSize.height)
        } else if let still = decoded.still {
            image = NSImage(cgImage: still.image, size: NSSize(width: still.image.width, height: still.image.height))
            decodedPixel = CGFloat(max(still.image.width, still.image.height))
            if pixelSize.width <= 0 { pixelSize = image.size }
        } else {
            fail("This image format isn't supported.")
            return
        }
        setContent(ImageViewerContent(fileId: file.id, image: image, documentSize: pixelSize, animates: decoded.animated, quality: .full))
        isLoading = false
        if wasUnknown { onPixelSizeResolved(pixelSize) }
        upgradeIfNeeded()
    }

    private func setContent(_ value: ImageViewerContent?) {
        content = value
        canvas?.show(value)
    }

    private func fail(_ message: String) {
        failure = message
        isLoading = false
    }

    private func upgradeIfNeeded() {
        guard hasZoomReport, !isUpgrading, let original, let content, content.quality == .full, !content.animates,
              let target = ImageViewerLayout.upgradePixel(
                  magnification: zoom.magnification,
                  document: content.documentSize,
                  scale: display.scale,
                  decoded: decodedPixel,
                  original: max(pixelSize.width, pixelSize.height)
              )
        else { return }
        isUpgrading = true
        let current = generation
        tasks.append(Task { [weak self] in
            let decoded = await Task.detached(priority: .userInitiated) { ImageDecoder.decode(original, maxPixel: target) }.value
            self?.applyUpgrade(decoded, target: target, generation: current)
        })
    }

    private func applyUpgrade(_ decoded: DecodedImage?, target: CGFloat, generation current: Int) {
        guard generation == current, let content else { return }
        isUpgrading = false
        guard let decoded else {
            decodedPixel = target
            return
        }
        decodedPixel = max(target, CGFloat(max(decoded.image.width, decoded.image.height)))
        let image = NSImage(cgImage: decoded.image, size: NSSize(width: decoded.image.width, height: decoded.image.height))
        setContent(ImageViewerContent(fileId: content.fileId, image: image, documentSize: content.documentSize, animates: false, quality: .full))
    }
}

struct ImageViewerDecoded: Sendable {
    let properties: ImageSourceProperties?
    let still: DecodedImage?
    let animated: Bool
}

enum ImageViewerDecoding {
    static func decode(_ data: Data, hint: CGSize, display: ImageViewerDisplay) -> ImageViewerDecoded? {
        let properties = ImageDecoder.properties(data)
        if properties?.isAnimatedGIF == true { return ImageViewerDecoded(properties: properties, still: nil, animated: true) }
        let size = properties.map(\.pixelSize).flatMap { $0.width > 0 ? $0 : nil } ?? hint
        guard let still = ImageDecoder.decode(data, maxPixel: ImageViewerLayout.decodePixel(image: size, display: display)) else { return nil }
        return ImageViewerDecoded(properties: properties, still: still, animated: false)
    }
}
