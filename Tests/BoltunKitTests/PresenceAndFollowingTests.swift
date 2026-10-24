import Foundation
import Testing
@testable import BoltunKit

@Suite struct ThreadFollowingModelTests {
    @Test func postDecodesFollowingFlag() throws {
        var raw = Fixtures.post("p1", channel: "c", user: "u1", message: "root", createAt: 1, replyCount: 2)
        #expect(try Fixtures.decode(Post.self, raw).isFollowing == nil)
        raw["is_following"] = true
        #expect(try Fixtures.decode(Post.self, raw).isFollowing == true)
        raw["is_following"] = false
        #expect(try Fixtures.decode(Post.self, raw).isFollowing == false)
        raw["is_following"] = "yes"
        #expect(try Fixtures.decode(Post.self, raw).isFollowing == nil)
        let encoded = Post(id: "x", userId: "u", channelId: "c", message: "", isFollowing: true)
        #expect(try MattermostJSON.decoder.decode(Post.self, from: MattermostJSON.encoder.encode(encoded)).isFollowing == true)
    }

    @Test func mergingKeepsKnownFollowingState() {
        let old = Post(id: "p", updateAt: 1, userId: "u", channelId: "c", message: "a", isFollowing: true)
        let bare = Post(id: "p", updateAt: 2, userId: "u", channelId: "c", message: "b")
        #expect(bare.mergingThreadSummary(from: old).isFollowing == true)
        let explicit = Post(id: "p", updateAt: 3, userId: "u", channelId: "c", message: "c", isFollowing: false)
        #expect(explicit.mergingThreadSummary(from: old).isFollowing == false)
    }

    @Test func clientConfigUserStatusesDefaultToEnabled() {
        #expect(ClientConfig(values: [:]).enableUserStatuses)
        #expect(ClientConfig(values: ["EnableUserStatuses": "true"]).enableUserStatuses)
        #expect(!ClientConfig(values: ["EnableUserStatuses": "false"]).enableUserStatuses)
    }

    @Test func followEndpointsUseThreadMembershipRoutes() async throws {
        let transport = FakeTransport()
        transport.on("PUT", "users/me1/teams/t1/threads/root/following", .ok)
        transport.on("DELETE", "users/me1/teams/t1/threads/root/following", .ok)
        transport.on("GET", "posts/root/thread", object: Fixtures.postList([]))
        let client = APIClient(baseURL: MockServer.baseURL, token: "t", transport: transport)
        try await client.setThreadFollowing(userId: "me1", teamId: "t1", threadId: "root", following: true)
        try await client.setThreadFollowing(userId: "me1", teamId: "t1", threadId: "root", following: false)
        #expect(transport.count("PUT", "users/me1/teams/t1/threads/root/following") == 1)
        #expect(transport.count("DELETE", "users/me1/teams/t1/threads/root/following") == 1)
        _ = try await client.postThread(postId: "root", collapsedThreads: true)
        let collapsed = try #require(transport.last("GET", "posts/root/thread")).query
        #expect(collapsed["collapsedThreads"] == "true")
        #expect(collapsed["collapsedThreadsExtended"] == "false")
        _ = try await client.postThread(postId: "root")
        #expect(try #require(transport.last("GET", "posts/root/thread")).query.isEmpty)
    }
}

@MainActor
@Suite struct ThreadFollowingSessionTests {
    static let followPath = "users/me1/teams/t1/threads/root/following"

    func server(rootFollowing: Bool? = nil) -> MockServer {
        let server = MockServer(pageSize: 10)
        var root = Fixtures.post("root", channel: "c-town", user: "u2", message: "root", createAt: 100, replyCount: 1)
        root["last_reply_at"] = 200
        root["participants"] = [Fixtures.user("u3", "carol")]
        if let rootFollowing { root["is_following"] = rootFollowing }
        let reply = Fixtures.post("reply1", channel: "c-town", user: "u3", message: "reply", createAt: 200, rootId: "root")
        server.setPosts("c-town", [root, reply])
        server.transport.on("GET", "posts/root/thread", object: Fixtures.postList([root, reply]))
        server.transport.on("PUT", Self.followPath, .ok)
        server.transport.on("DELETE", Self.followPath, .ok)
        return server
    }

    func started(_ server: MockServer) async -> ServerSession {
        let session = server.session(pageSize: 10)
        session.collapsedThreads = true
        await session.start()
        await session.selectTeam("t1", channelId: "c-town")
        return session
    }

    @Test func defaultFollowingComesFromAuthorshipAndParticipation() async {
        let session = await started(server())
        #expect(session.isFollowing(threadId: "root") == false)
        #expect(session.isFollowing(threadId: "missing") == false)
        session.posts["root"]?.participantIds.append("me1")
        #expect(session.isFollowing(threadId: "root"))
        session.posts["root"]?.participantIds = []
        session.posts["root"]?.userId = "me1"
        #expect(session.isFollowing(threadId: "root"))
        session.posts["root"]?.isFollowing = false
        #expect(session.isFollowing(threadId: "root") == false)
        session.stop()
    }

    @Test func serverFlagWinsOverDefault() async {
        let session = await started(server(rootFollowing: true))
        #expect(session.posts["root"]?.isFollowing == true)
        #expect(session.isFollowing(threadId: "root"))
        session.stop()
    }

    @Test func togglingFollowCallsServerOptimistically() async {
        let server = server()
        let session = await started(server)
        await session.setFollowing(threadId: "root", true)
        #expect(session.isFollowing(threadId: "root"))
        #expect(server.transport.count("PUT", Self.followPath) == 1)
        await session.setFollowing(threadId: "root", false)
        #expect(session.isFollowing(threadId: "root") == false)
        #expect(server.transport.count("DELETE", Self.followPath) == 1)
        session.stop()
    }

    @Test func failedToggleRevertsAndReports() async {
        let server = server(rootFollowing: true)
        server.transport.on("DELETE", Self.followPath, .error(500, message: "nope"))
        let session = await started(server)
        await session.setFollowing(threadId: "root", false)
        #expect(session.posts["root"]?.isFollowing == true)
        #expect(session.lastError == "nope")
        session.stop()
    }

    @Test func toggleIgnoresRepliesUnknownAndPendingPosts() async {
        let server = server()
        let session = await started(server)
        await session.setFollowing(threadId: "reply1", true)
        await session.setFollowing(threadId: "missing", true)
        session.posts["pending"] = Post(id: "pending", userId: "me1", channelId: "c-town", message: "x", pendingPostId: "pending")
        session.pendingPostIds.insert("pending")
        await session.setFollowing(threadId: "pending", true)
        let followRequests = server.transport.requests.compactMap(\.url).filter { $0.path.hasSuffix("/following") }
        #expect(followRequests.isEmpty)
        session.stop()
    }

    @Test func directMessageThreadsUseCurrentTeam() async {
        let server = server()
        server.transport.on("PUT", "users/me1/teams/t1/threads/dm-root/following", .ok)
        let session = await started(server)
        session.posts["dm-root"] = Post(id: "dm-root", userId: "u2", channelId: "c-dm", message: "hi")
        await session.setFollowing(threadId: "dm-root", true)
        #expect(server.transport.count("PUT", "users/me1/teams/t1/threads/dm-root/following") == 1)
        #expect(session.threadTeamId(Post(id: "x", userId: "u", channelId: "c-dev", message: "")) == "t1")
        session.stop()
    }

    @Test func followChangedEventUpdatesState() async {
        let session = await started(server())
        session.apply(Fixtures.wsEvent("thread_follow_changed", data: ["thread_id": "root", "state": true, "reply_count": 1], user: "me1"))
        #expect(session.posts["root"]?.isFollowing == true)
        session.apply(Fixtures.wsEvent("thread_follow_changed", data: ["thread_id": "root", "state": false], user: "me1"))
        #expect(session.posts["root"]?.isFollowing == false)
        session.apply(Fixtures.wsEvent("thread_follow_changed", data: ["thread_id": "root"], user: "me1"))
        session.apply(Fixtures.wsEvent("thread_follow_changed", data: ["thread_id": "unknown", "state": true], user: "me1"))
        #expect(session.posts["root"]?.isFollowing == false)
        #expect(session.posts["unknown"] == nil)
        session.stop()
    }

    @Test func followersInPostedEventMarkThreadFollowed() async {
        let session = await started(server())
        let plain = Fixtures.posted(Fixtures.post("r2", channel: "c-town", user: "u2", message: "plain", createAt: 300, rootId: "root"))
        session.apply(plain)
        #expect(session.posts["root"]?.isFollowing == nil)
        var mention = Fixtures.posted(Fixtures.post("r3", channel: "c-town", user: "u2", message: "@all look", createAt: 310, rootId: "root"), mentions: ["me1"]).data
        mention["followers"] = .string(Fixtures.json(["me1"]))
        session.apply(WebSocketEvent(event: "posted", data: mention, broadcast: WebSocketBroadcast(channelId: "c-town"), seq: 2))
        #expect(session.posts["root"]?.isFollowing == true)
        session.stop()
    }

    @Test func followersListWithoutMeDoesNotFollowEvenIfMentioned() async {
        let session = await started(server())
        var data = Fixtures.posted(Fixtures.post("r2", channel: "c-town", user: "u2", message: "@all", createAt: 300, rootId: "root"), mentions: ["me1"]).data
        data["followers"] = .string(Fixtures.json(["u3"]))
        session.apply(WebSocketEvent(event: "posted", data: data, broadcast: WebSocketBroadcast(channelId: "c-town"), seq: 2))
        #expect(session.posts["root"]?.isFollowing == nil)
        session.stop()
    }

    @Test func mentionWithoutFollowersListFallsBackToFollowing() async {
        let session = await started(server())
        session.apply(Fixtures.posted(Fixtures.post("r2", channel: "c-town", user: "u2", message: "hey @alice", createAt: 300, rootId: "root"), mentions: ["me1"]))
        #expect(session.posts["root"]?.isFollowing == true)
        session.stop()
    }

    @Test func ownRepliesFollowThread() async {
        let server = server(rootFollowing: false)
        server.acceptPosts()
        let session = await started(server)
        session.apply(Fixtures.posted(Fixtures.post("r2", channel: "c-town", user: "me1", message: "mine", createAt: 300, rootId: "root")))
        #expect(session.posts["root"]?.isFollowing == true)
        session.posts["root"]?.isFollowing = false
        #expect(await session.send("composer reply", channelId: "c-town", rootId: "root"))
        #expect(session.posts["root"]?.isFollowing == true)
        session.stop()
    }

    @Test func openingThreadRequestsCollapsedPayload() async throws {
        let server = server()
        let session = await started(server)
        await session.openThread(rootId: "root")
        #expect(try #require(server.transport.last("GET", "posts/root/thread")).query["collapsedThreads"] == "true")
        session.collapsedThreads = false
        await session.openThread(rootId: "root")
        #expect(try #require(server.transport.last("GET", "posts/root/thread")).query["collapsedThreads"] == nil)
        session.stop()
    }
}

@MainActor
@Suite struct PresenceSessionTests {
    @Test func watchedUsersCoverMeDirectPartnersAuthorsAndThreads() async {
        let server = MockServer(pageSize: 10)
        server.setPosts("c-town", [
            Fixtures.post("a", channel: "c-town", user: "u2", message: "a", createAt: 1),
            Fixtures.post("hook", channel: "c-town", user: "u9", message: "hook", createAt: 2, props: ["from_webhook": "true", "override_username": "ci"]),
        ])
        let session = server.session(pageSize: 10)
        await session.start()
        await session.selectTeam("t1", channelId: "c-town")
        session.threads["t"] = ThreadState(rootId: "t")
        session.threads["t"]?.postIds = ["x"]
        session.posts["x"] = Post(id: "x", userId: "u5", channelId: "c-dev", message: "x")
        #expect(session.watchedUserIds == ["me1", "u2", "u5"])
        session.presenceBatchLimit = 2
        #expect(session.watchedUserIds == ["me1", "u2"])
        session.presenceRecentPostLimit = 0
        session.presenceBatchLimit = 200
        #expect(session.watchedUserIds == ["me1", "u2", "u5"])
        session.stop()
    }

    @Test func refreshPresenceRequestsWatchedUsersAndKeepsUnchangedValues() async throws {
        let server = MockServer()
        let session = await server.startedSession()
        server.transport.reset()
        session.statuses["u2"] = .away
        await session.refreshPresence()
        let body = try #require(server.transport.last("POST", "users/status/ids")?.jsonBody as? [String])
        #expect(body.contains("me1") && body.contains("u2"))
        #expect(session.statuses["u2"] == .online)
        #expect(session.statuses["me1"] == .online)
        session.stop()
    }

    @Test func presenceIsSkippedWhenServerDisablesStatuses() async {
        let server = MockServer()
        let session = await server.startedSession()
        session.config = ClientConfig(values: ["EnableUserStatuses": "false"])
        server.transport.reset()
        await session.refreshPresence()
        await session.refreshMissingStatuses(["u7"])
        #expect(server.transport.count("POST", "users/status/ids") == 0)
        session.stop()
    }

    @Test func missingStatusesAreFetchedOnce() async throws {
        let server = MockServer()
        let session = await server.startedSession()
        server.transport.reset()
        await session.refreshMissingStatuses(["u2", "u7", ""])
        let body = try #require(server.transport.last("POST", "users/status/ids")?.jsonBody as? [String])
        #expect(body == ["u7"])
        #expect(session.statuses["u7"] == .online)
        await session.refreshMissingStatuses(["u7"])
        #expect(server.transport.count("POST", "users/status/ids") == 1)
        session.stop()
    }

    @Test func ingestedAuthorsGetStatuses() async {
        let server = MockServer()
        server.setPosts("c-dev", [Fixtures.post("d1", channel: "c-dev", user: "u8", message: "hi", createAt: 1)])
        let session = await server.startedSession()
        await session.selectChannel("c-dev")
        #expect(await eventually { session.statuses["u8"] == .online })
        session.stop()
    }

    @Test func ownStatusIsLoadedWithTeam() async {
        let session = await MockServer().startedSession()
        #expect(session.statuses["me1"] == .online)
        session.stop()
    }

    @Test func periodicRefreshRunsOnlyWhileActive() async {
        let server = MockServer()
        let session = server.session()
        session.presenceInterval = .milliseconds(20)
        var active = false
        session.isAppActive = { active }
        await session.start()
        server.transport.reset()
        try? await Task.sleep(for: .milliseconds(120))
        #expect(server.transport.count("POST", "users/status/ids") == 0)
        active = true
        #expect(await eventually { server.transport.count("POST", "users/status/ids") >= 2 })
        session.stop()
        #expect(session.presenceTask == nil)
        let settled = server.transport.count("POST", "users/status/ids")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(server.transport.count("POST", "users/status/ids") <= settled + 1)
    }

    @Test func startingTwiceKeepsSinglePresenceLoop() async {
        let session = await MockServer().startedSession()
        let task = session.presenceTask
        #expect(task != nil)
        session.startPresence()
        #expect(session.presenceTask == task)
        session.stop()
    }

    @Test func postingMarksAuthorOnlineButKeepsDoNotDisturb() async {
        let session = await MockServer().startedSession()
        session.statuses["u2"] = .away
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-town", user: "u2", message: "hi", createAt: 2000)))
        #expect(session.statuses["u2"] == .online)
        session.statuses["u3"] = .dnd
        session.apply(Fixtures.posted(Fixtures.post("n2", channel: "c-town", user: "u3", message: "hi", createAt: 2001)))
        #expect(session.statuses["u3"] == .dnd)
        session.statuses["me1"] = .away
        session.apply(Fixtures.posted(Fixtures.post("n3", channel: "c-town", user: "me1", message: "hi", createAt: 2002)))
        #expect(session.statuses["me1"] == .away)
        session.statuses["u2"] = .offline
        var quiet = Fixtures.posted(Fixtures.post("n4", channel: "c-town", user: "u2", message: "hi", createAt: 2003)).data
        quiet["set_online"] = .bool(false)
        session.apply(WebSocketEvent(event: "posted", data: quiet, broadcast: WebSocketBroadcast(channelId: "c-town"), seq: 3))
        #expect(session.statuses["u2"] == .offline)
        session.stop()
    }

    @Test func appModelRefreshesSelectedConnectedSession() async {
        let harness = AppHarness()
        let app = harness.model()
        let session = app.makeSession(for: app.servers[0])
        await app.refreshSelectedPresence()
        #expect(harness.server.transport.count("POST", "users/status/ids") == 0)
        session.connection = .connected
        session.me = User(id: "me1", username: "alice")
        await app.refreshSelectedPresence()
        #expect(harness.server.transport.count("POST", "users/status/ids") == 1)
    }
}
