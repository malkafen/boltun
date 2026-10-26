import AppKit
import BoltunKit
import Foundation
import SwiftUI
import Testing
@testable import BoltunUI

@MainActor
struct SettingsTests {
    init() {
        _ = NSApplication.shared
    }

    @Test func tabsHaveTitlesAndIcons() {
        #expect(SettingsTab.allCases.map(\.title) == ["Servers", "General", "Notifications", "About"])
        #expect(Set(SettingsTab.allCases.map(\.systemImage)).count == 4)
    }

    @Test func togglesLaunchAtLogin() {
        let harness = Harness()
        let loginItem = FakeLoginItem()
        let viewModel = GeneralSettingsViewModel(model: harness.model, loginItem: loginItem)
        viewModel.launchAtLogin = true
        #expect(viewModel.launchAtLogin)
        #expect(loginItem.calls == [true])
        #expect(harness.store.load().settings.launchAtLogin)
        loginItem.failure = TestFailure()
        viewModel.launchAtLogin = false
        #expect(viewModel.launchAtLogin)
        #expect(viewModel.loginItemError == "Could not update the login item: boom")
        loginItem.failure = nil
        viewModel.launchAtLogin = false
        #expect(!viewModel.launchAtLogin)
        #expect(viewModel.loginItemError == nil)
    }

    @Test func managesDownloadLocation() {
        let harness = Harness()
        let viewModel = GeneralSettingsViewModel(model: harness.model, loginItem: FakeLoginItem())
        #expect(viewModel.downloadURL == GeneralSettingsViewModel.defaultDownloadsURL)
        viewModel.setDownloadLocation(URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Files"))
        #expect(viewModel.downloadLocationDisplay == "~/Files")
        #expect(harness.model.settings.downloadLocation == NSHomeDirectory() + "/Files")
        viewModel.setDownloadLocation(nil)
        #expect(harness.model.settings.downloadLocation == nil)
    }

    @Test func systemLoginItemReportsStatus() {
        _ = SystemLoginItem().isEnabled
    }

    @Test func editsServerName() async {
        let server = Harness.server()
        let harness = Harness(servers: [server], tokens: [server.id: "token"])
        let viewModel = EditServerViewModel(model: harness.model, server: server)
        #expect(!viewModel.urlChanged)
        viewModel.name = "  "
        #expect(!viewModel.canSave)
        #expect(!(await viewModel.save()))
        viewModel.name = " Renamed "
        #expect(await viewModel.save())
        #expect(harness.model.servers[0].name == "Renamed")
        #expect(harness.credentials.token(for: server.id) == "token")
    }

    @Test func editsServerURL() async {
        let server = Harness.server()
        let other = ServerConfig(name: "Other", url: URL(string: "http://other.example.com")!)
        let transport = FakeTransport()
        let harness = Harness(servers: [server, other], tokens: [server.id: "token"], transport: transport)
        let viewModel = EditServerViewModel(model: harness.model, server: server)
        viewModel.urlText = "http://other.example.com/"
        #expect(viewModel.urlChanged)
        #expect(!(await viewModel.save()))
        #expect(viewModel.errorMessage == "Another server already uses this URL.")
        viewModel.urlText = "ftp://nope"
        #expect(!(await viewModel.save()))
        #expect(viewModel.errorMessage?.contains("valid server URL") == true)
        viewModel.urlText = "http://new.example.com"
        #expect(await viewModel.save())
        #expect(harness.model.servers[0].url == URL(string: "http://new.example.com"))
        #expect(harness.credentials.token(for: server.id) == nil)
        #expect(harness.model.needsLogin.contains(server.id))
    }

    @Test func describesServerStatus() async {
        let signedOut = Harness.server("A", port: 1)
        let connected = Harness.server("B", port: 2)
        let harness = await Harness.connected([connected])
        harness.model.addServer(name: "A", url: signedOut.url)
        let addedId = harness.model.servers[1].id
        #expect(ServerStatus(model: harness.model, serverId: connected.id).kind == .connected)
        #expect(ServerStatus(model: harness.model, serverId: addedId).kind == .signedOut)
        #expect(ServerStatus(model: harness.model, serverId: UUID()).kind == .offline)
        let kinds: [ServerStatus.Kind] = [.connected, .connecting, .signedOut, .offline, .error("Timed out")]
        #expect(kinds.map { ServerStatus(kind: $0).label } == ["Connected", "Connecting…", "Signed out", "Not connected", "Timed out"])
        #expect(Set(kinds.map { ServerStatus(kind: $0).color.description }).count >= 3)
        let session = harness.model.session(for: connected.id)!
        session.connection = .reconnecting
        #expect(ServerStatus(model: harness.model, serverId: connected.id).kind == .connecting)
        session.connection = .failed("Down")
        #expect(ServerStatus(model: harness.model, serverId: connected.id).kind == .error("Down"))
        session.connection = .unauthorized
        #expect(ServerStatus(model: harness.model, serverId: connected.id).kind == .signedOut)
        session.connection = .idle
        #expect(ServerStatus(model: harness.model, serverId: connected.id).kind == .offline)
    }

    @Test func rendersSettingsTabs() async {
        let harness = await Harness.connected([Harness.server("Alpha", port: 1), Harness.server("Beta", port: 2)])
        let router = AppRouter(model: harness.model)
        let loginItem = FakeLoginItem()
        for tab in SettingsTab.allCases {
            router.settingsTab = tab
            #expect(Render.png(SettingsView(model: harness.model, router: router, loginItem: loginItem), size: CGSize(width: 600, height: 560), name: "settings-\(tab.rawValue)") != nil)
        }
    }

    @Test func rendersServerList() async {
        let harness = await Harness.connected([Harness.server("Alpha", port: 1)])
        harness.model.addServer(name: "Signed Out", url: URL(string: "https://b.example.com")!)
        #expect(Render.png(ServersSettingsView(model: harness.model, selection: harness.model.servers[0].id), size: CGSize(width: 600, height: 420), name: "settings-servers-selected") != nil)
        #expect(Render.png(ServersSettingsView(model: harness.model, selection: harness.model.servers[1].id), size: CGSize(width: 600, height: 420), name: "settings-servers-signed-out") != nil)
        #expect(Render.png(ServersSettingsView(model: Harness().model), size: CGSize(width: 600, height: 420), name: "settings-servers-empty") != nil)
        #expect(Render.png(ServerRow(server: harness.model.servers[0], status: ServerStatus(kind: .error("Timed out"))), size: CGSize(width: 500, height: 44), name: "settings-row") != nil)
    }

    @Test func rendersGeneralAboutAndEdit() {
        let server = Harness.server()
        let harness = Harness(servers: [server])
        let viewModel = GeneralSettingsViewModel(model: harness.model, loginItem: FakeLoginItem())
        harness.model.settings.notificationsEnabled = false
        #expect(Render.png(GeneralSettingsView(viewModel: viewModel), size: CGSize(width: 600, height: 700), name: "settings-general-full") != nil)
        var opened: [URL] = []
        #expect(Render.png(AboutSettingsView(info: AppInfo(shortVersion: "1.0.0", fullVersion: "1.0.0-3-gabc", build: "3")) { opened.append($0) }, size: CGSize(width: 600, height: 440), name: "settings-about-info") != nil)
        let edit = EditServerViewModel(model: harness.model, server: server)
        edit.urlText = "https://changed.example.com"
        #expect(Render.png(EditServerView(viewModel: edit) {}, size: CGSize(width: 400, height: 360), name: "settings-edit") != nil)
    }
}
