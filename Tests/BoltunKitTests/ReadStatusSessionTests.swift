import Foundation
import Testing
@testable import BoltunKit

extension MockServer {
    func readCounts(_ channelId: String = "c-dm", type: String = "D", name: String = "me1__u2", total: Int, members: [String: Int]) {
        transport.on("GET", "channels/\(channelId)", object: Fixtures.channel(channelId, team: "", type: type, name: name, total: total, lastPostAt: 900))
        transport.on("GET", "channels/\(channelId)/members", object: members.sorted { $0.key < $1.key }.map { userId, count in
            ["channel_id": channelId, "user_id": userId, "msg_count": count, "msg_count_root": count, "mention_count": 0, "roles": "channel_user"]
        })
    }

    func memberRequests(_ channelId: String = "c-dm") -> Int {
        transport.count("GET", "channels/\(channelId)/members")
    }
}

@MainActor
@Suite struct ReadStatusSessionTests {
    func server(partnerViewed: Int = 1) -> MockServer {
        let server = MockServer(pageSize: 10)
        server.setPosts("c-dm", [
            Fixtures.post("d1", channel: "c-dm", user: "me1", message: "first", createAt: 100),
            Fixtures.post("d2", channel: "c-dm", user: "me1", message: "second", createAt: 200),
        ])
        server.readCounts(total: 2, members: ["me1": 2, "u2": partnerViewed])
        return server
    }

    func openDirect(_ server: MockServer, configure: (ServerSession) -> Void = { _ in }) async -> ServerSession {
        let session = server.session(pageSize: 10)
        configure(session)
        await session.start()
        await session.selectTeam("t1")
        await session.selectChannel("c-dm")
        return session
    }

    @Test func selectingDirectChannelLoadsCountsAndComputesStates() async {
        let server = server()
        let session = await openDirect(server)
        #expect(server.memberRequests() == 1)
        #expect(server.transport.count("GET", "channels/c-dm") == 1)
        #expect(session.readCounts["c-dm"] == [MemberReadCount(userId: "u2", msgCount: 1, msgCountRoot: 1)])
        #expect(session.readStates(channelId: "c-dm") == ["d1": .seen, "d2": .sent])
        #expect(session.hasUnseenOwnPost(channelId: "c-dm"))
        #expect(session.isPollingReadStatus)
        session.stop()
        #expect(!session.isPollingReadStatus)
    }

    @Test func publicChannelsAreNeverRequested() async {
        let server = server()
        let session = await server.startedSession(pageSize: 10)
        await session.selectChannel("c-dev")
        await session.refreshReadStatus(channelId: "c-dev")
        await session.refreshVisibleReadStatus()
        #expect(!session.tracksReadStatus(channelId: "c-town"))
        #expect(!session.tracksReadStatus(channelId: "c-dev"))
        #expect(session.readStates(channelId: "c-dev").isEmpty)
        #expect(!server.transport.requests.contains { $0.url?.path.hasSuffix("/members") == true && $0.httpMethod == "GET" && $0.url?.path.contains("/channels/c-") == true })
        #expect(!session.isPollingReadStatus)
        session.stop()
    }

    @Test func togglingTheSettingControlsRequestsAndState() async {
        let server = server()
        let session = await openDirect(server) { $0.readStatusEnabled = false }
        #expect(server.memberRequests() == 0)
        #expect(session.readStates(channelId: "c-dm").isEmpty)
        #expect(!session.tracksReadStatus(channelId: "c-dm"))
        await session.setReadStatusEnabled(true)
        #expect(server.memberRequests() == 1)
        #expect(session.readStates(channelId: "c-dm")["d2"] == .sent)
        #expect(session.isPollingReadStatus)
        await session.setReadStatusEnabled(false)
        #expect(session.readCounts.isEmpty)
        #expect(!session.isPollingReadStatus)
        #expect(session.readStates(channelId: "c-dm").isEmpty)
        await session.setReadStatusEnabled(false)
        session.apply(Fixtures.wsEvent("typing", data: ["user_id": "u2", "parent_id": ""], channel: "c-dm"))
        await settle()
        #expect(server.memberRequests() == 1)
        session.stop()
    }

    @Test func sendingRefreshesAndKeepsTheLocalTotal() async throws {
        let server = server()
        server.acceptPosts()
        let session = await openDirect(server)
        #expect(await session.send("third", channelId: "c-dm"))
        #expect(await eventually { server.memberRequests() == 2 })
        await settle()
        #expect(session.channels["c-dm"]?.totalMsgCount == 3)
        let sent = try #require(session.timelinePosts(channelId: "c-dm").last)
        #expect(session.readStates(channelId: "c-dm") == ["d1": .seen, "d2": .sent, sent.id: .sent])
        session.stop()
    }

    @Test func activityFromThePartnerRefreshes() async {
        let server = server()
        let session = await openDirect(server)
        session.users["u2"] = User(id: "u2", username: "bob")
        let events: [WebSocketEvent] = [
            Fixtures.wsEvent("typing", data: ["user_id": "u2", "parent_id": ""], channel: "c-dm"),
            Fixtures.wsEvent("reaction_added", data: ["reaction": Fixtures.json(Fixtures.reaction(user: "u2", post: "d1", emoji: "+1"))], channel: "c-dm"),
            Fixtures.wsEvent("post_edited", data: ["post": Fixtures.json(Fixtures.post("d0", channel: "c-dm", user: "u2", message: "edited", createAt: 50, updateAt: 60))], channel: "c-dm"),
            Fixtures.posted(Fixtures.post("n1", channel: "c-dm", user: "u2", message: "hi", createAt: 300), channelType: "D", team: ""),
        ]
        for (index, event) in events.enumerated() {
            session.apply(event)
            #expect(await eventually { server.memberRequests() == index + 2 }, "\(event.event)")
            await settle()
        }
        server.readCounts(total: 3, members: ["me1": 3, "u2": 3])
        session.apply(events[0])
        #expect(await eventually { session.readStates(channelId: "c-dm") == ["d1": .seen, "d2": .seen] })
        #expect(!session.hasUnseenOwnPost(channelId: "c-dm"))
        #expect(!session.isPollingReadStatus)
        session.stop()
    }

    @Test func ownActivityAndOtherChannelsDoNotRefresh() async {
        let server = server()
        let session = await openDirect(server)
        session.apply(Fixtures.wsEvent("typing", data: ["user_id": "me1", "parent_id": ""], channel: "c-dm"))
        session.apply(Fixtures.wsEvent("typing", data: ["user_id": "u2", "parent_id": ""], channel: "c-gm"))
        session.apply(Fixtures.wsEvent("reaction_removed", data: ["reaction": Fixtures.json(Fixtures.reaction(user: "u2", post: "d1", emoji: "+1"))], channel: "c-dm"))
        session.apply(Fixtures.wsEvent("reaction_added", data: ["reaction": Fixtures.json(Fixtures.reaction(user: "me1", post: "d1", emoji: "+1"))], channel: "c-dm"))
        session.apply(Fixtures.posted(Fixtures.post("t1", channel: "c-town", user: "u2", message: "town", createAt: 300)))
        session.apply(Fixtures.posted(Fixtures.post("g1", channel: "c-gm", user: "u3", message: "group", createAt: 300), channelType: "G", team: ""))
        await settle(40)
        #expect(server.memberRequests() == 1)
        #expect(server.memberRequests("c-gm") == 0)
        session.stop()
    }

    @Test func ownPostFromAnotherDeviceRefreshesOnce() async {
        let server = server()
        let session = await openDirect(server)
        let mine = Fixtures.post("phone", channel: "c-dm", user: "me1", message: "from phone", createAt: 300)
        session.apply(Fixtures.posted(mine, channelType: "D", sender: "@alice", team: ""))
        #expect(await eventually { server.memberRequests() == 2 })
        session.apply(Fixtures.posted(mine, channelType: "D", sender: "@alice", team: ""))
        await settle()
        #expect(server.memberRequests() == 2)
        session.stop()
    }

    @Test func reconnectRefreshes() async {
        let server = server()
        let session = await openDirect(server)
        await session.handle(realtime: .connected(needsResync: false))
        #expect(await eventually { server.memberRequests() == 2 })
        session.stop()
    }

    @Test func concurrentRefreshesAreCoalesced() async {
        let server = server()
        let session = await openDirect(server)
        let gate = Gate()
        server.hold("GET", "channels/c-dm/members", gate: gate) { _ in
            .object([["channel_id": "c-dm", "user_id": "u2", "msg_count": 2, "msg_count_root": 2]])
        }
        for _ in 0..<3 { Task { await session.refreshReadStatus(channelId: "c-dm") } }
        for _ in 0..<2 { session.apply(Fixtures.wsEvent("typing", data: ["user_id": "u2", "parent_id": ""], channel: "c-dm")) }
        #expect(await eventually { server.memberRequests() == 2 })
        await settle()
        #expect(server.memberRequests() == 2)
        await gate.open()
        #expect(await eventually { server.memberRequests() == 3 })
        await settle()
        #expect(server.memberRequests() == 3)
        #expect(session.readStates(channelId: "c-dm") == ["d1": .seen, "d2": .seen])
        session.stop()
    }

    @Test func staleChannelTotalsNeverLowerLocalCounts() async {
        let server = server()
        let session = await openDirect(server)
        session.channels["c-dm"]?.totalMsgCount = 5
        session.channels["c-dm"]?.totalMsgCountRoot = 4
        let fetched = Channel(id: "c-dm", type: .direct, name: "me1__u2", lastPostAt: 10, totalMsgCount: 3, totalMsgCountRoot: 3)
        session.applyReadCounts(channel: fetched, counts: [MemberReadCount(userId: "u2", msgCount: 3), MemberReadCount(userId: "me1", msgCount: 5)])
        #expect(session.channels["c-dm"]?.totalMsgCount == 5)
        #expect(session.channels["c-dm"]?.totalMsgCountRoot == 4)
        #expect(session.channels["c-dm"]?.lastPostAt == 900)
        #expect(session.readCounts["c-dm"] == [MemberReadCount(userId: "u2", msgCount: 3)])
        var newer = fetched
        newer.totalMsgCount = 7
        newer.totalMsgCountRoot = 6
        newer.lastPostAt = 1000
        session.applyReadCounts(channel: newer, counts: [MemberReadCount(userId: "u2", msgCount: 7)])
        #expect(session.channels["c-dm"]?.totalMsgCount == 7)
        #expect(session.channels["c-dm"]?.totalMsgCountRoot == 6)
        #expect(session.channels["c-dm"]?.lastPostAt == 1000)
        session.stop()
    }

    @Test func failedRefreshKeepsPreviousCountsQuietly() async {
        let server = server()
        let session = await openDirect(server)
        server.transport.on("GET", "channels/c-dm/members", .error(500))
        await session.refreshReadStatus(channelId: "c-dm")
        #expect(server.memberRequests() == 2)
        #expect(session.lastError == nil)
        #expect(session.readCounts["c-dm"] == [MemberReadCount(userId: "u2", msgCount: 1, msgCountRoot: 1)])
        session.stop()
    }

    @Test func onlyRealPartnersAndGroupsAreTracked() async {
        let server = server()
        let session = await openDirect(server)
        #expect(session.tracksReadStatus(channelId: "c-dm"))
        #expect(session.tracksReadStatus(channelId: "c-gm"))
        #expect(!session.tracksReadStatus(channelId: "missing"))
        session.users["u2"] = User(id: "u2", username: "helper", isBot: true)
        #expect(!session.tracksReadStatus(channelId: "c-dm"))
        session.channels["c-self"] = Channel(id: "c-self", type: .direct, name: "me1__me1")
        #expect(!session.tracksReadStatus(channelId: "c-self"))
        session.channels["c-broken"] = Channel(id: "c-broken", type: .direct, name: "broken")
        #expect(!session.tracksReadStatus(channelId: "c-broken"))
        session.stop()
    }

    @Test func groupChannelsReportPartialReads() async {
        let server = server()
        server.setPosts("c-gm", [Fixtures.post("g1", channel: "c-gm", user: "me1", message: "hello all", createAt: 100)])
        server.readCounts("c-gm", type: "G", name: "gmhash", total: 1, members: ["me1": 1, "u2": 1, "u3": 0])
        let session = await server.startedSession(pageSize: 10)
        await session.selectChannel("c-gm")
        #expect(session.readStates(channelId: "c-gm") == ["g1": .partiallySeen(seenBy: ["u2"], total: 2)])
        #expect(session.hasUnseenOwnPost(channelId: "c-gm"))
        session.stop()
    }

    @Test func uncountedPostsDoNotRaiseChannelTotals() async {
        let session = await MockServer().startedSession()
        session.apply(Fixtures.posted(Fixtures.post("j1", channel: "c-dev", user: "u3", message: "joined", createAt: 1000, type: "system_join_channel")))
        session.apply(Fixtures.posted(Fixtures.post("b1", channel: "c-dev", user: "u2", message: "", createAt: 1001, type: PostType.burnOnRead)))
        #expect(session.channels["c-dev"]?.totalMsgCount == 3)
        #expect(session.channels["c-dev"]?.totalMsgCountRoot == 3)
        #expect(session.channels["c-dev"]?.lastPostAt == 1001)
        session.apply(Fixtures.posted(Fixtures.post("h1", channel: "c-dev", user: "u2", message: "header", createAt: 1002, type: "system_header_change")))
        #expect(session.channels["c-dev"]?.totalMsgCount == 4)
        session.stop()
    }
}

@MainActor
@Suite struct ReadStatusPollingSessionTests {
    func server() -> MockServer {
        let server = MockServer(pageSize: 10)
        server.setPosts("c-dm", [Fixtures.post("d1", channel: "c-dm", user: "me1", message: "first", createAt: 100)])
        server.readCounts(total: 2, members: ["me1": 2, "u2": 0])
        return server
    }

    func open(_ server: MockServer, active: @escaping @MainActor () -> Bool = { true }) async -> ServerSession {
        let session = server.session(pageSize: 10)
        session.readStatusPollInterval = .milliseconds(30)
        session.readStatusMaxPollInterval = .milliseconds(60)
        session.isAppActive = active
        await session.start()
        await session.selectTeam("t1")
        await session.selectChannel("c-dm")
        return session
    }

    @Test func pollsWhileUnseenAndStopsOnceSeen() async {
        let server = server()
        let session = await open(server)
        #expect(session.isPollingReadStatus)
        #expect(await eventually { server.memberRequests() >= 3 })
        server.readCounts(total: 2, members: ["me1": 2, "u2": 2])
        #expect(await eventually { !session.isPollingReadStatus })
        #expect(session.readStates(channelId: "c-dm") == ["d1": .seen])
        let settled = server.memberRequests()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(server.memberRequests() == settled)
        session.stop()
    }

    @Test func doesNotPollWhileInactive() async {
        let server = server()
        let session = await open(server) { false }
        #expect(server.memberRequests() == 1)
        #expect(!session.isPollingReadStatus)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(server.memberRequests() == 1)
        session.stop()
    }

    @Test func stopsWhenTheAppGoesInactive() async {
        let server = server()
        var active = true
        let session = await open(server) { active }
        #expect(session.isPollingReadStatus)
        active = false
        #expect(await eventually { !session.isPollingReadStatus })
        let settled = server.memberRequests()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(server.memberRequests() == settled)
        session.stop()
    }

    @Test func stopsWhenTheChannelChanges() async {
        let server = server()
        let session = await open(server)
        #expect(session.isPollingReadStatus)
        await session.selectChannel("c-town")
        #expect(!session.isPollingReadStatus)
        session.stop()
    }

    @Test func stopsWhenAskedAndRestartsOnTrigger() async {
        let server = server()
        let session = await open(server)
        session.stopReadStatusPolling()
        #expect(!session.isPollingReadStatus)
        await session.refreshVisibleReadStatus()
        #expect(session.isPollingReadStatus)
        let task = session.readStatusPollTask
        await session.refreshVisibleReadStatus()
        #expect(session.readStatusPollTask == task)
        await session.refreshVisibleReadStatus(restartPolling: true)
        #expect(session.readStatusPollTask != task)
        session.stop()
    }
}

@MainActor
@Suite struct ReadStatusAppModelTests {
    @Test func settingIsCopiedIntoSessionsAndPropagated() async {
        let harness = AppHarness()
        let app = harness.model()
        let session = app.makeSession(for: app.servers[0])
        #expect(session.readStatusEnabled)
        app.settings.showReadStatus = false
        #expect(await eventually { !session.readStatusEnabled })
        let other = app.makeSession(for: app.servers[1])
        #expect(!other.readStatusEnabled)
        app.settings.showReadStatus = true
        #expect(await eventually { session.readStatusEnabled && other.readStatusEnabled })
        #expect(harness.store.load().settings.showReadStatus)
    }

    @Test func settingDefaultsToOnForOlderState() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"collapsedThreads":false}"#.utf8))
        #expect(decoded.showReadStatus)
        #expect(!decoded.collapsedThreads)
        var settings = AppSettings()
        settings.showReadStatus = false
        let roundTrip = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(!roundTrip.showReadStatus)
    }

    @Test func activationRefreshesAndResigningStopsPolling() async {
        let harness = AppHarness()
        harness.server.setPosts("c-dm", [Fixtures.post("d1", channel: "c-dm", user: "me1", message: "first", createAt: 100)])
        harness.server.readCounts(total: 1, members: ["me1": 1, "u2": 0])
        let app = harness.model()
        await app.refreshSelectedReadStatus()
        let session = app.makeSession(for: app.servers[0])
        await session.start()
        await session.selectTeam("t1")
        await session.selectChannel("c-dm")
        #expect(harness.server.memberRequests() == 1)
        #expect(session.isPollingReadStatus)
        app.appDidResignActive()
        #expect(!session.isPollingReadStatus)
        await app.refreshSelectedReadStatus()
        #expect(harness.server.memberRequests() == 2)
        #expect(session.isPollingReadStatus)
        let other = app.makeSession(for: app.servers[1])
        await app.select(serverId: app.servers[1].id)
        #expect(!session.isPollingReadStatus)
        #expect(!other.isPollingReadStatus)
        session.stop()
    }
}
