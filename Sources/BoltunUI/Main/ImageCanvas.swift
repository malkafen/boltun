import AppKit
import SwiftUI

@MainActor
protocol ImageCanvasControl: AnyObject {
    func show(_ content: ImageViewerContent?)
    func perform(_ command: ImageZoomCommand)
}

final class ImageCanvasClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        let rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        return ImageCanvasGeometry.centered(bounds: rect, document: document.frame.size)
    }
}

final class ImageDocumentView: NSImageView {
    var onDoubleClick: (NSPoint) -> Void = { _ in }
    var onPan: (CGSize) -> Void = { _ in }
    var onPanning: (Bool) -> Void = { _ in }

    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick(convert(event.locationInWindow, from: nil))
        } else {
            onPanning(true)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        onPan(CGSize(width: event.deltaX, height: event.deltaY))
    }

    override func mouseUp(with event: NSEvent) {
        onPanning(false)
    }
}

final class ImageScrollView: NSScrollView, ImageCanvasControl {
    let imageView = ImageDocumentView()
    var onZoomChange: (ImageZoomState) -> Void = { _ in }
    private(set) var fit: CGFloat = 1
    private(set) var isFitting = true
    private var fileId: String?
    private var reported: ImageZoomState?
    private(set) var isPanning = false

    var zoomState: ImageZoomState { ImageZoomState(magnification: magnification, fit: fit, isFitting: isFitting) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    private func configure() {
        contentView = ImageCanvasClipView()
        drawsBackground = true
        backgroundColor = Theme.windowBackground
        contentView.drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        usesPredominantAxisScrolling = false
        allowsMagnification = true
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageFrameStyle = .none
        imageView.isEditable = false
        imageView.allowsCutCopyPaste = false
        imageView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        documentView = imageView
        imageView.onDoubleClick = { [weak self] point in self?.toggle(at: point) }
        imageView.onPan = { [weak self] delta in self?.pan(by: delta) }
        imageView.onPanning = { [weak self] active in self?.setPanning(active) }
        contentView.postsBoundsChangedNotifications = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(boundsDidChange), name: NSView.boundsDidChangeNotification, object: contentView)
        center.addObserver(self, selector: #selector(willStartLiveMagnify), name: NSScrollView.willStartLiveMagnifyNotification, object: self)
        center.addObserver(self, selector: #selector(didEndLiveMagnify), name: NSScrollView.didEndLiveMagnifyNotification, object: self)
    }

    func show(_ content: ImageViewerContent?) {
        guard let content else {
            imageView.image = nil
            imageView.animates = false
            fileId = nil
            return
        }
        if imageView.image !== content.image { imageView.image = content.image }
        imageView.animates = content.animates
        let fileChanged = fileId != content.fileId
        let sizeChanged = imageView.frame.size != content.documentSize
        fileId = content.fileId
        if sizeChanged { imageView.frame = CGRect(origin: .zero, size: content.documentSize) }
        if fileChanged { isFitting = true }
        if fileChanged || sizeChanged { refit() }
    }

    func perform(_ command: ImageZoomCommand) {
        apply(ImageZoom.target(for: command, state: zoomState), at: nil)
    }

    func apply(_ target: ImageZoomTarget, at point: NSPoint?) {
        switch target {
        case .fit:
            isFitting = true
            setMagnification(fit, centeredAt: documentCenter)
        case .scale(let value):
            let clamped = ImageZoom.clamp(value, to: ImageZoom.limits(fit: fit))
            isFitting = ImageZoom.isFit(clamped, fit: fit)
            setMagnification(clamped, centeredAt: point ?? visibleCenter)
        }
        report()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refit()
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.scrollWheel(with: event)
            return
        }
        guard event.scrollingDeltaY != 0 else { return }
        let point = contentView.convert(event.locationInWindow, from: nil)
        let target = ImageZoom.scrolled(from: magnification, delta: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas, limits: ImageZoom.limits(fit: fit))
        apply(.scale(target), at: point)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { toggle(at: nil) } else { super.mouseDown(with: event) }
    }

    func toggle(at point: NSPoint?) {
        apply(ImageZoom.target(for: .toggle, state: zoomState), at: point)
    }

    func pan(by delta: CGSize) {
        let origin = ImageCanvasGeometry.panned(origin: contentView.bounds.origin, delta: delta, magnification: magnification, flipped: imageView.isFlipped)
        let constrained = contentView.constrainBoundsRect(NSRect(origin: origin, size: contentView.bounds.size))
        contentView.scroll(to: constrained.origin)
        reflectScrolledClipView(contentView)
    }

    private func setPanning(_ active: Bool) {
        if active, !isPanning, canPan {
            isPanning = true
            NSCursor.closedHand.push()
        } else if !active, isPanning {
            isPanning = false
            NSCursor.pop()
        }
    }

    private var canPan: Bool {
        ImageCanvasGeometry.canPan(document: imageView.frame.size, magnification: magnification, viewport: bounds.size)
    }

    private var documentCenter: NSPoint {
        NSPoint(x: imageView.frame.midX, y: imageView.frame.midY)
    }

    private var visibleCenter: NSPoint {
        NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
    }

    private func refit() {
        fit = ImageZoom.fit(document: imageView.frame.size, viewport: bounds.size)
        let limits = ImageZoom.limits(fit: fit)
        minMagnification = limits.lowerBound
        maxMagnification = limits.upperBound
        if isFitting { setMagnification(fit, centeredAt: documentCenter) }
        let constrained = contentView.constrainBoundsRect(contentView.bounds)
        if constrained.origin != contentView.bounds.origin { contentView.setBoundsOrigin(constrained.origin) }
        report()
    }

    private func report() {
        documentCursor = canPan ? .openHand : nil
        let state = zoomState
        guard state != reported else { return }
        reported = state
        onZoomChange(state)
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        report()
    }

    @objc private func willStartLiveMagnify(_ notification: Notification) {
        isFitting = false
    }

    @objc private func didEndLiveMagnify(_ notification: Notification) {
        isFitting = ImageZoom.isFit(magnification, fit: fit)
        report()
    }
}

struct ImageCanvas: NSViewRepresentable {
    let model: ImageViewerModel

    func makeNSView(context: Context) -> ImageScrollView {
        let view = ImageScrollView(frame: .zero)
        view.onZoomChange = { [weak model] state in model?.zoomChanged(state) }
        model.attach(view)
        return view
    }

    func updateNSView(_ view: ImageScrollView, context: Context) {}

    static func dismantleNSView(_ view: ImageScrollView, coordinator: ()) {
        view.show(nil)
        view.onZoomChange = { _ in }
    }
}
