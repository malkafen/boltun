import AppKit
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public lazy var environment = AppEnvironment.live()

    public func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSWindow.allowsAutomaticWindowTabbing = false
        installURLHandler()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        installURLHandler()
        environment.launch()
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        environment.appDidBecomeActive()
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment.showMainWindow()
        return false
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        environment.shutdown()
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { open(url) }
    }

    func installURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: value) else { return }
        open(url)
    }

    func open(_ url: URL) {
        let environment = self.environment
        Task { await environment.handle(url: url) }
    }
}
