import AppKit
import Foundation
import SwiftUI
import Testing
@testable import BoltunKit
@testable import BoltunUI

@MainActor
struct NotificationSettingsTests {
    static let patched = #"{"id":"me","username":"boltun","first_name":"Bolt","update_at":5,"notify_props":{"desktop":"all","mention_keys":"deploy,boltun","first_name":"true","channel":"false","desktop_threads":"mention"}}"#

    init() {
        _ = NSApplication.shared
    }

    func connected(_ servers: [ServerConfig] = [Harness.server()]) async -> Harness {
        let harness = await Harness.connected(servers)
        harness.transport.set("PUT users/me/patch", Self.patched)
        return harness
    }

    func sentProps(_ harness: Harness) throws -> [String: String] {
        let request = try #require(harness.transport.requests(matching: "PUT users/me/patch").last)
        let httpBody = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
        return try #require(body["notify_props"] as? [String: String])
    }

    @Test func startsFromTheSelectedServerAccount() async {
        let harness = await connected()
        let viewModel = NotificationSettingsViewModel(model: harness.model)
        #expect(viewModel.serverId == harness.model.servers[0].id)
        #expect(viewModel.isAvailable)
        #expect(viewModel.settings == AccountNotifySettings())
        #expect(viewModel.username == "boltun")
        #expect(viewModel.firstName.isEmpty)
        #expect(viewModel.keywordsText.isEmpty)
        #expect(!viewModel.hasChanges)
        #expect(viewModel.serverName == "Alpha")
    }

    @Test func savingPatchesTheAccountAndAdoptsTheResult() async throws {
        let harness = await connected()
        let viewModel = NotificationSettingsViewModel(model: harness.model)
        viewModel.settings.desktop = .all
        viewModel.settings.username = true
        viewModel.keywordsText = "deploy, "
        #expect(viewModel.hasChanges)
        #expect(viewModel.edited.keywords == ["deploy"])
        #expect(await viewModel.save())
        let props = try sentProps(harness)
        #expect(props["desktop"] == "all")
        #expect(props["mention_keys"] == "deploy,boltun")
        #expect(props["channel"] == "true")
        #expect(viewModel.original?.desktop == .all)
        #expect(viewModel.keywordsText == "deploy")
        #expect(!viewModel.hasChanges)
        #expect(viewModel.firstName == "Bolt")
        #expect(viewModel.errorMessage == nil)
        #expect(await viewModel.save())
        #expect(harness.transport.requests(matching: "PUT users/me/patch").count == 1)
    }

    @Test func failedSavesKeepTheEditsAndShowTheError() async {
        let harness = await connected()
        harness.transport.set("PUT users/me/patch", status: 500, #"{"id":"e","message":"server said no","status_code":500}"#)
        let viewModel = NotificationSettingsViewModel(model: harness.model)
        viewModel.settings.desktop = .none
        #expect(!(await viewModel.save()))
        #expect(viewModel.errorMessage == "server said no")
        #expect(viewModel.hasChanges)
        #expect(harness.model.selectedSession?.accountNotifySettings?.desktop == .mention)
        viewModel.revert()
        #expect(!viewModel.hasChanges)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.settings.desktop == .mention)
    }

    @Test func threadRepliesShowOnlyForMentionsWithCollapsedThreads() async {
        let harness = await connected()
        let viewModel = NotificationSettingsViewModel(model: harness.model)
        harness.model.selectedSession?.collapsedThreads = false
        #expect(!viewModel.showsThreadReplies)
        harness.model.selectedSession?.collapsedThreads = true
        #expect(viewModel.showsThreadReplies)
        viewModel.settings.desktop = .all
        #expect(!viewModel.showsThreadReplies)
    }

    @Test func signedOutServersExplainWhyNothingIsEditable() async {
        let empty = NotificationSettingsViewModel(model: Harness().model)
        #expect(empty.serverId == nil)
        #expect(!empty.isAvailable)
        #expect(empty.unavailableMessage == "Add a server to change its notification settings.")
        #expect(!(await empty.save()))
        let signedOut = NotificationSettingsViewModel(model: Harness(servers: [Harness.server("Beta")]).model)
        #expect(!signedOut.isAvailable)
        #expect(signedOut.unavailableMessage == "Sign in to Beta to change its notification settings.")
        #expect(!signedOut.hasChanges)
    }

    @Test func switchingServersReloadsTheirAccount() async {
        let harness = await connected([Harness.server("Alpha", port: 1), Harness.server("Beta", port: 2)])
        let viewModel = NotificationSettingsViewModel(model: harness.model, serverId: harness.model.servers[1].id)
        #expect(viewModel.serverName == "Beta")
        viewModel.settings.desktop = .all
        harness.model.session(for: harness.model.servers[0].id)?.me?.notifyProps["desktop"] = "none"
        viewModel.serverId = harness.model.servers[0].id
        #expect(viewModel.serverName == "Alpha")
        #expect(viewModel.settings.desktop == .none)
        #expect(!viewModel.hasChanges)
        viewModel.serverId = harness.model.servers[0].id
        #expect(viewModel.settings.desktop == .none)
    }

    @Test func remoteChangesSyncOnlyWithoutLocalEdits() async {
        let harness = await connected()
        let session = harness.model.selectedSession!
        let viewModel = NotificationSettingsViewModel(model: harness.model)
        session.me?.notifyProps["desktop"] = "all"
        viewModel.syncIfUnchanged()
        #expect(viewModel.settings.desktop == .all)
        viewModel.keywordsText = "oncall"
        session.me?.notifyProps["desktop"] = "none"
        viewModel.syncIfUnchanged()
        #expect(viewModel.settings.desktop == .all)
        #expect(viewModel.keywordsText == "oncall")
    }

    @Test func labelsDescribeEveryTrigger() {
        #expect(AccountNotifyLabels.level(.all) == "All new messages")
        #expect(AccountNotifyLabels.level(.mention) == "Mentions, direct messages and keywords")
        #expect(AccountNotifyLabels.level(.default) == AccountNotifyLabels.level(.mention))
        #expect(AccountNotifyLabels.level(.none) == "Nothing")
        #expect(AccountNotifyLabels.firstName("Ada") == "Your first name “Ada”")
        #expect(AccountNotifyLabels.firstName("").contains("not set"))
        #expect(AccountNotifyLabels.username("ada") == "Your username “ada” without the @")
        #expect(AccountNotifyLabels.usernameFootnote("ada") == "@ada always notifies you.")
        #expect(AccountNotifyLabels.channelWide.contains("@channel"))
        #expect(AccountNotifyLabels.levelFootnote.contains("Muted"))
    }

    @Test func rendersTheNotificationsTab() async {
        let harness = await connected([Harness.server("Alpha", port: 1), Harness.server("Beta", port: 2)])
        harness.model.selectedSession?.collapsedThreads = true
        let viewModel = NotificationSettingsViewModel(model: harness.model)
        viewModel.keywordsText = "deploy, release"
        #expect(Render.png(NotificationSettingsView(viewModel: viewModel), size: CGSize(width: 600, height: 760), name: "settings-notifications") != nil)
        let single = NotificationSettingsViewModel(model: (await connected()).model)
        #expect(Render.png(NotificationSettingsView(viewModel: single), size: CGSize(width: 600, height: 700), name: "settings-notifications-single") != nil)
        let signedOut = NotificationSettingsViewModel(model: Harness(servers: [Harness.server("Beta")]).model)
        #expect(Render.png(NotificationSettingsView(viewModel: signedOut), size: CGSize(width: 600, height: 300), name: "settings-notifications-signed-out") != nil)
    }
}

@MainActor
struct AccountNotifyAutomationTests {
    func command(_ path: String) -> DebugCommand? {
        DebugCommand(url: URL(string: "boltun://debug/\(path)")!)
    }

    @Test func parsesAccountNotifyChanges() {
        #expect(command("account-notify") == nil)
        #expect(command("account-notify?desktop=loud") == nil)
        #expect(command("account-notify?desktop=default") == nil)
        #expect(command("account-notify?desktop=all") == .accountNotify(server: 0, .init(desktop: .all)))
        #expect(command("account-notify?server=1&threads=0&first=1&username=yes&channel=off&keywords=a,b") == .accountNotify(
            server: 1, .init(threads: false, firstName: true, username: true, channelWide: false, keywords: "a,b")
        ))
        #expect(command("account-notify?keywords=") == .accountNotify(server: 0, .init(keywords: "")))
    }

    @Test func changesApplyOnTopOfTheCurrentSettings() {
        let base = AccountNotifySettings(keywords: ["old"])
        let change = DebugCommand.AccountNotifyChange(desktop: NotificationLevel.none, threads: false, firstName: true, username: true, channelWide: false, keywords: "a, b")
        #expect(change.applied(to: base) == AccountNotifySettings(desktop: .none, threadReplies: false, firstName: true, username: true, channelWide: false, keywords: ["a", "b"]))
        #expect(DebugCommand.AccountNotifyChange().applied(to: base) == base)
    }

    @Test func appliesAccountSettingsAndReportsThemInState() async throws {
        let harness = await Harness.connected()
        harness.transport.set("PUT users/me/patch", NotificationSettingsTests.patched)
        let sink = LogSink()
        let automation = DebugAutomation(router: AppRouter(model: harness.model), host: FakeAutomationHost(), isEnabled: { true }) { sink.lines.append($0) }
        await automation.handle(URL(string: "boltun://debug/account-notify?desktop=all&keywords=deploy")!)
        #expect(sink.lines.last == "ok /account-notify desktop=all threads=false first=true username=true channel=false keywords=deploy")
        let path = "/tmp/boltun-tests-\(UUID().uuidString)-account.json"
        await automation.handle(URL(string: "boltun://debug/state?path=\(path)")!)
        let state = try JSONDecoder().decode(AutomationState.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        try? FileManager.default.removeItem(atPath: path)
        #expect(state.servers[0].notifications?.hasPrefix("desktop=all") == true)
        await automation.handle(URL(string: "boltun://debug/settings?tab=notifications")!)
        #expect(sink.lines.last == "ok /settings")
    }

    @Test func reportsAccountNotifyFailures() async {
        let harness = await Harness.connected()
        harness.transport.set("PUT users/me/patch", status: 500, #"{"id":"e","message":"server said no","status_code":500}"#)
        let sink = LogSink()
        let automation = DebugAutomation(router: AppRouter(model: harness.model), host: FakeAutomationHost(), isEnabled: { true }) { sink.lines.append($0) }
        await automation.handle(URL(string: "boltun://debug/account-notify?desktop=none")!)
        #expect(sink.lines.last == "error /account-notify server said no")
        await automation.handle(URL(string: "boltun://debug/account-notify?server=3&desktop=none")!)
        #expect(sink.lines.last?.hasPrefix("error /account-notify") == true)
        let signedOut = Harness(servers: [Harness.server()])
        let other = DebugAutomation(router: AppRouter(model: signedOut.model), host: FakeAutomationHost(), isEnabled: { true }) { sink.lines.append($0) }
        await other.handle(URL(string: "boltun://debug/account-notify?desktop=none")!)
        #expect(sink.lines.last == "error /account-notify not signed in")
    }
}
