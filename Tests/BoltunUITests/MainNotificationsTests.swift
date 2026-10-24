import AppKit
import Foundation
import SwiftUI
import Testing
@testable import BoltunKit
@testable import BoltunUI

@MainActor
@Suite struct ChannelNotifyLabelTests {
    @Test func muteTitlesMatchTheChannelKind() {
        #expect(ChannelNotifyLabels.muteTitle(muted: false, isDirect: false) == "Mute Channel")
        #expect(ChannelNotifyLabels.muteTitle(muted: true, isDirect: false) == "Unmute Channel")
        #expect(ChannelNotifyLabels.muteTitle(muted: false, isDirect: true) == "Mute Conversation")
        #expect(ChannelNotifyLabels.muteTitle(muted: true, isDirect: true) == "Unmute Conversation")
        #expect(ChannelNotifyLabels.teamMuteTitle(muted: false) == "Mute Notifications")
        #expect(ChannelNotifyLabels.teamMuteTitle(muted: true) == "Unmute Notifications")
        #expect(ChannelNotifyLabels.muteDescription(isDirect: false).contains("channel"))
        #expect(ChannelNotifyLabels.muteDescription(isDirect: true).contains("conversation"))
    }

    @Test func levelTitlesNameTheInheritedDefault() {
        #expect(ChannelNotifyLabels.level(.default, fallback: .mention) == "Default (Mentions only)")
        #expect(ChannelNotifyLabels.level(.default, fallback: .all) == "Default (All new messages)")
        #expect(ChannelNotifyLabels.level(.default, fallback: .none) == "Default (Nothing)")
        #expect(ChannelNotifyLabels.level(.default, fallback: .default) == "Default (Mentions only)")
        #expect(ChannelNotifyLabels.level(.all, fallback: .mention) == "All new messages")
        #expect(ChannelNotifyLabels.level(.mention, fallback: .mention) == "Mentions, direct messages and keywords only")
        #expect(ChannelNotifyLabels.level(.none, fallback: .mention) == "Nothing")
    }
}

@MainActor
@Suite struct ChannelNotificationsModelTests {
    func workspace() -> Workspace {
        let transport = Fixture.transport()
        transport.on("PUT", "channels/*", json: #"{"status":"OK"}"#)
        return Fixture.workspace(transport: transport)
    }

    @Test func startsFromTheCurrentMemberProps() {
        let workspace = workspace()
        let model = ChannelNotificationsModel(workspace: workspace, channelId: "muted")
        #expect(model.settings.muted)
        #expect(model.muteTitle == "Unmute Channel")
        #expect(model.channelName == "Noise")
        #expect(!model.isDirect)
        #expect(!model.hasChanges)
        let direct = ChannelNotificationsModel(workspace: workspace, channelId: "dm-alice")
        #expect(direct.isDirect)
        #expect(direct.muteTitle == "Mute Conversation")
        #expect(direct.channelName == "alice")
    }

    @Test func unknownChannelsDegradeGracefully() {
        let model = ChannelNotificationsModel(workspace: workspace(), channelId: "ghost")
        #expect(model.channel == nil)
        #expect(model.channelName.isEmpty)
        #expect(!model.isDirect)
        #expect(model.settings == ChannelNotifySettings())
    }

    @Test func desktopFallbackComesFromTheUser() {
        let workspace = workspace()
        let model = ChannelNotificationsModel(workspace: workspace, channelId: "town")
        #expect(model.desktopFallback == .mention)
        #expect(model.desktopLevel == .mention)
        workspace.session.me?.notifyProps["desktop"] = "all"
        #expect(model.desktopFallback == .all)
        #expect(model.desktopLevel == .all)
        model.settings.desktop = .none
        #expect(model.desktopLevel == .none)
        #expect(model.desktopFallback == .all)
    }

    @Test func threadRepliesSectionFollowsCollapsedThreadsAndLevel() {
        let workspace = workspace()
        let model = ChannelNotificationsModel(workspace: workspace, channelId: "town")
        #expect(!model.showsThreadReplies)
        workspace.session.collapsedThreads = true
        #expect(model.showsThreadReplies)
        #expect(model.threadReplies)
        model.threadReplies = false
        #expect(model.settings.desktopThreads == .mention)
        #expect(!model.threadReplies)
        model.threadReplies = true
        #expect(model.settings.desktopThreads == .all)
        model.settings.desktop = .all
        #expect(!model.showsThreadReplies)
    }

    @Test func savingSendsOnlyTheEditedProps() async throws {
        let transport = Fixture.transport()
        transport.on("PUT", "channels/*", json: #"{"status":"OK"}"#)
        let workspace = Fixture.workspace(transport: transport)
        let model = ChannelNotificationsModel(workspace: workspace, channelId: "town")
        model.settings.muted = true
        model.settings.desktop = .none
        #expect(model.hasChanges)
        #expect(await model.save())
        let request = try #require(transport.requests("PUT", "channels/town/members/me/notify_props").last)
        let httpBody = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: httpBody) as? [String: String])
        #expect(body == ["mark_unread": "mention", "desktop": "none"])
        #expect(workspace.session.isMuted(channelId: "town"))
        #expect(!model.hasChanges)
        #expect(await model.save())
        #expect(transport.requests("PUT", "channels/town/members/me/notify_props").count == 1)
    }

    @Test func failedSaveKeepsTheSheetOpen() async {
        let transport = Fixture.transport()
        transport.on("PUT", "channels/*", status: 500, json: #"{"id":"err","message":"nope","status_code":500}"#)
        let workspace = Fixture.workspace(transport: transport)
        let model = ChannelNotificationsModel(workspace: workspace, channelId: "town")
        model.settings.muted = true
        #expect(!(await model.save()))
        #expect(model.hasChanges)
        #expect(!workspace.session.isMuted(channelId: "town"))
        #expect(workspace.visibleError == "nope")
    }
}

@MainActor
@Suite struct MutedRowPresentationTests {
    @Test func sidebarRowsCarryTheMutedFlag() {
        let session = Fixture.session()
        #expect(SidebarRowModel.make(channelId: "muted", session: session)?.muted == true)
        #expect(SidebarRowModel.make(channelId: "town", session: session)?.muted == false)
        session.members["town"]?.notifyProps["mark_unread"] = "mention"
        #expect(SidebarRowModel.make(channelId: "town", session: session)?.muted == true)
        let muted = SidebarRowModel.make(channelId: "muted", session: session)
        #expect(muted?.unread == false)
    }

    @Test func teamTilesCarryTheMutedFlag() {
        let session = Fixture.session()
        session.setMuted(teamId: "t2", true)
        let tiles = TeamTileModel.make(session: session)
        let design = tiles.first { $0.id == "t2" }
        #expect(design?.muted == true)
        #expect(design?.tooltip.hasSuffix("muted") == true)
        #expect(tiles.first { $0.id == "t1" }?.muted == false)
        #expect(tiles.first { $0.id == "t1" }?.tooltip.contains("muted") == false)
        session.setMuted(teamId: "t2", false)
        #expect(TeamTileModel.make(session: session).allSatisfy { !$0.muted })
    }

    @Test func workspaceShortcutsActOnTheCurrentChannel() async {
        let transport = Fixture.transport()
        transport.on("PUT", "channels/*", json: #"{"status":"OK"}"#)
        let workspace = Fixture.workspace(transport: transport)
        workspace.openNotificationPreferences()
        #expect(workspace.notificationPreferences == ChannelNotificationsTarget(id: "town"))
        await workspace.toggleMuteCurrentChannel()
        #expect(workspace.session.isMuted(channelId: "town"))
        workspace.session.currentChannelId = nil
        workspace.notificationPreferences = nil
        workspace.openNotificationPreferences()
        await workspace.toggleMuteCurrentChannel()
        #expect(workspace.notificationPreferences == nil)
    }
}

@MainActor
@Suite struct ChannelNotificationsRenderTests {
    @Test func sheetRendersMuteAndLevelSections() async {
        let transport = Fixture.transport()
        transport.on("PUT", "channels/*", json: #"{"status":"OK"}"#)
        let workspace = Fixture.workspace(transport: transport)
        workspace.session.collapsedThreads = true
        let open = await MainSnapshot.render(
            ChannelNotificationsSheet(workspace: workspace, channelId: "town"),
            size: CGSize(width: 440, height: 420),
            name: "channel-notifications"
        )
        #expect(MainSnapshot.distinctColors(open) > 2)
        let muted = await MainSnapshot.render(
            ChannelNotificationsSheet(workspace: workspace, channelId: "muted"),
            size: CGSize(width: 440, height: 260),
            name: "channel-notifications-muted"
        )
        #expect(muted.pixelsWide >= 440)
    }

    @Test func sidebarAndRailShowMutedIndicators() async {
        let (model, session) = Fixture.appModel()
        await model.selectServer(at: 0)
        session.setMuted(teamId: "t2", true)
        let sidebar = await MainSnapshot.render(ChannelSidebar(workspace: Fixture.workspace()), size: CGSize(width: 250, height: 520), name: "sidebar-muted")
        #expect(MainSnapshot.distinctColors(sidebar) > 4)
        let rail = await MainSnapshot.render(LeftRail(model: model, onAddServer: {}), size: CGSize(width: LeftRail.width, height: 400), name: "rail-muted")
        #expect(MainSnapshot.distinctColors(rail) > 4)
    }

    @Test func channelHeaderMenuRenders() async {
        let workspace = Fixture.workspace()
        workspace.session.members["town"]?.notifyProps["mark_unread"] = "mention"
        let channel = workspace.session.channels["town"]!
        let rep = await MainSnapshot.render(
            ChannelHeader(workspace: workspace, channel: channel),
            size: CGSize(width: 700, height: 56),
            name: "channel-header-muted"
        )
        #expect(rep.pixelsWide >= 700)
    }
}

@MainActor
@Suite struct NotificationCommandParsingTests {
    func command(_ path: String) -> DebugCommand? {
        DebugCommand(url: URL(string: "boltun://debug/\(path)")!)
    }

    @Test func muteCommandDefaultsToOn() {
        #expect(command("mute") == .mute(on: true))
        #expect(command("mute?on=1") == .mute(on: true))
        #expect(command("mute?on=0") == .mute(on: false))
    }

    @Test func teamMuteCommandNeedsATeam() {
        #expect(command("team-mute?team=alpha") == .teamMute(team: "alpha", on: true))
        #expect(command("team-mute?team=alpha&on=no") == .teamMute(team: "alpha", on: false))
        #expect(command("team-mute") == nil)
        #expect(command("team-mute?team=") == nil)
    }

    @Test func notifyPrefsCommandNeedsAtLeastOneOption() {
        #expect(command("notify-prefs") == nil)
        #expect(command("notify-prefs?desktop=loud") == nil)
        #expect(command("notify-prefs?desktop=all") == .notifyPrefs(mute: nil, desktop: .all, threads: nil, ignore: nil))
        #expect(command("notify-prefs?mute=1") == .notifyPrefs(mute: true, desktop: nil, threads: nil, ignore: nil))
        #expect(command("notify-prefs?threads=0&ignore=1") == .notifyPrefs(mute: nil, desktop: nil, threads: false, ignore: true))
        #expect(command("notify-prefs?desktop=default&mute=0") == .notifyPrefs(mute: false, desktop: .default, threads: nil, ignore: nil))
    }
}

@MainActor
struct NotificationAutomationTests {
    func make(_ harness: Harness) -> (DebugAutomation, LogSink, AppRouter) {
        let sink = LogSink()
        let router = AppRouter(model: harness.model)
        let automation = DebugAutomation(router: router, host: FakeAutomationHost(), isEnabled: { true }) { sink.lines.append($0) }
        return (automation, sink, router)
    }

    func connected() async -> Harness {
        let harness = await Harness.connected()
        harness.transport.set("PUT channels/c1/members/me/notify_props", #"{"status":"OK"}"#)
        await harness.model.selectedSession?.selectTeam("t1", channelId: "c1")
        return harness
    }

    @Test func mutesAndUnmutesTheCurrentChannel() async {
        let harness = await connected()
        let (automation, sink, _) = make(harness)
        await automation.handle(URL(string: "boltun://debug/mute")!)
        #expect(sink.lines.last == "ok /mute true")
        #expect(harness.model.selectedSession?.isMuted(channelId: "c1") == true)
        await automation.handle(URL(string: "boltun://debug/mute?on=0")!)
        #expect(sink.lines.last == "ok /mute false")
        #expect(harness.model.selectedSession?.isMuted(channelId: "c1") == false)
    }

    @Test func reportsMuteFailures() async {
        let harness = await connected()
        harness.transport.set("PUT channels/c1/members/me/notify_props", status: 500, #"{"id":"e","message":"server said no","status_code":500}"#)
        let (automation, sink, _) = make(harness)
        await automation.handle(URL(string: "boltun://debug/mute")!)
        #expect(sink.lines.last == "error /mute server said no")
    }

    @Test func appliesNotificationPreferences() async throws {
        let harness = await connected()
        let (automation, sink, _) = make(harness)
        await automation.handle(URL(string: "boltun://debug/notify-prefs?desktop=all&threads=0&ignore=1")!)
        #expect(sink.lines.last == "ok /notify-prefs muted=false desktop=all threads=mention ignore=on")
        let request = try #require(harness.transport.requests(matching: "PUT channels/c1/members/me/notify_props").last)
        let httpBody = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: httpBody) as? [String: String])
        #expect(body == ["desktop": "all", "desktop_threads": "mention", "ignore_channel_mentions": "on"])
        await automation.handle(URL(string: "boltun://debug/notify-prefs?mute=1")!)
        #expect(sink.lines.last == "ok /notify-prefs muted=true desktop=all threads=mention ignore=on")
    }

    @Test func mutesTeamsAndReportsThemInState() async throws {
        let harness = await connected()
        let (automation, sink, _) = make(harness)
        await automation.handle(URL(string: "boltun://debug/team-mute?team=team-two")!)
        #expect(sink.lines.last == "ok /team-mute t2")
        #expect(harness.model.servers[0].teamLayout.muted == ["t2"])
        let path = "/tmp/boltun-tests-\(UUID().uuidString)-muted.json"
        await automation.handle(URL(string: "boltun://debug/state?path=\(path)")!)
        let state = try JSONDecoder().decode(AutomationState.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        try? FileManager.default.removeItem(atPath: path)
        #expect(state.servers[0].mutedTeams == ["team-two"])
        await automation.handle(URL(string: "boltun://debug/team-mute?team=team-two&on=0")!)
        #expect(sink.lines.last == "ok /team-mute")
        await automation.handle(URL(string: "boltun://debug/team-mute?team=nope")!)
        #expect(sink.lines.last == "error /team-mute no team nope")
    }

    @Test func presentsTheNotificationPreferencesSheet() async throws {
        let harness = await connected()
        let (automation, sink, router) = make(harness)
        await automation.handle(URL(string: "boltun://debug/present?sheet=notifications")!)
        #expect(sink.lines.last == "ok /present")
        let workspace = try #require(router.workspaces.existing(serverId: harness.model.servers[0].id))
        #expect(workspace.notificationPreferences == ChannelNotificationsTarget(id: "c1"))
        let path = "/tmp/boltun-tests-\(UUID().uuidString)-sheet.json"
        await automation.handle(URL(string: "boltun://debug/state?path=\(path)")!)
        let state = try JSONDecoder().decode(AutomationState.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        try? FileManager.default.removeItem(atPath: path)
        #expect(state.ui?.sheets.contains("notification-preferences") == true)
    }

    @Test func reportsMutedChannelsInUIState() async throws {
        let harness = await connected()
        let (automation, _, _) = make(harness)
        await automation.handle(URL(string: "boltun://debug/mute")!)
        let path = "/tmp/boltun-tests-\(UUID().uuidString)-ui.json"
        await automation.handle(URL(string: "boltun://debug/state?path=\(path)")!)
        let state = try JSONDecoder().decode(AutomationState.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        try? FileManager.default.removeItem(atPath: path)
        #expect(state.ui?.mutedChannels == ["Town Square"])
    }

    @Test func notificationCommandsNeedAChannel() async {
        let harness = await connected()
        harness.model.selectedSession?.currentChannelId = nil
        let (automation, sink, _) = make(harness)
        await automation.handle(URL(string: "boltun://debug/mute")!)
        #expect(sink.lines.last == "error /mute no channel")
        await automation.handle(URL(string: "boltun://debug/notify-prefs?mute=1")!)
        #expect(sink.lines.last == "error /notify-prefs no channel")
        await automation.handle(URL(string: "boltun://debug/present?sheet=notifications")!)
        #expect(sink.lines.last == "error /present no channel")
    }
}

@MainActor
@Suite struct ChannelMenuCommandTests {
    @Test func menuTitleTracksTheCurrentChannel() async {
        let transport = Fixture.transport()
        transport.on("PUT", "channels/*", json: #"{"status":"OK"}"#)
        let (model, session) = Fixture.appModel(transport: transport)
        await model.selectServer(at: 0)
        let router = AppRouter(model: model)
        let commands = AppCommands(router: router)
        #expect(commands.currentWorkspace == nil)
        #expect(commands.muteTitle == "Mute Channel")
        let workspace = router.workspaces.workspace(for: session, serverURL: Fixture.serverURL)
        #expect(commands.currentChannelId == "town")
        #expect(commands.muteTitle == "Mute Channel")
        await workspace.toggleMuteCurrentChannel()
        #expect(commands.muteTitle == "Unmute Channel")
        await session.selectChannel("dm-alice")
        #expect(commands.muteTitle == "Mute Conversation")
        session.currentChannelId = nil
        #expect(commands.currentChannelId == nil)
        #expect(commands.muteTitle == "Mute Channel")
    }
}
