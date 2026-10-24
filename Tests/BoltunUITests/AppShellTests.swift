import AppKit
import BoltunKit
import Foundation
import SwiftUI
import Testing
@testable import BoltunUI

@MainActor
struct AppShellTests {
    init() {
        _ = NSApplication.shared
    }

    @Test func appBuilds() {
        _ = BoltunApp()
    }

    @Test func menuBarBindingAvoidsRedundantWrites() {
        let harness = Harness()
        let binding = BoltunApp.menuBarBinding(harness.model)
        #expect(!binding.wrappedValue)
        binding.wrappedValue = false
        binding.wrappedValue = true
        #expect(harness.model.settings.showMenuBarIcon)
        #expect(harness.store.load().settings.showMenuBarIcon)
    }

    @Test func readsAppInfo() {
        let info = AppInfo(infoDictionary: ["CFBundleShortVersionString": "1.2.0", "BoltunFullVersion": "1.2.0-5-gabc", "CFBundleVersion": "42", "CFBundleName": "Boltun"])
        #expect(info.versionDescription == "Version 1.2.0 (1.2.0-5-gabc, build 42)")
        let plain = AppInfo(infoDictionary: ["CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "7"])
        #expect(plain.fullVersion == "1.0.0")
        #expect(plain.versionDescription == "Version 1.0.0 (build 7)")
        let empty = AppInfo(infoDictionary: nil)
        #expect(empty.shortVersion == "0.0.0")
        #expect(empty.name == "Boltun")
        _ = AppInfo.current
    }

    @Test func selectsCredentialStore() {
        let defaults = UserDefaults(suiteName: "boltun-tests-\(UUID().uuidString)")!
        #expect(AppEnvironment.credentialStore(defaults: defaults) is KeychainCredentialStore)
        defaults.set(true, forKey: DebugCommand.defaultsKey)
        #expect(AppEnvironment.credentialStore(defaults: defaults) is FileCredentialStore)
    }

    @Test func fileCredentialStorePersistsTokens() throws {
        let url = URL(fileURLWithPath: "/tmp/boltun-tests-\(UUID().uuidString)/credentials.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FileCredentialStore(fileURL: url)
        let id = UUID()
        #expect(store.token(for: id) == nil)
        try store.setToken("abc", for: id)
        #expect(FileCredentialStore(fileURL: url).token(for: id) == "abc")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        store.removeToken(for: UUID())
        store.removeToken(for: id)
        #expect(store.token(for: id) == nil)
        #expect(FileCredentialStore.defaultURL().lastPathComponent == "debug-credentials.json")
    }

    @Test func mainWindowHidesInsteadOfClosing() {
        let controller = MainWindowController(rootView: Text("Main"), autosaveName: nil)
        let window = controller.window!
        #expect(window.contentMinSize == MainWindowController.minimumSize)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titleVisibility == .hidden)
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(!window.isReleasedWhenClosed)
        window.orderFront(nil)
        #expect(controller.isWindowVisible)
        #expect(!controller.windowShouldClose(window))
        #expect(!controller.isWindowVisible)
        controller.present()
        #expect(controller.isWindowVisible)
        window.orderOut(nil)
    }

    @Test func mainWindowRestoresFrame() {
        let name = "BoltunTestWindow-\(UUID().uuidString)"
        let first = MainWindowController(rootView: Text("A"), autosaveName: name)
        first.window?.setFrame(NSRect(x: 40, y: 50, width: 1000, height: 700), display: false)
        first.window?.saveFrame(usingName: name)
        let second = MainWindowController(rootView: Text("B"), autosaveName: name)
        #expect(second.window?.frame.size == NSSize(width: 1000, height: 700))
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(name)")
    }

    @Test func environmentLaunchWiresServices() async {
        let harness = await Harness.connected()
        let dock = FakeDock()
        let center = SilentNotificationCenter()
        let loginItem = FakeLoginItem()
        loginItem.isEnabled = true
        var opened: [URL] = []
        let environment = harness.environment(center: center, dock: dock, loginItem: loginItem) { opened.append($0) }
        environment.launch(startSessions: false)
        environment.launch(startSessions: false)
        #expect(dock.badgeLabel == "1")
        #expect(harness.model.settings.launchAtLogin)
        #expect(environment.mainWindow?.isVisible == true)
        #expect(harness.model.onNotification != nil)
        #expect(!harness.model.isAppActive())
        dock.isAppActive = true
        #expect(harness.model.isAppActive())
        environment.router.showMainWindow()
        environment.router.openExternalURL(AppInfo.issuesURL)
        #expect(opened == [AppInfo.issuesURL])
        await harness.model.selectedSession?.selectChannel("c2")
        #expect(await eventually { center.removed.contains("c2") })
        await environment.deliverTestNotification(title: "T", body: "B")
        #expect(center.posted.last?.title == "T")
        await environment.handle(url: URL(string: "mattermost://chat.example.com:8065/team-two/channels/random")!)
        #expect(harness.model.selectedSession?.currentChannelId == "c4")
        await environment.handle(url: URL(string: "boltun://debug/bogus")!)
        environment.shutdown()
        #expect(harness.model.selectedSession?.connection == .idle)
        environment.mainWindow?.orderOut(nil)
    }

    @Test func environmentStartsSessionsOnLaunch() async {
        let server = Harness.server()
        let harness = Harness(servers: [server], tokens: [server.id: "token"])
        let environment = harness.environment()
        environment.launch()
        #expect(await eventually(timeout: .seconds(10)) { harness.model.session(for: server.id)?.connection == .connected })
        environment.mainWindow?.orderOut(nil)
    }

    @Test func testNotificationNeedsChannel() async {
        let harness = Harness()
        let center = SilentNotificationCenter()
        await harness.environment(center: center).deliverTestNotification(title: "T", body: "B")
        #expect(center.posted.isEmpty)
    }

    @Test func rendersRootStates() async {
        let empty = Harness()
        let router = AppRouter(model: empty.model)
        #expect(Render.png(AppRootView(model: empty.model, router: router), size: CGSize(width: 900, height: 600), name: "app-welcome") != nil)

        let signedOut = Harness(servers: [Harness.server()])
        await signedOut.model.startAll()
        let signedOutRouter = AppRouter(model: signedOut.model)
        #expect(Render.png(AppRootView(model: signedOut.model, router: signedOutRouter), size: CGSize(width: 900, height: 600), name: "app-signed-out") != nil)
        #expect(signedOutRouter.sheet == .login(signedOut.model.servers[0].id))

        let connected = await Harness.connected()
        let connectedRouter = AppRouter(model: connected.model)
        connectedRouter.presentAddServer()
        #expect(Render.png(AppRootView(model: connected.model, router: connectedRouter), size: CGSize(width: 900, height: 600), name: "app-main") != nil)
    }

    @Test func rendersWelcome() {
        #expect(Render.png(WelcomeView {}, size: CGSize(width: 900, height: 600), name: "login-welcome") != nil)
    }

    @Test func buildsCommandsAndStatusMenu() async {
        let harness = await Harness.connected([Harness.server("A", port: 1), Harness.server("B", port: 2)])
        let router = AppRouter(model: harness.model)
        let commands = AppCommands(router: router)
        _ = commands.body
        #expect(commands.signOutTitle == "Sign Out of A")
        #expect(AppCommands(router: AppRouter(model: Harness().model)).signOutTitle == "Sign Out")
        #expect(Render.png(StatusMenuContent(router: router), size: CGSize(width: 300, height: 300), name: "app-status-menu") != nil)
        let server = harness.model.servers[0]
        #expect(StatusMenuContent.title(server: server, unread: ChannelUnread(unread: true, mentions: 3)) == "A — 3 mentions")
        #expect(StatusMenuContent.title(server: server, unread: ChannelUnread(unread: true, mentions: 1)) == "A — 1 mention")
        #expect(StatusMenuContent.title(server: server, unread: ChannelUnread(unread: true)) == "A — unread")
        #expect(StatusMenuContent.title(server: server, unread: ChannelUnread()) == "A")
    }

    @Test func rendersFullWindowSnapshot() {
        let controller = MainWindowController(rootView: Color.red.frame(width: 400, height: 300), autosaveName: nil)
        controller.window?.setContentSize(NSSize(width: 960, height: 640))
        let data = controller.window.flatMap(Snapshot.png(of:))
        #expect(data != nil)
        let blank = NSView(frame: .zero)
        #expect(Snapshot.png(of: blank) == nil)
    }

    @Test func fontScaleEnvironmentDefaults() {
        let values = EnvironmentValues()
        #expect(values.fontScale == 1.0)
        #expect(values.appRouter == nil)
    }
}
