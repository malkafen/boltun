import AppKit
import SwiftUI

@MainActor
public final class MainWindowController: NSWindowController, NSWindowDelegate {
    public static let autosaveName = "BoltunMainWindow"
    public static let minimumSize = NSSize(width: 900, height: 600)
    public static let defaultSize = NSSize(width: 1240, height: 820)
    var onBecomeKey: () -> Void = {}

    public init<Content: View>(rootView: Content, autosaveName: String? = MainWindowController.autosaveName) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        Self.style(window)
        let host = NSHostingView(rootView: rootView)
        host.sizingOptions = []
        window.contentView = host
        super.init(window: window)
        window.delegate = self
        if let autosaveName, !window.setFrameUsingName(autosaveName) { window.center() }
        if let autosaveName { window.setFrameAutosaveName(autosaveName) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    static func style(_ window: NSWindow) {
        window.title = "Boltun"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.windowBackground
        window.contentMinSize = minimumSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isMovableByWindowBackground = false
    }

    public var isWindowVisible: Bool { window?.isVisible ?? false }

    public func present() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        onBecomeKey()
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender.styleMask.contains(.fullScreen) {
            NSApp.hide(nil)
        } else {
            sender.orderOut(nil)
        }
        return false
    }
}
