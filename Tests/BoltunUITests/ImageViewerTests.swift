import AppKit
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import BoltunKit
@testable import BoltunUI

enum ViewerImages {
    static func cgImage(width: Int, height: Int, hue: CGFloat = 0.1) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(NSColor(hue: hue, saturation: 0.6, brightness: 0.8, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor(hue: hue + 0.5, saturation: 0.6, brightness: 0.9, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        return context.makeImage()!
    }

    static func encode(_ images: [CGImage], type: UTType, properties: [CFString: Any] = [:]) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, images.count, nil)!
        for image in images { CGImageDestinationAddImage(destination, image, properties as CFDictionary) }
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func png(width: Int, height: Int) -> Data {
        encode([cgImage(width: width, height: height)], type: .png)
    }

    static func jpeg(width: Int, height: Int, orientation: Int = 1) -> Data {
        encode([cgImage(width: width, height: height)], type: .jpeg, properties: [kCGImagePropertyOrientation: orientation])
    }

    static func gif(width: Int, height: Int, frames: Int) -> Data {
        let images = (0..<frames).map { cgImage(width: width, height: height, hue: CGFloat($0) / CGFloat(max(frames, 1))) }
        return encode(images, type: .gif, properties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]])
    }
}

@MainActor
final class FakeImageCanvas: ImageCanvasControl {
    var shown: [ImageViewerContent?] = []
    var commands: [ImageZoomCommand] = []

    func show(_ content: ImageViewerContent?) { shown.append(content) }
    func perform(_ command: ImageZoomCommand) { commands.append(command) }
}

@MainActor
enum ViewerFixture {
    static let display = ImageViewerDisplay(size: CGSize(width: 100, height: 100), scale: 1)

    static func file(_ name: String = "wide.png", width: Int = 400, height: Int = 200, preview: Bool = true) -> FileInfo {
        let ext = (name as NSString).pathExtension
        return FileInfo(
            id: "viewer-\(UUID().uuidString)", postId: "p6", name: name, extension: ext, size: 5000,
            mimeType: ext == "gif" ? "image/gif" : "image/\(ext)", width: width, height: height, hasPreviewImage: preview
        )
    }

    static func workspace(_ originals: [String: Data], failing: Set<String> = []) -> (Workspace, URL) {
        let transport = Fixture.transport()
        for (id, data) in originals {
            transport.on("GET", "files/\(id)") { _ in (200, data) }
        }
        for id in failing {
            transport.on("GET", "files/\(id)", status: 500, json: #"{"id":"x","message":"storage offline","status_code":500}"#)
        }
        let workspace = Fixture.workspace(transport: transport)
        let directory = FileManager.default.temporaryDirectory.appending(path: "boltun-viewer-\(UUID().uuidString)")
        workspace.previewDirectory = directory.appending(path: "previews")
        workspace.downloadDirectory = directory.appending(path: "downloads")
        return (workspace, directory)
    }

    static func model(_ workspace: Workspace, _ file: FileInfo, gallery: [FileInfo] = [], display: ImageViewerDisplay = display) -> ImageViewerModel {
        ImageViewerModel(workspace: workspace, file: file, gallery: gallery, display: display)
    }
}

@Suite struct ImageSourcePropertiesTests {
    @Test func readsPixelSizeAndType() throws {
        let properties = try #require(ImageDecoder.properties(ViewerImages.png(width: 40, height: 20)))
        #expect(properties.pixelSize == CGSize(width: 40, height: 20))
        #expect(properties.type == UTType.png.identifier)
        #expect(properties.frameCount == 1)
        #expect(!properties.isAnimatedGIF)
    }

    @Test func swapsDimensionsForRotatedPhotos() throws {
        let properties = try #require(ImageDecoder.properties(ViewerImages.jpeg(width: 40, height: 20, orientation: 6)))
        #expect(properties.pixelSize == CGSize(width: 20, height: 40))
    }

    @Test func detectsAnimatedGifs() throws {
        #expect(try #require(ImageDecoder.properties(ViewerImages.gif(width: 8, height: 8, frames: 3))).isAnimatedGIF)
        #expect(try #require(ImageDecoder.properties(ViewerImages.gif(width: 8, height: 8, frames: 1))).isAnimatedGIF == false)
        #expect(ImageDecoder.properties(Data("nope".utf8)) == nil)
    }

    @Test func decodingFitsTheDisplay() throws {
        let display = ImageViewerDisplay(size: CGSize(width: 50, height: 50), scale: 2)
        let decoded = try #require(ImageViewerDecoding.decode(ViewerImages.png(width: 400, height: 200), hint: .zero, display: display))
        #expect(decoded.still?.image.width == 100)
        #expect(decoded.still?.image.height == 50)
        #expect(!decoded.animated)
        let gif = try #require(ImageViewerDecoding.decode(ViewerImages.gif(width: 8, height: 8, frames: 2), hint: .zero, display: display))
        #expect(gif.animated)
        #expect(gif.still == nil)
        #expect(ImageViewerDecoding.decode(Data("nope".utf8), hint: .zero, display: display) == nil)
    }
}

@MainActor
@Suite struct ImageViewerModelTests {
    @Test func loadsTheOriginalDecodedForTheScreen() async {
        let file = ViewerFixture.file()
        let (workspace, _) = ViewerFixture.workspace([file.id: ViewerImages.png(width: 400, height: 200)])
        let model = ViewerFixture.model(workspace, file)
        #expect(model.pixelSize == CGSize(width: 400, height: 200))
        #expect(model.details == "5 KB · 400 × 200")
        #expect(model.position == nil)
        model.start()
        #expect(model.isLoading)
        #expect(await eventually { model.content?.quality == .full })
        #expect(model.decodedPixel == 100)
        #expect(model.content?.image.size == CGSize(width: 100, height: 50))
        #expect(model.content?.documentSize == CGSize(width: 400, height: 200))
        #expect(model.content?.fileId == file.id)
        #expect(!model.isLoading)
        #expect(model.failure == nil)
        #expect(model.canCopy)
        model.displayChanged(ImageViewerDisplay(size: CGSize(width: 100, height: 100), scale: 2))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(model.decodedPixel == 100)
        model.release()
        #expect(model.content == nil)
        #expect(model.original == nil)
        #expect(!model.canCopy)
    }

    @Test func cachedThumbnailIsShownImmediately() async {
        let file = ViewerFixture.file()
        let (workspace, _) = ViewerFixture.workspace([file.id: ViewerImages.png(width: 400, height: 200)])
        let placeholder = NSImage(size: NSSize(width: 70, height: 35))
        ImageStore.shared.insert(placeholder, for: workspace.session.client.filePreviewURL(id: file.id), maxPixel: ImageThumbnail.maxPixel)
        let model = ViewerFixture.model(workspace, file)
        model.start()
        #expect(model.content?.quality == .preview)
        #expect(model.content?.image === placeholder)
        #expect(model.content?.documentSize == CGSize(width: 400, height: 200))
        #expect(await eventually { model.content?.quality == .full })
        model.release()
    }

    @Test func placeholderSourcesMatchTheThumbnails() {
        let client = Fixture.workspace().session.client
        let file = ViewerFixture.file()
        #expect(ImageViewerModel.placeholderSources(for: file, client: client) == [
            ImageViewerPlaceholderSource(url: client.filePreviewURL(id: file.id), maxPixel: 700),
            ImageViewerPlaceholderSource(url: client.fileThumbnailURL(id: file.id), maxPixel: 108),
        ])
        let gif = ViewerFixture.file("anim.gif", preview: false)
        #expect(ImageViewerModel.placeholderSources(for: gif, client: client) == [
            ImageViewerPlaceholderSource(url: client.fileURL(id: gif.id), maxPixel: 700),
            ImageViewerPlaceholderSource(url: client.fileURL(id: gif.id), maxPixel: 108),
        ])
    }

    @Test func failureKeepsTheFetchedPreview() async {
        let file = ViewerFixture.file()
        let (workspace, _) = ViewerFixture.workspace([:], failing: [file.id])
        let model = ViewerFixture.model(workspace, file)
        model.start()
        #expect(await eventually { model.failure != nil && model.content != nil })
        #expect(model.failure == "Couldn't load image: storage offline")
        #expect(model.content?.quality == .preview)
        #expect(!model.isLoading)
        #expect(!model.canCopy)
        model.release()
    }

    @Test func failureWithoutPreviewShowsOnlyTheError() async {
        let file = ViewerFixture.file(preview: false)
        let (workspace, _) = ViewerFixture.workspace([:], failing: [file.id])
        let model = ViewerFixture.model(workspace, file)
        model.start()
        #expect(await eventually { model.failure != nil })
        #expect(model.content == nil)
    }

    @Test func unsupportedDataIsReported() async {
        let file = ViewerFixture.file(preview: false)
        let (workspace, _) = ViewerFixture.workspace([file.id: Data("nope".utf8)])
        let model = ViewerFixture.model(workspace, file)
        model.start()
        #expect(await eventually { model.failure != nil })
        #expect(model.failure == "This image format isn't supported.")
        #expect(model.original == nil)
    }

    @Test func unknownDimensionsAreResolvedFromTheImage() async {
        let file = ViewerFixture.file(width: 0, height: 0, preview: false)
        let (workspace, _) = ViewerFixture.workspace([file.id: ViewerImages.png(width: 300, height: 150)])
        let model = ViewerFixture.model(workspace, file)
        var resolved: [CGSize] = []
        model.onPixelSizeResolved = { resolved.append($0) }
        #expect(model.pixelSize == .zero)
        #expect(model.details == "5 KB")
        model.start()
        #expect(await eventually { model.content?.quality == .full })
        #expect(model.pixelSize == CGSize(width: 300, height: 150))
        #expect(resolved == [CGSize(width: 300, height: 150)])
        model.release()
    }

    @Test func animatedGifsKeepAllFrames() async {
        let file = ViewerFixture.file("anim.gif", width: 16, height: 8, preview: false)
        let (workspace, _) = ViewerFixture.workspace([file.id: ViewerImages.gif(width: 16, height: 8, frames: 3)])
        let model = ViewerFixture.model(workspace, file)
        model.start()
        #expect(await eventually { model.content?.quality == .full })
        #expect(model.content?.animates == true)
        #expect(model.decodedPixel == 16)
        model.zoomChanged(ImageZoomState(magnification: 8, fit: 1, isFitting: false))
        #expect(model.content?.animates == true)
        model.release()
    }

    @Test func zoomingPastTheDecodedSizeUpgradesToTheOriginal() async {
        let file = ViewerFixture.file()
        let (workspace, _) = ViewerFixture.workspace([file.id: ViewerImages.png(width: 400, height: 200)])
        let model = ViewerFixture.model(workspace, file)
        model.start()
        #expect(await eventually { model.content?.quality == .full })
        model.zoomChanged(ImageZoomState(magnification: 0.25, fit: 0.25, isFitting: true))
        #expect(model.decodedPixel == 100)
        let zoomed = ImageZoomState(magnification: 1, fit: 0.25, isFitting: false)
        model.zoomChanged(zoomed)
        #expect(model.zoom == zoomed)
        #expect(await eventually { model.decodedPixel == 400 })
        #expect(model.content?.image.size == CGSize(width: 400, height: 200))
        #expect(model.content?.documentSize == CGSize(width: 400, height: 200))
        model.release()
    }

    @Test func movingToASharperDisplayUpgrades() async {
        let file = ViewerFixture.file()
        let (workspace, _) = ViewerFixture.workspace([file.id: ViewerImages.png(width: 400, height: 200)])
        let model = ViewerFixture.model(workspace, file)
        model.start()
        #expect(await eventually { model.content?.quality == .full })
        model.zoomChanged(ImageZoomState(magnification: 0.25, fit: 0.25, isFitting: true))
        let retina = ImageViewerDisplay(size: CGSize(width: 100, height: 100), scale: 2)
        model.displayChanged(retina)
        #expect(model.display == retina)
        #expect(await eventually { model.decodedPixel == 400 })
        model.release()
    }

    @Test func navigatesWithinTheGallery() async {
        let files = [ViewerFixture.file("a.png"), ViewerFixture.file("b.png"), ViewerFixture.file("c.png")]
        let (workspace, _) = ViewerFixture.workspace(Dictionary(uniqueKeysWithValues: files.map { ($0.id, ViewerImages.png(width: 40, height: 20)) }))
        let model = ViewerFixture.model(workspace, files[1], gallery: files)
        model.start()
        #expect(model.index == 1)
        #expect(model.position == "2 of 3")
        #expect(model.canGoBack && model.canGoForward)
        model.perform(.navigate(1))
        #expect(model.file.id == files[2].id)
        #expect(workspace.previewFile?.id == files[2].id)
        #expect(!model.canGoForward)
        model.navigate(1)
        #expect(model.index == 2)
        model.navigate(-2)
        #expect(model.index == 0)
        #expect(!model.canGoBack)
        #expect(await eventually { model.content?.fileId == files[0].id && model.content?.quality == .full })
        model.release()
    }

    @Test func showReloadsOnlyForANewFile() async {
        let files = [ViewerFixture.file("a.png"), ViewerFixture.file("b.png")]
        let (workspace, _) = ViewerFixture.workspace(Dictionary(uniqueKeysWithValues: files.map { ($0.id, ViewerImages.png(width: 40, height: 20)) }))
        let model = ViewerFixture.model(workspace, files[0], gallery: [files[0]])
        model.start()
        #expect(await eventually { model.content?.quality == .full })
        let image = model.content?.image
        model.show(files[0], gallery: [files[0]])
        #expect(model.content?.image === image)
        model.show(files[0], gallery: files)
        #expect(model.gallery.count == 2)
        #expect(model.content?.image === image)
        model.show(files[1], gallery: files)
        #expect(model.index == 1)
        #expect(await eventually { model.content?.fileId == files[1].id && model.content?.quality == .full })
        model.release()
    }

    @Test func forwardsZoomCommandsAndContentToTheCanvas() async {
        let file = ViewerFixture.file()
        let (workspace, _) = ViewerFixture.workspace([file.id: ViewerImages.png(width: 40, height: 20)])
        let model = ViewerFixture.model(workspace, file)
        let canvas = FakeImageCanvas()
        model.attach(canvas)
        #expect(canvas.shown.count == 1)
        model.perform(.zoom(.zoomIn))
        model.zoom(.toggle)
        #expect(canvas.commands == [.zoomIn, .toggle])
        model.start()
        #expect(await eventually { canvas.shown.last??.quality == .full })
        model.release()
        #expect(canvas.shown.last ?? nil == nil)
    }

    @Test func closeActionNotifiesTheWindow() {
        let file = ViewerFixture.file()
        let model = ViewerFixture.model(Fixture.workspace(), file)
        var closed = 0
        model.onClose = { closed += 1 }
        model.perform(.close)
        #expect(closed == 1)
    }

    @Test func copiesPngDataAndOtherFormatsAsImages() async {
        let png = ViewerFixture.file()
        let jpeg = ViewerFixture.file("photo.jpg")
        let (workspace, _) = ViewerFixture.workspace([png.id: ViewerImages.png(width: 40, height: 20), jpeg.id: ViewerImages.jpeg(width: 40, height: 20)])
        let model = ViewerFixture.model(workspace, png, gallery: [png, jpeg])
        #expect(!model.copy())
        model.start()
        #expect(await eventually { model.canCopy })
        model.perform(.copy)
        #expect(workspace.pasteboard.data(forType: .png) == model.original)
        model.navigate(1)
        #expect(await eventually { model.canCopy })
        #expect(model.copy())
        #expect(workspace.pasteboard.canReadObject(forClasses: [NSImage.self]))
        model.release()
    }

    @Test func downloadsAndOpensInTheDefaultApp() async {
        let file = ViewerFixture.file()
        let (workspace, directory) = ViewerFixture.workspace([file.id: ViewerImages.png(width: 40, height: 20)])
        defer { try? FileManager.default.removeItem(at: directory) }
        var revealed: [URL] = []
        var opened: [URL] = []
        workspace.revealInFinder = { revealed.append($0) }
        workspace.openExternal = { opened.append($0) }
        let model = ViewerFixture.model(workspace, file)
        #expect(!model.isDownloading)
        model.perform(.download)
        #expect(await eventually { revealed.count == 1 })
        #expect(revealed.first?.lastPathComponent == "wide.png")
        await model.openInDefaultApp()
        #expect(opened.first?.lastPathComponent == "wide.png")
        #expect(opened.first?.deletingLastPathComponent().lastPathComponent == file.id)
    }

    @Test func automationSummaryDescribesTheViewer() async {
        let file = ViewerFixture.file()
        let (workspace, _) = ViewerFixture.workspace([file.id: ViewerImages.png(width: 400, height: 200)])
        let model = ViewerFixture.model(workspace, file)
        model.start()
        #expect(await eventually { model.content?.quality == .full })
        model.zoomChanged(ImageZoomState(magnification: 0.25, fit: 0.25, isFitting: true))
        let summary = DebugAutomation.imageViewerSummary(model)
        #expect(summary == AutomationUIState.ImageViewerSummary(
            fileId: file.id, name: "wide.png", index: 0, count: 1, width: 400, height: 200,
            zoom: "25%", fitting: true, quality: "full", decodedPixel: 100, loading: false, failure: nil
        ))
        model.release()
    }
}

@MainActor
@Suite struct ImageScrollViewTests {
    func content(_ id: String, _ size: CGSize, animates: Bool = false) -> ImageViewerContent {
        ImageViewerContent(fileId: id, image: NSImage(size: size), documentSize: size, animates: animates, quality: .full)
    }

    func hosted(_ size: CGSize = CGSize(width: 400, height: 300)) -> (ImageScrollView, NSWindow) {
        let view = ImageScrollView(frame: CGRect(origin: .zero, size: size))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        return (view, window)
    }

    func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.002 }

    @Test func fitsByDefaultAndFollowsZoomCommands() {
        let (view, window) = hosted()
        defer { window.close() }
        var states: [ImageZoomState] = []
        view.onZoomChange = { states.append($0) }
        view.show(content("a", CGSize(width: 800, height: 600)))
        #expect(view.fit == 0.5)
        #expect(near(view.magnification, 0.5))
        #expect(view.isFitting)
        #expect(view.minMagnification == 0.25)
        #expect(view.maxMagnification == 8)
        view.perform(.zoomIn)
        #expect(near(view.magnification, 2.0 / 3))
        #expect(!view.isFitting)
        view.perform(.actualSize)
        #expect(near(view.magnification, 1))
        view.perform(.toggle)
        #expect(near(view.magnification, 0.5))
        #expect(view.isFitting)
        view.perform(.toggle)
        #expect(near(view.magnification, 1))
        view.perform(.zoomOut)
        #expect(near(view.magnification, 0.75))
        view.apply(.scale(100), at: nil)
        #expect(near(view.magnification, 8))
        view.perform(.fit)
        #expect(near(view.magnification, 0.5))
        view.apply(.scale(0.5), at: nil)
        #expect(view.isFitting)
        #expect(states.last == view.zoomState)
    }

    @Test func refitsOnResizeOnlyWhileFitting() {
        let (view, window) = hosted()
        defer { window.close() }
        view.show(content("a", CGSize(width: 800, height: 600)))
        view.setFrameSize(NSSize(width: 800, height: 600))
        #expect(view.fit == 1)
        #expect(near(view.magnification, 1))
        view.perform(.zoomIn)
        view.setFrameSize(NSSize(width: 400, height: 300))
        #expect(view.fit == 0.5)
        #expect(near(view.magnification, 1.25))
    }

    @Test func swappingTheImageKeepsZoomButANewFileRefits() {
        let (view, window) = hosted()
        defer { window.close() }
        view.show(content("a", CGSize(width: 800, height: 600)))
        view.perform(.actualSize)
        let sharper = content("a", CGSize(width: 800, height: 600))
        view.show(sharper)
        #expect(view.imageView.image === sharper.image)
        #expect(near(view.magnification, 1))
        view.show(content("b", CGSize(width: 200, height: 100), animates: true))
        #expect(view.isFitting)
        #expect(view.fit == 1)
        #expect(view.imageView.animates)
        #expect(view.imageView.frame.size == CGSize(width: 200, height: 100))
        #expect(view.contentView.bounds.origin.x < 0)
        view.show(nil)
        #expect(view.imageView.image == nil)
        #expect(!view.imageView.animates)
    }

    @Test func panningScrollsWhenZoomedIn() {
        let (view, window) = hosted()
        defer { window.close() }
        view.show(content("a", CGSize(width: 800, height: 600)))
        view.perform(.actualSize)
        #expect(view.documentCursor != nil)
        let before = view.contentView.bounds.origin
        view.pan(by: CGSize(width: 20, height: 10))
        let after = view.contentView.bounds.origin
        #expect(near(after.x, before.x - 20))
        #expect(near(after.y, before.y + 10))
        view.pan(by: CGSize(width: 10_000, height: 10_000))
        #expect(near(view.contentView.bounds.origin.x, 0))
        view.perform(.fit)
        #expect(view.documentCursor == nil)
    }

    @Test func dragCursorIsBalanced() {
        let (view, window) = hosted()
        defer { window.close() }
        view.show(content("a", CGSize(width: 800, height: 600)))
        view.imageView.onPanning(true)
        #expect(!view.isPanning)
        view.imageView.onPanning(false)
        view.perform(.actualSize)
        view.imageView.onPanning(true)
        #expect(view.isPanning)
        view.imageView.onPanning(true)
        view.imageView.onPanning(false)
        #expect(!view.isPanning)
    }

    @Test func mouseEventsDriveTheDocumentView() throws {
        let view = ImageDocumentView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        var clicks: [NSPoint] = []
        var panning: [Bool] = []
        var pans: [CGSize] = []
        view.onDoubleClick = { clicks.append($0) }
        view.onPanning = { panning.append($0) }
        view.onPan = { pans.append($0) }
        func event(_ type: NSEvent.EventType, clicks: Int) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: 10, y: 20), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown, clicks: 1))
        view.mouseDragged(with: try event(.leftMouseDragged, clicks: 1))
        view.mouseUp(with: try event(.leftMouseUp, clicks: 1))
        view.mouseDown(with: try event(.leftMouseDown, clicks: 2))
        #expect(panning == [true, false])
        #expect(pans.count == 1)
        #expect(clicks == [NSPoint(x: 10, y: 20)])
    }

    @Test func doubleClickTogglesAroundThePoint() {
        let (view, window) = hosted()
        defer { window.close() }
        view.show(content("a", CGSize(width: 800, height: 600)))
        view.toggle(at: NSPoint(x: 100, y: 100))
        #expect(near(view.magnification, 1))
        view.imageView.onDoubleClick(NSPoint(x: 400, y: 300))
        #expect(view.isFitting)
    }

    @Test func clipViewCentersSmallDocuments() {
        let clip = ImageCanvasClipView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        clip.documentView = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let rect = clip.constrainBoundsRect(CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(rect.origin == CGPoint(x: -150, y: -100))
    }

    @Test func documentViewDoesNotTakeFocusOrMoveTheWindow() {
        let view = ImageDocumentView()
        #expect(!view.acceptsFirstResponder)
        #expect(!view.mouseDownCanMoveWindow)
        #expect(view.acceptsFirstMouse(for: nil))
    }
}

@MainActor
@Suite(.serialized) struct ImageViewerWindowTests {
    func keyEvent(_ keyCode: UInt16, _ characters: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        )!
    }

    @Test func frameFitsTheImageInsideTheScreen() {
        let visible = CGRect(x: 0, y: 40, width: 1000, height: 800)
        let titlebar = ImageViewerWindowController.titlebarHeight
        #expect(titlebar > 0)
        let large = ImageViewerWindowController.frame(imageSize: CGSize(width: 4000, height: 2000), visible: visible)
        #expect(large.width == 900)
        #expect(large.height == 450 + ImageViewerLayout.headerHeight + titlebar)
        #expect(large.midX == visible.midX)
        #expect(abs(large.midY - visible.midY) <= 0.5)
        let small = ImageViewerWindowController.frame(imageSize: CGSize(width: 10, height: 10), visible: visible)
        #expect(small.size == CGSize(width: 520, height: 360 + titlebar))
    }

    @Test func windowMapsKeysToActions() {
        let window = ImageViewerWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        var actions: [ImageViewerAction] = []
        window.onAction = { actions.append($0) }
        #expect(window.handle(keyEvent(ImageViewerKey.rightArrow)))
        #expect(window.performKeyEquivalent(with: keyEvent(24, "=", modifiers: .command)))
        #expect(!window.handle(keyEvent(0, "a")))
        window.cancelOperation(nil)
        #expect(actions == [.navigate(1), .zoom(.zoomIn), .close])
    }

    @Test func presenterOpensReusesAndClosesTheViewer() async throws {
        _ = NSApplication.shared
        let files = [ViewerFixture.file("a.png"), ViewerFixture.file("b.png")]
        let (workspace, _) = ViewerFixture.workspace(Dictionary(uniqueKeysWithValues: files.map { ($0.id, ViewerImages.png(width: 40, height: 20)) }))
        let presenter = ImageViewerPresenter()
        presenter.screen = { nil }
        presenter.sync(workspace)
        #expect(presenter.window == nil)
        workspace.previewImage(files[1], in: files)
        presenter.sync(workspace)
        let window = try #require(presenter.window as? ImageViewerWindow)
        let model = try #require(presenter.model(for: workspace))
        #expect(window.title == "b.png")
        #expect(window.isVisible)
        #expect(window.identifier?.rawValue == "image-viewer")
        #expect(window.appearance?.name == .darkAqua)
        #expect(model.index == 1)
        #expect(await eventually { model.content?.quality == .full })
        workspace.previewImage(files[0], in: files)
        presenter.sync(workspace)
        #expect(presenter.model === model)
        #expect(model.index == 0)
        #expect(window.handle(keyEvent(ImageViewerKey.rightArrow)))
        #expect(workspace.previewFile?.id == files[1].id)

        let other = ViewerFixture.workspace([:]).0
        other.previewImage(files[0])
        presenter.sync(other)
        #expect(workspace.previewFile == nil)
        #expect(workspace.previewGallery.isEmpty)
        #expect(model.content == nil)
        #expect(!window.isVisible)
        #expect(presenter.model(for: workspace) == nil)
        let second = try #require(presenter.model(for: other))
        second.perform(.close)
        #expect(presenter.controller == nil)
        #expect(other.previewFile == nil)

        workspace.previewImage(files[0], in: files)
        presenter.sync(workspace)
        #expect(presenter.window != nil)
        workspace.previewFile = nil
        presenter.sync(workspace)
        #expect(presenter.window == nil)
        presenter.close(for: workspace)
    }

    @Test func resizesOnceTheImageSizeIsKnown() throws {
        let file = ViewerFixture.file(width: 0, height: 0)
        let model = ViewerFixture.model(Fixture.workspace(), file)
        let controller = ImageViewerWindowController(model: model, screen: nil)
        defer { controller.close() }
        let window = try #require(controller.window)
        #expect(window.contentRect(forFrameRect: window.frame).size == ImageViewerLayout.fallbackContent)
        controller.resize(toFit: CGSize(width: 800, height: 400))
        #expect(window.contentRect(forFrameRect: window.frame).size == CGSize(width: 800, height: 400 + ImageViewerLayout.headerHeight))
        controller.windowDidChangeScreen(Notification(name: NSWindow.didChangeScreenNotification))
        controller.windowDidChangeBackingProperties(Notification(name: NSWindow.didChangeBackingPropertiesNotification))
        #expect(model.display == ImageViewerDisplay.of(window.screen))
    }

    @Test func rendersHeaderAndImage() async {
        let files = [ViewerFixture.file("a.png"), ViewerFixture.file("b.png")]
        let (workspace, _) = ViewerFixture.workspace(Dictionary(uniqueKeysWithValues: files.map { ($0.id, ViewerImages.png(width: 400, height: 200)) }))
        let model = ViewerFixture.model(workspace, files[0], gallery: files, display: .fallback)
        model.start()
        #expect(await eventually { model.content?.quality == .full })
        let rep = await MainSnapshot.render(ImageViewerView(model: model), size: CGSize(width: 900, height: 600), name: "image-viewer", settle: .milliseconds(600))
        #expect(MainSnapshot.distinctColors(rep) > 4)
        #expect(model.content?.quality == .full)
        #expect(model.zoom.isFitting)
        model.release()
        let failing = ViewerFixture.file(preview: false)
        let broken = ViewerFixture.model(ViewerFixture.workspace([:], failing: [failing.id]).0, failing)
        broken.start()
        await MainSnapshot.render(ImageViewerView(model: broken), size: CGSize(width: 600, height: 400), name: "image-viewer-failed", settle: .milliseconds(400))
        #expect(broken.failure != nil)
    }
}
