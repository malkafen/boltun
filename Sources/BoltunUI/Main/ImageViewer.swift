import AppKit
import BoltunKit
import SwiftUI

final class ImageViewerWindow: NSWindow {
    var onAction: (ImageViewerAction) -> Void = { _ in }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handle(event) || super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if handle(event) { return }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onAction(.close)
    }

    func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              let action = ImageViewerKey.action(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "", modifiers: event.modifierFlags)
        else { return false }
        onAction(action)
        return true
    }
}

@MainActor
final class ImageViewerWindowController: NSWindowController, NSWindowDelegate {
    static let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
    static let contentMinSize = NSSize(width: 360, height: 240)

    let model: ImageViewerModel
    var onClose: () -> Void = {}

    init(model: ImageViewerModel, screen: NSScreen?) {
        self.model = model
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: ImageViewerDisplay.fallback.size)
        let window = ImageViewerWindow(contentRect: CGRect(origin: .zero, size: Self.contentMinSize), styleMask: Self.styleMask, backing: .buffered, defer: false)
        Self.style(window, title: model.file.name)
        let host = NSHostingView(rootView: ImageViewerView(model: model))
        host.sizingOptions = []
        window.contentView = host
        window.setFrame(Self.frame(imageSize: model.pixelSize, visible: visible), display: false)
        super.init(window: window)
        window.delegate = self
        window.onAction = { [weak model] action in model?.perform(action) }
        model.onClose = { [weak window] in window?.performClose(nil) }
        model.onPixelSizeResolved = { [weak self] size in self?.resize(toFit: size) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    static func style(_ window: NSWindow, title: String) {
        window.title = title
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Theme.sidebarHeader)
        window.contentMinSize = contentMinSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.identifier = NSUserInterfaceItemIdentifier("image-viewer")
    }

    static var titlebarHeight: CGFloat {
        let probe = CGRect(x: 0, y: 0, width: 100, height: 100)
        return NSWindow.frameRect(forContentRect: probe, styleMask: styleMask).height - probe.height
    }

    static func frame(imageSize: CGSize, visible: CGRect) -> CGRect {
        let titlebar = titlebarHeight
        let available = ImageViewerLayout.available(visible: visible.size, titlebar: titlebar)
        let content = ImageViewerLayout.contentSize(image: imageSize, available: available)
        return ImageViewerLayout.centered(size: CGSize(width: content.width, height: content.height + titlebar), in: visible)
    }

    func present() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    func resize(toFit size: CGSize) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let visible = window.screen?.visibleFrame ?? CGRect(origin: .zero, size: ImageViewerDisplay.fallback.size)
        window.setFrame(Self.frame(imageSize: size, visible: visible), display: true, animate: window.isVisible)
    }

    func windowWillClose(_ notification: Notification) {
        model.release()
        onClose()
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        model.displayChanged(.of(window?.screen))
    }

    func windowDidChangeScreen(_ notification: Notification) {
        model.displayChanged(.of(window?.screen))
    }
}

@MainActor
final class ImageViewerPresenter {
    static let shared = ImageViewerPresenter()

    private(set) var controller: ImageViewerWindowController?
    var screen: () -> NSScreen? = { NSApplication.shared.keyWindow?.screen ?? NSApplication.shared.mainWindow?.screen ?? NSScreen.main }

    var window: NSWindow? { controller?.window }
    var model: ImageViewerModel? { controller?.model }

    func model(for workspace: Workspace) -> ImageViewerModel? {
        controller.flatMap { $0.model.workspace === workspace ? $0.model : nil }
    }

    func sync(_ workspace: Workspace) {
        guard let file = workspace.previewFile else {
            close(for: workspace)
            return
        }
        if let model = model(for: workspace) {
            let reopened = model.file.id != file.id
            model.show(file, gallery: workspace.previewGallery)
            if reopened {
                controller?.resize(toFit: model.pixelSize)
                controller?.present()
            }
            return
        }
        controller?.close()
        let screen = screen()
        let model = ImageViewerModel(workspace: workspace, file: file, gallery: workspace.previewGallery, display: .of(screen))
        let controller = ImageViewerWindowController(model: model, screen: screen)
        controller.onClose = { [weak self, weak controller] in self?.didClose(controller) }
        self.controller = controller
        model.start()
        controller.present()
    }

    func close(for workspace: Workspace) {
        guard model(for: workspace) != nil else { return }
        controller?.close()
    }

    private func didClose(_ closed: ImageViewerWindowController?) {
        guard let closed, closed === controller else { return }
        controller = nil
        let workspace = closed.model.workspace
        if workspace.previewFile != nil { workspace.previewFile = nil }
        workspace.previewGallery = []
    }
}

struct ImageViewerView: View {
    let model: ImageViewerModel

    var body: some View {
        VStack(spacing: 0) {
            ImageViewerHeader(model: model)
            ZStack {
                ImageCanvas(model: model)
                if model.content == nil { ImageViewerStatus(model: model) }
            }
        }
        .background(Theme.content)
        .background { WindowTitleSetter(title: model.file.name).frame(width: 0, height: 0) }
        .preferredColorScheme(.dark)
    }
}

struct ImageViewerStatus: View {
    let model: ImageViewerModel

    var body: some View {
        if let failure = model.failure {
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.exclamationmark").font(.system(size: 34)).foregroundStyle(Theme.textSecondary)
                Text(failure).scaledFont(13).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
            .padding(24)
        } else {
            ProgressView()
        }
    }
}

struct ImageViewerHeader: View {
    let model: ImageViewerModel
    @State private var opening = false

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.file.name)
                    .scaledFont(13.5, weight: .semibold)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(model.details).foregroundStyle(Theme.textSecondary)
                    if model.content != nil, let failure = model.failure {
                        Text(failure).foregroundStyle(Theme.error)
                    }
                }
                .scaledFont(11.5)
                .lineLimit(1)
            }
            .layoutPriority(1)
            if model.isLoading {
                ProgressView().controlSize(.small).padding(.leading, 6).help("Loading full resolution")
            }
            Spacer(minLength: 12)
            if let position = model.position {
                ImageViewerButton(systemName: "chevron.left", help: "Previous Image (←)", enabled: model.canGoBack) { model.navigate(-1) }
                Text(position)
                    .scaledFont(11.5)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize()
                ImageViewerButton(systemName: "chevron.right", help: "Next Image (→)", enabled: model.canGoForward) { model.navigate(1) }
                ImageViewerDivider()
            }
            ImageViewerButton(systemName: "minus.magnifyingglass", help: "Zoom Out (⌘−)", enabled: model.zoom.canZoomOut) { model.zoom(.zoomOut) }
            Button { model.zoom(.toggle) } label: {
                Text(model.zoom.percent)
                    .scaledFont(11.5, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.zoom.isFitting ? "Actual Size (⌘1)" : "Zoom to Fit (⌘0)")
            ImageViewerButton(systemName: "plus.magnifyingglass", help: "Zoom In (⌘+)", enabled: model.zoom.canZoomIn) { model.zoom(.zoomIn) }
            ImageViewerButton(systemName: "arrow.up.left.and.down.right.magnifyingglass", help: "Zoom to Fit (⌘0)", enabled: !model.zoom.isFitting) { model.zoom(.fit) }
            ImageViewerDivider()
            ImageViewerButton(systemName: "doc.on.doc", help: "Copy Image (⌘C)", enabled: model.canCopy) { model.copy() }
            ImageViewerButton(systemName: "arrow.up.forward.app", help: "Open in Default App", enabled: !opening) { open() }
            ImageViewerButton(systemName: "arrow.down.circle", help: "Download (⌘S)", enabled: !model.isDownloading) { model.download() }
            ImageViewerButton(systemName: "xmark", help: "Close (Esc)") { model.perform(.close) }
        }
        .padding(.horizontal, 12)
        .frame(height: ImageViewerLayout.headerHeight)
        .background(Theme.sidebarHeader)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
    }

    private func open() {
        opening = true
        Task {
            await model.openInDefaultApp()
            opening = false
        }
    }
}

struct ImageViewerButton: View {
    let systemName: String
    let help: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        IconButton(systemName: systemName, help: help, action: action)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.35)
    }
}

struct ImageViewerDivider: View {
    var body: some View {
        Rectangle().fill(Theme.separator).frame(width: 1, height: 18).padding(.horizontal, 4)
    }
}
