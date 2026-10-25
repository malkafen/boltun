import AppKit
import Foundation
import Testing
@testable import BoltunKit
@testable import BoltunUI

@Suite struct ImageViewerLayoutTests {
    let roomy = CGSize(width: 1800, height: 1000)

    @Test func availableAreaIsAFractionOfTheVisibleFrameMinusTitlebar() {
        let area = ImageViewerLayout.available(visible: CGSize(width: 1000, height: 800), titlebar: 28)
        #expect(area == CGSize(width: 900, height: 692))
        #expect(ImageViewerLayout.available(visible: CGSize(width: 10, height: 10), titlebar: 28).height == 0)
    }

    @Test func largeImagesShrinkToTheAvailableAreaKeepingAspect() {
        let size = ImageViewerLayout.contentSize(image: CGSize(width: 4000, height: 2000), available: roomy, header: 50)
        #expect(size == CGSize(width: 1800, height: 950))
        let tall = ImageViewerLayout.contentSize(image: CGSize(width: 1000, height: 3800), available: roomy, header: 50, minimum: .zero)
        #expect(tall == CGSize(width: 250, height: 1000))
        let floored = ImageViewerLayout.contentSize(image: CGSize(width: 1000, height: 3800), available: roomy, header: 50)
        #expect(floored == CGSize(width: 520, height: 1000))
    }

    @Test func mediumImagesOpenAtNaturalSize() {
        let size = ImageViewerLayout.contentSize(image: CGSize(width: 1280, height: 720), available: roomy, header: 46)
        #expect(size == CGSize(width: 1280, height: 766))
    }

    @Test func smallImagesGetTheMinimumWindow() {
        let size = ImageViewerLayout.contentSize(image: CGSize(width: 64, height: 48), available: roomy)
        #expect(size == ImageViewerLayout.minimumContent)
    }

    @Test func unknownDimensionsUseTheFallbackSize() {
        #expect(ImageViewerLayout.contentSize(image: .zero, available: roomy) == ImageViewerLayout.fallbackContent)
        #expect(ImageViewerLayout.contentSize(image: .zero, available: CGSize(width: 600, height: 400)) == CGSize(width: 600, height: 400))
    }

    @Test func minimumNeverExceedsTheScreen() {
        let size = ImageViewerLayout.contentSize(image: CGSize(width: 64, height: 48), available: CGSize(width: 300, height: 200))
        #expect(size == CGSize(width: 300, height: 200))
    }

    @Test func framesAreCenteredInTheVisibleArea() {
        let frame = ImageViewerLayout.centered(size: CGSize(width: 200, height: 100), in: CGRect(x: 100, y: 50, width: 1000, height: 800))
        #expect(frame == CGRect(x: 500, y: 400, width: 200, height: 100))
    }

    @Test func decodesAtTheScreenBackingSize() {
        let retina = ImageViewerDisplay(size: CGSize(width: 1440, height: 900), scale: 2)
        #expect(ImageViewerLayout.decodePixel(image: CGSize(width: 11520, height: 3600), display: retina) == 2880)
        #expect(ImageViewerLayout.decodePixel(image: CGSize(width: 1000, height: 7200), display: retina) == 1800)
        #expect(ImageViewerLayout.decodePixel(image: CGSize(width: 800, height: 600), display: retina) == 800)
        #expect(ImageViewerLayout.decodePixel(image: .zero, display: retina) == 2880)
        let plain = ImageViewerDisplay(size: CGSize(width: 1920, height: 1080), scale: 1)
        #expect(ImageViewerLayout.decodePixel(image: CGSize(width: 3840, height: 2160), display: plain) == 1920)
    }

    @Test func decodeIsCapped() {
        let huge = ImageViewerDisplay(size: CGSize(width: 10000, height: 10000), scale: 1)
        #expect(ImageViewerLayout.decodePixel(image: CGSize(width: 20000, height: 100), display: huge) == ImageViewerLayout.maximumDecodePixel)
        #expect(ImageViewerLayout.decodePixel(image: .zero, display: huge) == ImageViewerLayout.maximumDecodePixel)
    }

    @Test func upgradesOnlyWhenZoomNeedsMorePixels() {
        let document = CGSize(width: 6000, height: 4000)
        #expect(ImageViewerLayout.upgradePixel(magnification: 0.45, document: document, scale: 1, decoded: 2700, original: 6000) == nil)
        #expect(ImageViewerLayout.upgradePixel(magnification: 0.46, document: document, scale: 1, decoded: 2700, original: 6000) == nil)
        #expect(ImageViewerLayout.upgradePixel(magnification: 1, document: document, scale: 2, decoded: 2700, original: 6000) == 6000)
        #expect(ImageViewerLayout.upgradePixel(magnification: 4, document: document, scale: 2, decoded: 6000, original: 6000) == nil)
        #expect(ImageViewerLayout.upgradePixel(magnification: 1, document: document, scale: 2, decoded: 0, original: 6000) == nil)
        let giant = CGSize(width: 20000, height: 1000)
        #expect(ImageViewerLayout.upgradePixel(magnification: 1, document: giant, scale: 1, decoded: 4000, original: 20000) == ImageViewerLayout.maximumDecodePixel)
        #expect(ImageViewerLayout.upgradePixel(magnification: 1, document: giant, scale: 1, decoded: 8192, original: 20000) == nil)
    }

    @MainActor
    @Test func displayFallsBackWithoutScreen() {
        #expect(ImageViewerDisplay.of(nil) == .fallback)
    }
}

@Suite struct ImageZoomTests {
    @Test func fitNeverUpscales() {
        #expect(ImageZoom.fit(document: CGSize(width: 800, height: 600), viewport: CGSize(width: 400, height: 400)) == 0.5)
        #expect(ImageZoom.fit(document: CGSize(width: 100, height: 100), viewport: CGSize(width: 400, height: 400)) == 1)
        #expect(ImageZoom.fit(document: .zero, viewport: CGSize(width: 400, height: 400)) == 1)
        #expect(ImageZoom.fit(document: CGSize(width: 10, height: 10), viewport: .zero) == 1)
    }

    @Test func limitsAllowZoomingOutBelowFitForSmallImages() {
        #expect(ImageZoom.limits(fit: 1) == 0.25...8)
        #expect(ImageZoom.limits(fit: 0.1) == 0.1...8)
        #expect(ImageZoom.limits(fit: 0.001) == 0.01...8)
    }

    @Test func zoomInWalksTheLadder() {
        let limits = ImageZoom.limits(fit: 0.4)
        #expect(ImageZoom.zoomIn(from: 0.4, limits: limits) == 0.5)
        #expect(ImageZoom.zoomIn(from: 1, limits: limits) == 1.25)
        #expect(ImageZoom.zoomIn(from: 0.9, limits: limits) == 1)
        #expect(ImageZoom.zoomIn(from: 8, limits: limits) == 8)
        #expect(ImageZoom.zoomIn(from: 7, limits: limits) == 8)
    }

    @Test func zoomOutWalksTheLadderAndStopsAtTheMinimum() {
        let limits = ImageZoom.limits(fit: 0.4)
        #expect(ImageZoom.zoomOut(from: 1, limits: limits) == 0.75)
        #expect(ImageZoom.zoomOut(from: 0.5, limits: limits) == 1.0 / 3)
        #expect(ImageZoom.zoomOut(from: 0.25, limits: limits) == 0.25)
        #expect(ImageZoom.zoomOut(from: 0.05, limits: ImageZoom.limits(fit: 0.01)) == 0.01)
    }

    @Test func clampRespectsLimits() {
        #expect(ImageZoom.clamp(20, to: 0.5...8) == 8)
        #expect(ImageZoom.clamp(0.1, to: 0.5...8) == 0.5)
        #expect(ImageZoom.clamp(2, to: 0.5...8) == 2)
    }

    @Test func scrollZoomIsSmoothAndClamped() {
        let limits = ImageZoom.limits(fit: 0.5)
        #expect(ImageZoom.scrolled(from: 1, delta: 0, precise: true, limits: limits) == 1)
        #expect(ImageZoom.scrolled(from: 1, delta: 10, precise: true, limits: limits) > 1)
        #expect(ImageZoom.scrolled(from: 1, delta: -10, precise: true, limits: limits) < 1)
        #expect(abs(ImageZoom.scrolled(from: 1, delta: 1, precise: false, limits: limits) - ImageZoom.scrolled(from: 1, delta: 10, precise: true, limits: limits)) < 1e-9)
        #expect(ImageZoom.scrolled(from: 1, delta: 1000, precise: true, limits: limits) == 8)
        #expect(ImageZoom.scrolled(from: 1, delta: -1000, precise: true, limits: limits) == 0.25)
    }

    @Test func commandsMapToTargets() {
        let fitting = ImageZoomState(magnification: 0.5, fit: 0.5, isFitting: true)
        #expect(ImageZoom.target(for: .zoomIn, state: fitting) == .scale(2.0 / 3))
        #expect(ImageZoom.target(for: .zoomOut, state: fitting) == .scale(1.0 / 3))
        #expect(ImageZoom.target(for: .fit, state: fitting) == .fit)
        #expect(ImageZoom.target(for: .actualSize, state: fitting) == .scale(1))
        #expect(ImageZoom.target(for: .toggle, state: fitting) == .scale(1))
        let zoomed = ImageZoomState(magnification: 1, fit: 0.5, isFitting: false)
        #expect(ImageZoom.target(for: .toggle, state: zoomed) == .fit)
    }

    @Test func stateDescribesAvailableZoom() {
        let state = ImageZoomState(magnification: 0.25, fit: 1, isFitting: false)
        #expect(!state.canZoomOut)
        #expect(state.canZoomIn)
        #expect(state.percent == "25%")
        #expect(!ImageZoomState(magnification: 8, fit: 1, isFitting: false).canZoomIn)
        #expect(ImageZoom.percent(2.0 / 3) == "67%")
        #expect(ImageZoom.isFit(0.5, fit: 0.5004))
        #expect(!ImageZoom.isFit(0.5, fit: 0.51))
    }
}

@Suite struct ImageCanvasGeometryTests {
    @Test func centersDocumentsSmallerThanTheViewport() {
        let rect = ImageCanvasGeometry.centered(bounds: CGRect(x: 0, y: 0, width: 400, height: 300), document: CGSize(width: 100, height: 500))
        #expect(rect == CGRect(x: -150, y: 0, width: 400, height: 300))
        let large = CGRect(x: 30, y: 40, width: 100, height: 100)
        #expect(ImageCanvasGeometry.centered(bounds: large, document: CGSize(width: 500, height: 500)) == large)
    }

    @Test func panningMovesAgainstTheDragScaledByMagnification() {
        let origin = CGPoint(x: 100, y: 100)
        #expect(ImageCanvasGeometry.panned(origin: origin, delta: CGSize(width: 20, height: 10), magnification: 2, flipped: false) == CGPoint(x: 90, y: 105))
        #expect(ImageCanvasGeometry.panned(origin: origin, delta: CGSize(width: -20, height: 10), magnification: 1, flipped: true) == CGPoint(x: 120, y: 90))
        #expect(ImageCanvasGeometry.panned(origin: origin, delta: .zero, magnification: 0, flipped: false) == origin)
    }

    @Test func panIsPossibleOnlyWhenZoomedPastTheViewport() {
        let viewport = CGSize(width: 400, height: 300)
        #expect(!ImageCanvasGeometry.canPan(document: CGSize(width: 800, height: 600), magnification: 0.5, viewport: viewport))
        #expect(ImageCanvasGeometry.canPan(document: CGSize(width: 800, height: 600), magnification: 1, viewport: viewport))
        #expect(ImageCanvasGeometry.canPan(document: CGSize(width: 100, height: 400), magnification: 1, viewport: viewport))
    }
}

@Suite struct ImageGalleryTests {
    let files = [
        FileInfo(id: "a", name: "a.png", extension: "png"),
        FileInfo(id: "doc", name: "doc.pdf", extension: "pdf"),
        FileInfo(id: "b", name: "b.jpg", extension: "jpg"),
        FileInfo(id: "svg", name: "logo.svg", extension: "svg", mimeType: "image/svg+xml"),
        FileInfo(id: "c", name: "c.gif", extension: "gif"),
    ]

    @Test func keepsOnlyRasterImages() {
        #expect(ImageGallery.images(files).map(\.id) == ["a", "b", "c"])
    }

    @Test func normalizesToTheSelectedFile() {
        let images = ImageGallery.images(files)
        #expect(ImageGallery.normalized(images, selecting: images[1]).map(\.id) == ["a", "b", "c"])
        #expect(ImageGallery.normalized(images, selecting: files[1]).map(\.id) == ["doc"])
        #expect(ImageGallery.normalized([], selecting: images[0]).map(\.id) == ["a"])
        #expect(ImageGallery.index(of: images[2], in: images) == 2)
        #expect(ImageGallery.index(of: files[1], in: images) == 0)
    }

    @Test func navigationStaysInsideTheGallery() {
        #expect(ImageGallery.index(from: 0, offset: 1, count: 3) == 1)
        #expect(ImageGallery.index(from: 2, offset: 1, count: 3) == nil)
        #expect(ImageGallery.index(from: 0, offset: -1, count: 3) == nil)
        #expect(ImageGallery.index(from: 1, offset: 0, count: 3) == nil)
        #expect(ImageGallery.index(from: 0, offset: 1, count: 1) == nil)
    }

    @Test func positionIsShownForMultipleImages() {
        #expect(ImageGallery.position(index: 1, count: 3) == "2 of 3")
        #expect(ImageGallery.position(index: 0, count: 1) == nil)
    }
}

@Suite struct ImageViewerKeyTests {
    func action(_ characters: String, _ keyCode: UInt16 = 0, _ modifiers: NSEvent.ModifierFlags = []) -> ImageViewerAction? {
        ImageViewerKey.action(keyCode: keyCode, characters: characters, modifiers: modifiers)
    }

    @Test func plainKeys() {
        #expect(action("\u{1b}", ImageViewerKey.escape) == .close)
        #expect(action("", ImageViewerKey.leftArrow, [.numericPad, .function]) == .navigate(-1))
        #expect(action("", ImageViewerKey.rightArrow) == .navigate(1))
        #expect(action("a", 0) == nil)
        #expect(action("", ImageViewerKey.rightArrow, .option) == nil)
    }

    @Test func commandShortcuts() {
        #expect(action("w", 13, .command) == .close)
        #expect(action("=", 24, .command) == .zoom(.zoomIn))
        #expect(action("+", 24, [.command, .shift]) == .zoom(.zoomIn))
        #expect(action("-", 27, .command) == .zoom(.zoomOut))
        #expect(action("0", 29, .command) == .zoom(.fit))
        #expect(action("1", 18, .command) == .zoom(.actualSize))
        #expect(action("c", 8, .command) == .copy)
        #expect(action("s", 1, .command) == .download)
        #expect(action("c", 8, [.command, .shift]) == nil)
        #expect(action("w", 13, [.command, .option]) == nil)
        #expect(action("k", 40, .command) == nil)
    }
}

@Suite struct ImageViewerFormatTests {
    @Test func detailsCombineSizeAndDimensions() {
        let file = FileInfo(id: "f", name: "a.png", size: 2048)
        #expect(ImageViewerFormat.details(file: file, pixelSize: CGSize(width: 640, height: 480)) == "2 KB · 640 × 480")
        #expect(ImageViewerFormat.details(file: file, pixelSize: .zero) == "2 KB")
        #expect(ImageViewerFormat.details(file: FileInfo(id: "f", name: "a.png"), pixelSize: CGSize(width: 1, height: 2)) == "1 × 2")
        #expect(ImageViewerFormat.dimensions(.zero) == nil)
    }
}
