@testable import BoltunKit
import Foundation
import Testing
@testable import BoltunUI

@MainActor
struct AppRouterTests {
    @Test func presentsAndDismissesSheets() {
        let server = Harness.server()
        let harness = Harness(servers: [server])
        let router = AppRouter(model: harness.model)
        var shown = 0
        router.showMainWindow = { shown += 1 }
        router.presentAddServer()
        #expect(router.sheet == .addServer)
        #expect(router.sheet?.id == "add-server")
        router.presentLogin(serverId: server.id)
        #expect(router.sheet == .login(server.id))
        #expect(router.sheet?.id == "login-\(server.id.uuidString)")
        router.presentLogin(serverId: UUID())
        #expect(router.sheet == .login(server.id))
        router.dismissSheet()
        #expect(router.sheet == nil)
        #expect(shown == 2)
    }

    @Test func publishesCommands() {
        let router = AppRouter(model: Harness().model)
        #expect(router.lastCommand == nil)
        router.focusQuickSwitcher()
        #expect(router.lastCommand == AppCommandEvent(sequence: 1, command: .focusQuickSwitcher))
        router.focusSearch()
        router.focusComposer()
        #expect(router.lastCommand?.sequence == 3)
        #expect(router.lastCommand?.command == .focusComposer)
        router.toggleSidebar()
        #expect(!router.isSidebarVisible)
        router.toggleThreadPane()
        #expect(router.isThreadPaneVisible)
        router.toggleThreadPane()
        router.send(.openThread(rootId: "r1"))
        #expect(router.isThreadPaneVisible)
        #expect(router.consumePendingThreadRootId() == "r1")
        #expect(router.pendingThreadRootId == nil)
        router.send(.highlightPost(postId: "p1"))
        #expect(router.consumePendingPostId() == "p1")
        #expect(router.consumePendingPostId() == nil)
    }

    @Test func opensSettings() {
        let router = AppRouter(model: Harness().model)
        var opened = 0
        router.openSettingsWindow = { opened += 1 }
        router.openSettings(tab: .about)
        #expect(router.settingsTab == .about)
        router.openSettings()
        #expect(router.settingsTab == .about)
        #expect(opened == 2)
    }

    @Test func cyclesServers() async {
        let servers = [Harness.server("A", port: 1), Harness.server("B", port: 2), Harness.server("C", port: 3)]
        let harness = Harness(servers: servers)
        let router = AppRouter(model: harness.model)
        #expect(router.selectedIndex == 0)
        await router.selectNextServer()
        #expect(router.selectedIndex == 1)
        await router.selectPreviousServer()
        await router.selectPreviousServer()
        #expect(router.selectedIndex == 2)
        await router.selectNextServer()
        #expect(router.selectedIndex == 0)
        await router.selectServer(number: 2)
        #expect(router.selectedIndex == 1)
        await router.selectServer(number: 9)
        #expect(router.selectedIndex == 1)
    }

    @Test func cyclingWithSingleServerIsNoop() async {
        let harness = Harness(servers: [Harness.server()])
        let router = AppRouter(model: harness.model)
        await router.selectNextServer()
        #expect(router.selectedIndex == 0)
    }

    @Test func zoomsWithinRange() {
        let harness = Harness()
        let router = AppRouter(model: harness.model)
        router.zoomIn()
        #expect(harness.model.settings.fontScale == 1.1)
        router.zoomOut()
        router.zoomOut()
        #expect(harness.model.settings.fontScale == 0.9)
        router.resetZoom()
        #expect(harness.model.settings.fontScale == 1.0)
        for _ in 0..<30 { router.zoomIn() }
        #expect(harness.model.settings.fontScale == AppRouter.fontScaleRange.upperBound)
        #expect(!router.canZoomIn)
        for _ in 0..<30 { router.zoomOut() }
        #expect(harness.model.settings.fontScale == AppRouter.fontScaleRange.lowerBound)
        #expect(!router.canZoomOut)
        #expect(harness.store.load().settings.fontScale == AppRouter.fontScaleRange.lowerBound)
    }

    @Test func presentsLoginWhenSelectedServerNeedsIt() {
        let server = Harness.server()
        let harness = Harness(servers: [server])
        let router = AppRouter(model: harness.model)
        router.presentLoginIfNeeded()
        #expect(router.sheet == nil)
        #expect(!router.currentServerNeedsLogin)
        harness.model.addServer(name: "B", url: URL(string: "https://b.example.com")!)
        harness.model.makeSession(for: server)
        #expect(router.currentServerNeedsLogin)
        router.presentLoginIfNeeded()
        #expect(router.sheet == .login(server.id))
    }

    @Test func signsOutCurrentServer() async {
        let harness = await Harness.connected()
        let server = harness.model.servers[0]
        let router = AppRouter(model: harness.model)
        await router.signOutCurrentServer()
        #expect(harness.model.needsLogin.contains(server.id))
        #expect(harness.credentials.token(for: server.id) == nil)
        #expect(router.sheet == .login(server.id))
        #expect(harness.transport.requests(matching: "POST users/logout").count == 1)
    }

    @Test func signOutWithoutServerIsNoop() async {
        let router = AppRouter(model: Harness().model)
        await router.signOutCurrentServer()
        #expect(router.sheet == nil)
    }

    @Test func routesNotificationTargets() async {
        let first = Harness.server("A", port: 1)
        let second = Harness.server("B", port: 2)
        let harness = await Harness.connected([first, second])
        let router = AppRouter(model: harness.model)
        await router.route(serverId: second.id, teamId: "t2", channelId: "c4", rootId: "r1")
        let session = harness.model.session(for: second.id)
        #expect(harness.model.selectedServerId == second.id)
        #expect(session?.currentTeamId == "t2")
        #expect(session?.currentChannelId == "c4")
        #expect(router.pendingThreadRootId == "r1")
        await router.route(serverId: second.id, teamId: nil, channelId: "c1", rootId: nil)
        #expect(session?.currentChannelId == "c1")
        await router.route(serverId: UUID(), teamId: nil, channelId: nil)
        #expect(harness.model.selectedServerId == second.id)
    }

    @Test func routingToTheOpenChannelMarksItRead() async throws {
        let harness = await Harness.connected()
        let server = harness.model.servers[0]
        let router = AppRouter(model: harness.model)
        await router.route(serverId: server.id, teamId: "t1", channelId: "c1")
        let session = try #require(harness.model.selectedSession)
        #expect(session.currentChannelId == "c1")
        let viewed = harness.transport.requests(matching: "POST channels/members/me/view").count
        session.members["c1"]?.mentionCount = 2
        await router.route(serverId: server.id, teamId: nil, channelId: "c1")
        #expect(session.currentChannelId == "c1")
        #expect(session.unread(channelId: "c1") == .none)
        #expect(harness.transport.requests(matching: "POST channels/members/me/view").count == viewed + 1)
    }

    @Test func routingToSignedOutServerPresentsLogin() async {
        let server = Harness.server()
        let harness = Harness(servers: [server])
        await harness.model.startAll()
        let router = AppRouter(model: harness.model)
        await router.route(serverId: server.id, teamId: "t1", channelId: "c1")
        #expect(router.sheet == .login(server.id))
    }

    @Test func routingTimesOutWhenNotConnected() async {
        let server = Harness.server()
        let harness = Harness(servers: [server], tokens: [server.id: "token"])
        harness.model.makeSession(for: server)
        let router = AppRouter(model: harness.model)
        router.connectionTimeout = .milliseconds(50)
        #expect(await router.connectedSession(server.id) == nil)
    }

    @Test func waitsForConnection() async {
        let server = Harness.server()
        let harness = Harness(servers: [server], tokens: [server.id: "token"])
        let router = AppRouter(model: harness.model)
        Task { await harness.model.startAll() }
        #expect(await router.connectedSession(server.id) != nil)
    }
}

@MainActor
struct AppRouterDeepLinkTests {
    let server = ServerConfig(name: "Alpha", url: URL(string: "http://chat.example.com:8065")!)

    func setUp() async -> (Harness, AppRouter) {
        let harness = await Harness.connected([server])
        return (harness, AppRouter(model: harness.model))
    }

    @Test func opensChannelLink() async {
        let (harness, router) = await setUp()
        let opened = await router.open(url: URL(string: "mattermost://chat.example.com:8065/team-two/channels/random")!)
        #expect(opened)
        #expect(harness.model.selectedSession?.currentChannelId == "c4")
        #expect(router.lastRouteError == nil)
    }

    @Test func opensTeamAndServerLinks() async {
        let (harness, router) = await setUp()
        #expect(await router.open(url: URL(string: "mattermost://chat.example.com/team-two")!))
        #expect(harness.model.selectedSession?.currentTeamId == "t2")
        #expect(await router.open(url: URL(string: "boltun://chat.example.com:8065")!))
    }

    @Test func opensPermalinkAndThread() async {
        let (harness, router) = await setUp()
        #expect(await router.open(url: URL(string: "http://chat.example.com:8065/team-two/pl/p9")!))
        #expect(harness.model.selectedSession?.currentChannelId == "c4")
        #expect(router.pendingPostId == "p9")
        #expect(router.pendingThreadRootId == "r9")
        router.pendingThreadRootId = nil
        #expect(await router.open(url: URL(string: "mattermost://chat.example.com/team-two/threads/p9")!))
        #expect(router.pendingThreadRootId == "r9")
    }

    @Test func opensDirectMessage() async {
        let (harness, router) = await setUp()
        #expect(await router.open(url: URL(string: "mattermost://chat.example.com/team-one/messages/@alice")!))
        #expect(harness.model.selectedSession?.currentChannelId == "dm1")
    }

    @Test func reportsFailures() async {
        let (_, router) = await setUp()
        #expect(!(await router.open(url: URL(string: "mattermost://chat.example.com/nope/channels/x")!)))
        #expect(router.lastRouteError != nil)
        #expect(!(await router.open(url: URL(string: "mattermost://chat.example.com/team-one/channels/missing")!)))
        #expect(!(await router.open(url: URL(string: "mattermost://chat.example.com/team-one/pl/missing")!)))
        #expect(!(await router.open(url: URL(string: "mattermost://other.example.com/team")!)))
        #expect(router.lastRouteError == "No server matches other.example.com")
        #expect(!(await router.open(url: URL(string: "ftp://chat.example.com/x")!)))
    }

    @Test func forwardsUnknownWebLinks() async {
        let (_, router) = await setUp()
        var external: [URL] = []
        router.openExternalURL = { external.append($0) }
        let url = URL(string: "https://elsewhere.example.com/page")!
        #expect(!(await router.open(url: url)))
        #expect(external == [url])
        #expect(router.lastRouteError == nil)
    }
}
