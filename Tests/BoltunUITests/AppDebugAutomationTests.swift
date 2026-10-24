import AppKit
import BoltunKit
import Foundation
import SwiftUI
import Testing
@testable import BoltunUI

@MainActor
final class FakeAutomationHost: AutomationHost {
    var mainWindow: NSWindow?
    private(set) var shown = 0
    private(set) var terminated = 0
    private(set) var notifications: [(String, String)] = []

    func showMainWindow() { shown += 1 }
    func deliverTestNotification(title: String, body: String) async { notifications.append((title, body)) }
    func terminate() { terminated += 1 }
}

@MainActor
final class LogSink {
    var lines: [String] = []
}

@MainActor
struct AppDebugAutomationTests {
    func make(_ harness: Harness, enabled: Bool = true) -> (DebugAutomation, FakeAutomationHost, LogSink, AppRouter) {
        let host = FakeAutomationHost()
        let sink = LogSink()
        let router = AppRouter(model: harness.model)
        let automation = DebugAutomation(router: router, host: host, isEnabled: { enabled }) { sink.lines.append($0) }
        return (automation, host, sink, router)
    }

    func tempPath(_ name: String) -> String {
        "/tmp/boltun-tests-\(UUID().uuidString)-\(name)"
    }

    @Test func ignoresWhenDisabled() async {
        let (automation, host, sink, _) = make(Harness(), enabled: false)
        #expect(!(await automation.handle(URL(string: "boltun://debug/quit")!)))
        #expect(host.terminated == 0)
        #expect(sink.lines.isEmpty)
    }

    @Test func ignoresNonDebugURLs() async {
        let (automation, _, sink, _) = make(Harness())
        #expect(!(await automation.handle(URL(string: "mattermost://chat.example.com/team")!)))
        #expect(sink.lines.isEmpty)
    }

    @Test func logsInvalidCommands() async {
        let (automation, _, sink, _) = make(Harness())
        #expect(await automation.handle(URL(string: "boltun://debug/bogus")!))
        #expect(sink.lines == ["error /bogus invalid command"])
    }

    @Test func addsServerAndLogsIn() async {
        let harness = Harness()
        let (automation, _, sink, router) = make(harness)
        await automation.handle(URL(string: "boltun://debug/add-server?url=http://chat.example.com:8065")!)
        #expect(harness.model.servers.first?.name == "Test Site")
        #expect(harness.model.servers.first?.url == URL(string: "http://chat.example.com:8065"))
        let id = harness.model.servers[0].id
        router.presentLogin(serverId: id)
        await automation.handle(URL(string: "boltun://debug/login?server=0&user=boltun&password=pw")!)
        #expect(sink.lines.last == "ok /login connected")
        #expect(router.sheet == nil)
        #expect(harness.credentials.token(for: id) == "session-token")
        await automation.handle(URL(string: "boltun://debug/login?server=5&user=a&password=b")!)
        #expect(sink.lines.last == "error /login no server at index 5")
        await automation.handle(URL(string: "boltun://debug/logout?server=0")!)
        #expect(harness.model.needsLogin.contains(id))
    }

    @Test func selectsTeamAndChannel() async {
        let harness = await Harness.connected()
        let (automation, _, sink, _) = make(harness)
        await automation.handle(URL(string: "boltun://debug/select?server=0&team=team-two&channel=random")!)
        #expect(harness.model.selectedSession?.currentChannelId == "c4")
        await automation.handle(URL(string: "boltun://debug/select?server=0&team=team-two&channel=missing")!)
        #expect(sink.lines.last == "error /select could not open team-two/missing")
        await automation.handle(URL(string: "boltun://debug/select?server=0")!)
        #expect(sink.lines.last == "ok /select")
    }

    @Test func opensLinks() async {
        let harness = await Harness.connected([ServerConfig(name: "A", url: URL(string: "http://chat.example.com:8065")!)])
        let (automation, _, sink, _) = make(harness)
        await automation.handle(URL(string: "boltun://debug/open?url=mattermost%3A%2F%2Fchat.example.com%2Fteam-two%2Fchannels%2Frandom")!)
        #expect(sink.lines.last == "ok /open")
        await automation.handle(URL(string: "boltun://debug/open?url=mattermost%3A%2F%2Fother.example.com%2Fteam")!)
        #expect(sink.lines.last == "ok /open No server matches other.example.com")
    }

    @Test func dumpsState() async throws {
        let harness = await Harness.connected()
        let (automation, host, _, router) = make(harness)
        host.mainWindow = NSWindow(contentRect: .init(x: 0, y: 0, width: 10, height: 10), styleMask: [], backing: .buffered, defer: true)
        router.presentAddServer()
        let path = tempPath("state.json")
        await automation.handle(URL(string: "boltun://debug/state?path=\(path)")!)
        let state = try JSONDecoder().decode(AutomationState.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        try? FileManager.default.removeItem(atPath: path)
        #expect(state.servers.count == 1)
        #expect(state.servers[0].connection == "connected")
        #expect(state.servers[0].user == "boltun")
        #expect(state.servers[0].team == "team-one")
        #expect(state.servers[0].channel == "town-square")
        #expect(state.servers[0].channelDisplayName == "Town Square")
        #expect(state.servers[0].visiblePostCount == 2)
        #expect(state.servers[0].teams == ["team-one", "team-two"])
        #expect(state.servers[0].mentions == 1)
        #expect(state.selectedServer == 0)
        #expect(state.badge == "1")
        #expect(state.sheet == "add-server")
        #expect(!state.windowVisible)
    }

    @Test func describesConnections() {
        #expect(AutomationState.describe(.idle) == "idle")
        #expect(AutomationState.describe(.connecting) == "connecting")
        #expect(AutomationState.describe(.reconnecting) == "reconnecting")
        #expect(AutomationState.describe(.unauthorized) == "unauthorized")
        #expect(AutomationState.describe(.failed("x")) == "failed: x")
        #expect(DebugAutomation.connectionSummary(nil) == "none")
    }

    @Test func snapshotsWindows() async throws {
        _ = NSApplication.shared
        let harness = Harness()
        let (automation, host, sink, _) = make(harness)
        let controller = MainWindowController(rootView: Text("Hi").frame(width: 300, height: 200), autosaveName: nil)
        host.mainWindow = controller.window
        let path = tempPath("main.png")
        await automation.handle(URL(string: "boltun://debug/snapshot?path=\(path)")!)
        let image = NSImage(contentsOfFile: path)
        try? FileManager.default.removeItem(atPath: path)
        #expect(image != nil)
        #expect(sink.lines.last == "ok /snapshot \(path)")
        await automation.handle(URL(string: "boltun://debug/snapshot?path=\(path)&window=sheet")!)
        #expect(sink.lines.last == "error /snapshot no sheet window")
        await automation.handle(URL(string: "boltun://debug/snapshot?path=\(path)&window=settings")!)
        #expect(sink.lines.last == "error /snapshot no settings window")
        _ = try? automation.window(for: .key)
    }

    @Test func drivesUI() async {
        let server = Harness.server()
        let harness = Harness(servers: [server])
        let (automation, host, sink, router) = make(harness)
        var settingsOpened = 0
        router.openSettingsWindow = { settingsOpened += 1 }
        await automation.handle(URL(string: "boltun://debug/present?sheet=add-server")!)
        #expect(router.sheet == .addServer)
        await automation.handle(URL(string: "boltun://debug/present?sheet=login")!)
        #expect(router.sheet == .login(server.id))
        await automation.handle(URL(string: "boltun://debug/present?sheet=bogus")!)
        #expect(sink.lines.last == "error /present invalid command")
        await automation.handle(URL(string: "boltun://debug/dismiss")!)
        #expect(router.sheet == nil)
        await automation.handle(URL(string: "boltun://debug/settings?tab=general")!)
        #expect(router.settingsTab == .general)
        #expect(settingsOpened == 1)
        await automation.handle(URL(string: "boltun://debug/show")!)
        #expect(host.shown == 1)
        await automation.handle(URL(string: "boltun://debug/close")!)
        await automation.handle(URL(string: "boltun://debug/notify?title=T&body=B")!)
        #expect(host.notifications.first?.0 == "T")
        await automation.handle(URL(string: "boltun://debug/quit")!)
        #expect(host.terminated == 1)
    }

    @Test func refusesSymlinkTargets() throws {
        let target = tempPath("target")
        let link = tempPath("link.png")
        FileManager.default.createFile(atPath: target, contents: Data())
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        defer {
            try? FileManager.default.removeItem(atPath: link)
            try? FileManager.default.removeItem(atPath: target)
        }
        #expect(throws: CocoaError.self) { try Snapshot.write(Data([1]), to: link) }
    }

    @Test func appendsToLogFile() throws {
        DebugAutomation.appendToLog("test line \(UUID().uuidString)")
        let contents = try String(contentsOfFile: DebugAutomation.logPath, encoding: .utf8)
        #expect(contents.contains("test line"))
    }
}
