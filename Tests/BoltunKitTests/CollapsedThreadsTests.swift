import Foundation
import Testing
@testable import BoltunKit

@Suite struct CollapsedThreadsModelTests {
    @Test func postDecodesParticipantObjectsAndIds() throws {
        var raw = Fixtures.post("p1", channel: "c", user: "u1", message: "root", createAt: 1, replyCount: 2)
        raw["participants"] = [Fixtures.user("u2", "bob"), Fixtures.user("u3", "carol")]
        raw["last_reply_at"] = 50
        let post = try Fixtures.decode(Post.self, raw)
        #expect(post.participantIds == ["u2", "u3"])
        #expect(post.replyCount == 2)
        #expect(post.lastReplyAt == 50)
        raw["participants"] = ["u4"]
        #expect(try Fixtures.decode(Post.self, raw).participantIds == ["u4"])
        raw["participants"] = NSNull()
        #expect(try Fixtures.decode(Post.self, raw).participantIds.isEmpty)
        let encoded = Post(id: "x", userId: "u", channelId: "c", message: "", participantIds: ["u9"])
        let decoded = try MattermostJSON.decoder.decode(Post.self, from: MattermostJSON.encoder.encode(encoded))
        #expect(decoded.participantIds == ["u9"])
    }

    @Test func mergingKeepsThreadSummaryMissingFromNewerCopy() {
        let old = Post(id: "p", updateAt: 1, userId: "u", channelId: "c", message: "a", replyCount: 3, lastReplyAt: 40, participantIds: ["u2"])
        let bare = Post(id: "p", updateAt: 2, userId: "u", channelId: "c", message: "b")
        let merged = bare.mergingThreadSummary(from: old)
        #expect(merged.message == "b")
        #expect(merged.replyCount == 3)
        #expect(merged.lastReplyAt == 40)
        #expect(merged.participantIds == ["u2"])
        let fresh = Post(id: "p", updateAt: 3, userId: "u", channelId: "c", message: "c", replyCount: 4, lastReplyAt: 60, participantIds: ["u3"])
        let kept = fresh.mergingThreadSummary(from: old)
        #expect(kept.replyCount == 4)
        #expect(kept.lastReplyAt == 60)
        #expect(kept.participantIds == ["u3"])
    }

    @Test func appSettingsEnableCollapsedThreadsByDefault() throws {
        #expect(AppSettings().collapsedThreads)
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(legacy.collapsedThreads)
        var off = AppSettings()
        off.collapsedThreads = false
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(off)).collapsedThreads == false)
    }

    @Test func unreadUsesRootCountsWhenCollapsed() {
        let channel = Channel(id: "c", teamId: "t", name: "c", totalMsgCount: 10, totalMsgCountRoot: 4)
        let repliesOnly = ChannelMember(channelId: "c", userId: "me", msgCount: 7, msgCountRoot: 4, mentionCount: 1, mentionCountRoot: 0)
        #expect(SidebarBuilder.unread(channel: channel, member: repliesOnly) == ChannelUnread(unread: true, mentions: 1))
        #expect(SidebarBuilder.unread(channel: channel, member: repliesOnly, collapsedThreads: true) == ChannelUnread(unread: false, mentions: 1))
        let newRoot = ChannelMember(channelId: "c", userId: "me", msgCount: 7, msgCountRoot: 3)
        #expect(SidebarBuilder.unread(channel: channel, member: newRoot, collapsedThreads: true).unread)
        var muted = newRoot
        muted.notifyProps = ["mark_unread": "mention"]
        #expect(!SidebarBuilder.unread(channel: channel, member: muted, collapsedThreads: true).unread)
    }

    @Test func endpointAddsCollapsedThreadsQuery() async throws {
        let transport = FakeTransport()
        transport.on("GET", "channels/c1/posts", object: Fixtures.postList([]))
        let client = APIClient(baseURL: MockServer.baseURL, token: "t", transport: transport)
        _ = try await client.posts(channelId: "c1", page: .latest(perPage: 30), collapsedThreads: true)
        let query = try #require(transport.last("GET", "channels/c1/posts")).query
        #expect(query["collapsedThreads"] == "true")
        #expect(query["collapsedThreadsExtended"] == "false")
        #expect(query["per_page"] == "30")
        _ = try await client.posts(channelId: "c1", page: .since(5))
        let plain = try #require(transport.last("GET", "channels/c1/posts")).query
        #expect(plain["collapsedThreads"] == nil)
        #expect(plain["since"] == "5")
    }
}

@MainActor
@Suite struct CollapsedThreadsSessionTests {
    func server() -> MockServer {
        let server = MockServer(pageSize: 10)
        var root = Fixtures.post("root", channel: "c-town", user: "u2", message: "root", createAt: 100, replyCount: 2)
        root["last_reply_at"] = 300
        root["participants"] = [Fixtures.user("u3", "carol")]
        let replies = [
            Fixtures.post("reply1", channel: "c-town", user: "u3", message: "first reply", createAt: 200, rootId: "root"),
            Fixtures.post("reply2", channel: "c-town", user: "u3", message: "second reply", createAt: 300, rootId: "root"),
        ]
        server.setPosts("c-town", [root, replies[0], Fixtures.post("plain", channel: "c-town", user: "me1", message: "plain", createAt: 250), replies[1]])
        var bareRoot = root
        bareRoot["participants"] = NSNull()
        server.transport.on("GET", "posts/root/thread", object: Fixtures.postList([bareRoot] + replies))
        return server
    }

    func started(_ server: MockServer, collapsed: Bool) async -> ServerSession {
        let session = server.session(pageSize: 10)
        session.collapsedThreads = collapsed
        await session.start()
        await session.selectTeam("t1", channelId: "c-town")
        return session
    }

    @Test func collapsedTimelineRequestsAndShowsOnlyRootPosts() async throws {
        let server = server()
        let session = await started(server, collapsed: true)
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["root", "plain"])
        let query = try #require(server.transport.last("GET", "channels/c-town/posts")).query
        #expect(query["collapsedThreads"] == "true")
        #expect(session.posts["root"]?.replyCount == 2)
        #expect(session.posts["root"]?.participantIds == ["u3"])
        session.stop()
    }

    @Test func expandedTimelineKeepsRepliesInline() async throws {
        let server = server()
        let session = await started(server, collapsed: false)
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["root", "reply1", "plain", "reply2"])
        #expect(server.transport.last("GET", "channels/c-town/posts")?.query["collapsedThreads"] == nil)
        session.stop()
    }

    @Test func liveReplyUpdatesRootInsteadOfTimeline() async {
        let server = server()
        let session = await started(server, collapsed: true)
        session.apply(Fixtures.posted(Fixtures.post("reply3", channel: "c-town", user: "u2", message: "live", createAt: 400, rootId: "root")))
        #expect(session.timelines["c-town"]?.postIds.contains("reply3") == false)
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["root", "plain"])
        #expect(session.posts["root"]?.replyCount == 3)
        #expect(session.posts["root"]?.lastReplyAt == 400)
        #expect(session.posts["root"]?.participantIds == ["u3", "u2"])
        session.apply(Fixtures.posted(Fixtures.post("reply4", channel: "c-town", user: "u3", message: "again", createAt: 500, rootId: "root")))
        #expect(session.posts["root"]?.participantIds == ["u2", "u3"])
        session.apply(Fixtures.posted(Fixtures.post("new-root", channel: "c-town", user: "u2", message: "new", createAt: 600)))
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["root", "plain", "new-root"])
        session.stop()
    }

    @Test func threadReplyFromComposerStaysOutOfCollapsedTimeline() async {
        let server = server()
        server.acceptPosts()
        let session = await started(server, collapsed: true)
        await session.openThread(rootId: "root")
        #expect(session.threadPosts(rootId: "root").map(\.id) == ["root", "reply1", "reply2"])
        #expect(await session.send("my reply", channelId: "c-town", rootId: "root"))
        #expect(session.threadPosts(rootId: "root").count == 4)
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["root", "plain"])
        #expect(session.posts["root"]?.replyCount == 3)
        session.stop()
    }

    @Test func threadFetchDoesNotEraseParticipants() async {
        let server = server()
        let session = await started(server, collapsed: true)
        await session.openThread(rootId: "root")
        #expect(session.posts["root"]?.participantIds == ["u3"])
        #expect(session.posts["root"]?.replyCount == 2)
        session.stop()
    }

    @Test func editedRootKeepsThreadSummary() async {
        let server = server()
        let session = await started(server, collapsed: true)
        var edited = Fixtures.post("root", channel: "c-town", user: "u2", message: "root edited", createAt: 100, updateAt: 700)
        edited["participants"] = NSNull()
        session.apply(Fixtures.wsEvent("post_edited", data: ["post": Fixtures.json(edited)], channel: "c-town"))
        #expect(session.posts["root"]?.message == "root edited")
        #expect(session.posts["root"]?.replyCount == 2)
        #expect(session.posts["root"]?.participantIds == ["u3"])
        session.stop()
    }

    @Test func togglingModeReloadsCurrentChannelAndDropsOtherTimelines() async {
        let server = server()
        let session = await started(server, collapsed: false)
        await session.selectChannel("c-dev")
        await session.selectChannel("c-town")
        #expect(session.timelines["c-dev"] != nil)
        let viewedAt = session.timelines["c-town"]?.lastViewedAtOnOpen
        await session.setCollapsedThreads(true)
        #expect(session.collapsedThreads)
        #expect(session.timelines["c-dev"] == nil)
        #expect(session.timelines["c-town"]?.postIds == ["root", "plain"])
        #expect(session.timelines["c-town"]?.lastViewedAtOnOpen == viewedAt)
        let requests = server.transport.count("GET", "channels/c-town/posts")
        await session.setCollapsedThreads(true)
        #expect(server.transport.count("GET", "channels/c-town/posts") == requests)
        await session.setCollapsedThreads(false)
        #expect(session.timelines["c-town"]?.postIds == ["root", "reply1", "plain", "reply2"])
        session.stop()
    }

    @Test func togglingWithoutOpenChannelOnlyChangesFlag() async {
        let session = MockServer().session()
        await session.setCollapsedThreads(true)
        #expect(session.collapsedThreads)
        #expect(session.timelines.isEmpty)
    }

    @Test func replyInOtherChannelDoesNotMarkItUnreadWhenCollapsed() async {
        let server = server()
        let session = await started(server, collapsed: true)
        session.isAppActive = { true }
        #expect(session.unread(channelId: "c-dev").unread)
        session.apply(Fixtures.posted(Fixtures.post("r-town", channel: "c-dm", user: "u2", message: "reply", createAt: 1000, rootId: "x"), channelType: "D"))
        #expect(session.unread(channelId: "c-dm").unread == false)
        #expect(session.unread(channelId: "c-dm").mentions == 1)
        session.stop()
    }

    @Test func unloadedTeamUsesRootUnreadCountsWhenCollapsed() async {
        let server = MockServer()
        server.transport.on("GET", "users/me/teams/unread", object: [
            ["team_id": "t2", "msg_count": 4, "mention_count": 0, "msg_count_root": 0, "mention_count_root": 0, "thread_count": 0, "thread_mention_count": 0],
        ])
        let session = server.session()
        await session.start()
        #expect(session.teamUnread(teamId: "t2").unread)
        session.collapsedThreads = true
        #expect(session.teamUnread(teamId: "t2").unread == false)
        session.stop()
    }

    @Test func appModelAppliesSettingToSessions() async {
        let harness = AppHarness()
        let app = harness.model()
        #expect(app.settings.collapsedThreads)
        let session = app.makeSession(for: app.servers[0])
        #expect(session.collapsedThreads)
        app.settings.collapsedThreads = false
        #expect(await eventually { !session.collapsedThreads })
        #expect(harness.store.load().settings.collapsedThreads == false)
        let second = app.makeSession(for: app.servers[1])
        #expect(!second.collapsedThreads)
    }
}
