import Foundation
import Testing
@testable import BoltunKit

@MainActor
@Suite struct ServerSessionPostedTests {
    func started(active: Bool = true) async -> (MockServer, ServerSession, NotificationBox) {
        let server = MockServer()
        let session = await server.startedSession()
        let box = NotificationBox()
        session.onNotification = { box.items.append($0) }
        session.isAppActive = { active }
        return (server, session, box)
    }

    @Test func mentionInOtherChannelBumpsCountersAndNotifies() async throws {
        let (_, session, box) = await started()
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-dev", user: "u2", message: "hey @alice\nlook", createAt: 1000), channelDisplayName: "Development", mentions: ["me1"]))
        #expect(session.channels["c-dev"]?.totalMsgCount == 4)
        #expect(session.channels["c-dev"]?.lastPostAt == 1000)
        #expect(session.members["c-dev"]?.mentionCount == 2)
        #expect(session.unread(channelId: "c-dev") == ChannelUnread(unread: true, mentions: 2))
        let note = try #require(box.items.first)
        #expect(note.title == "Development")
        #expect(note.body == "bob: hey @alice look")
        #expect(note.teamId == "t1")
        #expect(note.channelId == "c-dev")
        #expect(note.postId == "n1")
        #expect(note.rootId == "")
        #expect(note.serverId == session.serverId)
        session.stop()
    }

    @Test func plainMessageInOtherChannelIsUnreadWithoutNotification() async {
        let (_, session, box) = await started()
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-dev", user: "u2", message: "fyi", createAt: 1000, rootId: "x")))
        #expect(session.members["c-dev"]?.mentionCount == 1)
        #expect(session.channels["c-dev"]?.totalMsgCountRoot == 3)
        #expect(box.items.isEmpty)
        session.stop()
    }

    @Test func directMessageNotifiesWithSenderTitle() async throws {
        let (_, session, box) = await started()
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-dm", user: "u2", message: "", createAt: 1000), channelType: "D", sender: "bob", team: ""))
        #expect(session.members["c-dm"]?.mentionCount == 1)
        #expect(session.members["c-dm"]?.mentionCountRoot == 1)
        let note = try #require(box.items.first)
        #expect(note.title == "bob")
        #expect(note.body == "Sent an attachment")
        #expect(note.teamId == "t1")
        session.stop()
    }

    @Test func groupMessageUsesChannelTitle() async throws {
        let (_, session, box) = await started()
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-gm", user: "u3", message: "hi all", createAt: 1000), channelType: "G", sender: "", team: ""))
        let note = try #require(box.items.first)
        #expect(note.title == "alice, bob, carol")
        #expect(note.body.hasSuffix(": hi all"))
        session.stop()
    }

    @Test func messageInViewedChannelMarksItViewed() async {
        let (server, session, box) = await started()
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-town", user: "u2", message: "@alice hi", createAt: 1000), mentions: ["me1"]))
        #expect(await eventually { server.viewedChannels == ["c-town", "c-town"] })
        #expect(session.members["c-town"]?.mentionCount == 0)
        #expect(session.members["c-town"]?.msgCount == 6)
        #expect(session.timelinePosts(channelId: "c-town").last?.id == "n1")
        #expect(box.items.isEmpty)
        session.stop()
    }

    @Test func messageInSelectedChannelWhileInactiveNotifies() async {
        let (server, session, box) = await started(active: false)
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-town", user: "u2", message: "@alice hi", createAt: 1000), mentions: ["me1"]))
        #expect(session.members["c-town"]?.mentionCount == 1)
        #expect(box.items.count == 1)
        await settle()
        #expect(server.viewedChannels == ["c-town"])
        session.stop()
    }

    @Test func ownPostFromAnotherDeviceSyncsCounters() async {
        let (_, session, box) = await started()
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-dev", user: "me1", message: "from phone", createAt: 1000), sender: "@alice"))
        #expect(session.members["c-dev"]?.msgCount == 4)
        #expect(session.unread(channelId: "c-dev").unread == false)
        #expect(box.items.isEmpty)
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-dev", user: "me1", message: "from phone", createAt: 1000), sender: "@alice"))
        #expect(session.channels["c-dev"]?.totalMsgCount == 4)
        session.stop()
    }

    @Test func messageInUnloadedTeamUpdatesTeamUnreadAndNotifies() async throws {
        let (server, session, box) = await started()
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-beta", user: "u2", message: "@alice beta", createAt: 1000), channelDisplayName: "Beta Square", team: "t2", mentions: ["me1"]))
        #expect(session.teamUnreads["t2"]?.msgCount == 5)
        #expect(session.teamUnreads["t2"]?.mentionCount == 3)
        #expect(session.teamUnread(teamId: "t2") == ChannelUnread(unread: true, mentions: 3))
        #expect(await eventually { box.items.count == 1 })
        let note = try #require(box.items.first)
        #expect(note.title == "Beta Square")
        #expect(note.teamId == "t2")
        session.apply(Fixtures.posted(Fixtures.post("n2", channel: "c-beta2", user: "u2", message: "new team", createAt: 1001, rootId: "n1"), team: "t9"))
        #expect(session.teamUnreads["t9"] == TeamUnread(teamId: "t9", msgCount: 1))
        await settle()
        #expect(server.transport.count("GET", "channels/c-beta") == 1)
        #expect(box.items.count == 1)
        session.stop()
    }

    @Test func messageInUnknownChannelOfLoadedTeamRefreshesChannel() async {
        let (server, session, _) = await started()
        server.transport.on("GET", "channels/c-new", object: Fixtures.channel("c-new", team: "t1", name: "new", display: "New", total: 1))
        server.transport.on("GET", "channels/c-new/members/me", object: Fixtures.member("c-new", user: "me1"))
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-new", user: "u2", message: "welcome", createAt: 1000)))
        #expect(await eventually { session.channels["c-new"] != nil && session.members["c-new"] != nil })
        #expect(session.unread(channelId: "c-new").unread)
        #expect(await eventually { server.transport.count("GET", "users/me/teams/t1/channels/categories") == 2 })
        session.stop()
    }

    @Test func notificationRespectsDoNotDisturbAndMutes() async {
        let (_, session, box) = await started()
        session.statuses["me1"] = .dnd
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-dm", user: "u2", message: "hi", createAt: 1000), channelType: "D", team: ""))
        #expect(box.items.isEmpty)
        session.statuses["me1"] = .online
        session.members["c-dev"]?.notifyProps["mark_unread"] = "mention"
        session.apply(Fixtures.posted(Fixtures.post("n2", channel: "c-dev", user: "u2", message: "@channel", createAt: 1001), mentions: ["me1"]))
        #expect(box.items.isEmpty)
        #expect(session.members["c-dev"]?.mentionCount == 2)
        session.apply(Fixtures.posted(Fixtures.post("n3", channel: "c-dev", user: "u2", message: "@alice", createAt: 1002), mentions: ["me1"]))
        #expect(box.items.map(\.postId) == ["n3"])
        session.stop()
    }

    @Test func malformedPostedEventIsIgnored() async {
        let (_, session, _) = await started()
        session.apply(Fixtures.wsEvent("posted", data: ["post": "{broken"], channel: "c-town"))
        #expect(session.timelinePosts(channelId: "c-town").count == 3)
        session.stop()
    }
}

final class NotificationBox {
    var items: [MentionNotification] = []
}

@MainActor
@Suite struct ServerSessionEventTests {
    @Test func postEditedKeepsReactionsAndIgnoresStaleUpdates() async {
        let server = MockServer()
        server.setPosts("c-town", [Fixtures.post("p5", channel: "c-town", user: "me1", message: "orig", createAt: 500, reactions: [Fixtures.reaction(user: "u2", post: "p5", emoji: "tada")])])
        let session = await server.startedSession()
        session.apply(Fixtures.wsEvent("post_edited", data: ["post": Fixtures.json(Fixtures.post("p5", channel: "c-town", user: "me1", message: "edited", createAt: 500, updateAt: 700))], channel: "c-town"))
        #expect(session.posts["p5"]?.message == "edited")
        #expect(session.posts["p5"]?.metadata.reactions.count == 1)
        session.apply(Fixtures.wsEvent("post_edited", data: ["post": Fixtures.json(Fixtures.post("p5", channel: "c-town", user: "me1", message: "stale", createAt: 500, updateAt: 600))], channel: "c-town"))
        #expect(session.posts["p5"]?.message == "edited")
        session.apply(Fixtures.wsEvent("post_edited", data: ["post": Fixtures.json(Fixtures.post("zz", channel: "c-unloaded", user: "u2", message: "x", createAt: 1))]))
        #expect(session.posts["zz"] == nil)
        session.apply(Fixtures.wsEvent("post_edited", data: ["post": Fixtures.json(Fixtures.post("old", channel: "c-town", user: "u2", message: "x", createAt: 1))]))
        #expect(session.posts["old"] != nil)
        session.stop()
    }

    @Test func postDeletedRemovesUnknownRootReplies() async {
        let server = MockServer()
        let session = await server.startedSession()
        session.apply(Fixtures.posted(Fixtures.post("r9", channel: "c-town", user: "u2", message: "reply to old root", createAt: 900, rootId: "old-root")))
        #expect(session.timelinePosts(channelId: "c-town").last?.id == "r9")
        session.apply(Fixtures.wsEvent("post_deleted", data: ["post": Fixtures.json(Fixtures.post("old-root", channel: "c-town", user: "u2", message: "", createAt: 10, deleteAt: 99))], channel: "c-town"))
        #expect(session.posts["r9"] == nil)
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["p3", "p4", "p5"])
        session.stop()
    }

    @Test func reactionEvents() async {
        let server = MockServer()
        let session = await server.startedSession()
        let reaction = Fixtures.json(Fixtures.reaction(user: "u2", post: "p5", emoji: "+1"))
        session.apply(Fixtures.wsEvent("reaction_added", data: ["reaction": reaction], channel: "c-town"))
        #expect(session.posts["p5"]?.reactionSummary.first?.userIds == ["u2"])
        session.apply(Fixtures.wsEvent("reaction_removed", data: ["reaction": reaction], channel: "c-town"))
        #expect(session.posts["p5"]?.metadata.reactions.isEmpty == true)
        session.apply(Fixtures.wsEvent("reaction_added", data: ["reaction": Fixtures.json(Fixtures.reaction(user: "u2", post: "nope", emoji: "+1"))]))
        session.stop()
    }

    @Test func reactionFromUnknownUserLoadsTheirProfile() async {
        let server = MockServer()
        server.users([Fixtures.user("u9", "dave", first: "Dave")])
        let session = await server.startedSession()
        #expect(session.users["u9"] == nil)
        session.apply(Fixtures.wsEvent("reaction_added", data: ["reaction": Fixtures.json(Fixtures.reaction(user: "u9", post: "p5", emoji: "tada"))], channel: "c-town"))
        #expect(await eventually { session.users["u9"]?.username == "dave" })
        let lookups = server.transport.count("POST", "users/ids")
        session.apply(Fixtures.wsEvent("reaction_removed", data: ["reaction": Fixtures.json(Fixtures.reaction(user: "u9", post: "p5", emoji: "tada"))], channel: "c-town"))
        session.apply(Fixtures.wsEvent("reaction_added", data: ["reaction": Fixtures.json(Fixtures.reaction(user: "u9", post: "p5", emoji: "+1"))], channel: "c-town"))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(server.transport.count("POST", "users/ids") == lookups)
        session.stop()
    }

    @Test func viewedEventsClearUnread() async {
        let server = MockServer()
        let session = await server.startedSession()
        session.apply(Fixtures.wsEvent("channel_viewed", data: ["channel_id": "c-dev"], user: "me1"))
        #expect(session.unread(channelId: "c-dev") == .none)
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-dm", user: "u2", message: "hi", createAt: 1000), channelType: "D", team: ""))
        #expect(session.unread(channelId: "c-dm").unread)
        session.apply(Fixtures.wsEvent("multiple_channels_viewed", data: ["channel_times": ["c-dm": 1000, "c-elsewhere": 5]], user: "me1"))
        #expect(session.unread(channelId: "c-dm") == .none)
        #expect(await eventually { server.transport.count("GET", "users/me/teams/unread") == 2 })
        session.stop()
    }

    @Test func postUnreadRestoresCounters() async {
        let server = MockServer()
        let session = await server.startedSession()
        session.apply(Fixtures.wsEvent("post_unread", data: ["msg_count": 2, "msg_count_root": 2, "mention_count": 1, "mention_count_root": 1, "urgent_mention_count": 0, "last_viewed_at": 299, "post_id": "p3"], channel: "c-town", team: "t1", user: "me1"))
        #expect(session.members["c-town"]?.msgCount == 2)
        #expect(session.members["c-town"]?.lastViewedAt == 299)
        #expect(session.unread(channelId: "c-town") == ChannelUnread(unread: true, mentions: 1))
        session.apply(Fixtures.wsEvent("post_unread", data: ["msg_count": 2], channel: "c-unknown"))
        session.stop()
    }

    @Test func channelLifecycleEvents() async {
        let server = MockServer()
        server.transport.on("GET", "channels/c-new", object: Fixtures.channel("c-new", team: "", type: "D", name: "me1__u3"))
        server.transport.on("GET", "channels/c-new/members/me", object: Fixtures.member("c-new", user: "me1"))
        let session = await server.startedSession()
        session.apply(Fixtures.wsEvent("direct_added", data: ["teammate_id": "u3"], channel: "c-new"))
        #expect(await eventually { session.members["c-new"] != nil })
        #expect(await eventually { session.users["u3"] != nil })
        session.apply(Fixtures.wsEvent("channel_updated", data: ["channel": Fixtures.json(Fixtures.channel("c-dev", team: "t1", name: "dev", display: "Dev Renamed", total: 3))], channel: "c-dev"))
        #expect(session.channels["c-dev"]?.displayName == "Dev Renamed")
        server.transport.on("GET", "channels/c-dev", object: Fixtures.channel("c-dev", team: "t1", name: "dev", display: "Fetched", total: 3))
        server.transport.on("GET", "channels/c-dev/members/me", object: Fixtures.member("c-dev", user: "me1", msgCount: 3))
        session.apply(Fixtures.wsEvent("channel_updated", channel: "c-dev"))
        #expect(await eventually { session.channels["c-dev"]?.displayName == "Fetched" })
        session.apply(Fixtures.wsEvent("channel_deleted", data: ["channel_id": "c-dev", "delete_at": 12345], channel: "c-dev"))
        #expect(session.channels["c-dev"]?.deleteAt == 12345)
        #expect(session.sidebar[1].channelIds == ["c-town"])
        session.now = { Date(timeIntervalSince1970: 2) }
        session.apply(Fixtures.wsEvent("channel_deleted", data: ["channel_id": "c-town"], channel: "c-town"))
        #expect(session.channels["c-town"]?.deleteAt == 2000)
        #expect(session.sidebar[1].channelIds == ["c-town"])
        session.apply(Fixtures.wsEvent("channel_created", data: ["channel_id": "", "team_id": "t1"]))
        session.stop()
    }

    @Test func membershipEvents() async {
        let server = MockServer()
        server.transport.on("GET", "channels/c-added", object: Fixtures.channel("c-added", team: "t1", name: "added"))
        server.transport.on("GET", "channels/c-added/members/me", object: Fixtures.member("c-added", user: "me1"))
        let session = await server.startedSession()
        session.apply(Fixtures.wsEvent("channel_member_updated", data: ["channelMember": Fixtures.json(Fixtures.member("c-dev", user: "me1", msgCount: 3, desktop: "all"))], user: "me1"))
        #expect(session.members["c-dev"]?.desktopNotifyLevel == "all")
        session.apply(Fixtures.wsEvent("channel_member_updated", data: ["channelMember": Fixtures.json(Fixtures.member("c-dev", user: "u2", desktop: "none"))]))
        #expect(session.members["c-dev"]?.desktopNotifyLevel == "all")
        session.apply(Fixtures.wsEvent("user_added", data: ["user_id": "u2", "team_id": "t1"], channel: "c-added"))
        await settle()
        #expect(session.members["c-added"] == nil)
        session.apply(Fixtures.wsEvent("user_added", data: ["user_id": "me1", "team_id": "t1"], channel: "c-added"))
        #expect(await eventually { session.members["c-added"] != nil })
        session.apply(Fixtures.wsEvent("user_removed", data: ["user_id": "u2", "remover_id": "u3"], channel: "c-town"))
        #expect(session.members["c-town"] != nil)
        session.apply(Fixtures.wsEvent("user_removed", data: ["channel_id": "c-town", "remover_id": "u3"], user: "me1"))
        #expect(session.members["c-town"] == nil)
        #expect(session.categories["t1"]?.contains { $0.channelIds.contains("c-town") } == false)
        #expect(await eventually { session.currentChannelId == "c-added" || session.currentChannelId == "c-dev" })
        session.stop()
    }

    @Test func userAndStatusEvents() async {
        let server = MockServer()
        let session = await server.startedSession()
        session.apply(Fixtures.wsEvent("user_updated", data: ["user": Fixtures.user("u2", "robert")]))
        #expect(session.users["u2"]?.username == "robert")
        session.apply(Fixtures.wsEvent("user_updated", data: ["user": Fixtures.user("me1", "alice2")]))
        #expect(session.me?.username == "alice2")
        session.apply(Fixtures.wsEvent("status_change", data: ["user_id": "u2", "status": "away"]))
        #expect(session.statuses["u2"] == .away)
        session.apply(Fixtures.wsEvent("status_change", data: ["user_id": "u2", "status": "weird"]))
        #expect(session.statuses["u2"] == .away)
        session.apply(Fixtures.wsEvent("emoji_added", data: ["emoji": Fixtures.json(["id": "e9", "name": "blob", "creator_id": "u2"])]))
        #expect(session.customEmojis["blob"]?.id == "e9")
        session.apply(Fixtures.wsEvent("something_new", data: ["x": 1]))
        session.stop()
    }

    @Test func teamEvents() async {
        let server = MockServer()
        let session = await server.startedSession()
        session.apply(Fixtures.wsEvent("update_team", data: ["team": Fixtures.json(Fixtures.team("t2", "beta", display: "Aardvark"))], team: "t2"))
        #expect(session.teams.map(\.displayName) == ["Aardvark", "Alpha"])
        session.apply(Fixtures.wsEvent("update_team", data: ["team": Fixtures.json(Fixtures.team("t9", "x", display: "X"))]))
        #expect(session.teams.count == 2)
        session.apply(Fixtures.wsEvent("leave_team", data: ["user_id": "u2", "team_id": "t1"], team: "t1"))
        await settle()
        #expect(server.transport.count("GET", "users/me/teams") == 1)
        server.transport.on("GET", "users/me/teams", object: [Fixtures.team("t1", "alpha", display: "Alpha"), Fixtures.team("t4", "delta", display: "Delta")])
        session.apply(Fixtures.wsEvent("added_to_team", data: ["team_id": "t4", "user_id": "me1"], user: "me1"))
        #expect(await eventually { session.teams.map(\.id) == ["t1", "t4"] })
        server.transport.on("GET", "users/me/teams", object: [Fixtures.team("t2", "beta", display: "beta")])
        session.apply(Fixtures.wsEvent("leave_team", data: ["user_id": "me1", "team_id": "t1"], user: "me1"))
        #expect(await eventually { session.currentTeamId == "t2" && session.currentChannelId == "c-beta" })
        server.transport.on("GET", "users/me/teams", object: [])
        var selections: [String] = []
        session.onSelectionChange = { selections.append("\($0 ?? "-")/\($1 ?? "-")") }
        session.apply(Fixtures.wsEvent("leave_team", data: ["user_id": "me1", "team_id": "t2"], user: "me1"))
        #expect(await eventually { session.currentTeamId == nil })
        #expect(session.currentChannelId == nil)
        #expect(selections == ["-/-"])
        session.stop()
    }

    @Test func categoryEventsRefreshLoadedTeamsOnly() async {
        let server = MockServer()
        let session = await server.startedSession()
        session.apply(Fixtures.wsEvent("sidebar_category_updated", data: ["updatedCategories": "[]"], team: "t1", user: "me1"))
        session.apply(Fixtures.wsEvent("sidebar_category_order_updated", data: ["team_id": "t1", "order": "[]"], user: "me1"))
        session.apply(Fixtures.wsEvent("sidebar_category_created", data: ["category_id": "x"], team: "t2", user: "me1"))
        #expect(await eventually { server.transport.count("GET", "users/me/teams/t1/channels/categories") == 3 })
        await settle()
        #expect(server.transport.count("GET", "users/me/teams/t2/channels/categories") == 0)
        session.stop()
    }
}

@MainActor
@Suite struct ServerSessionConnectionTests {
    @Test func midSessionUnauthorizedFlipsStateOnce() async {
        let server = MockServer()
        let session = await server.startedSession()
        var calls = 0
        session.onUnauthorized = { calls += 1 }
        #expect(await eventually { server.connector.sockets.count == 1 })
        server.transport.on("GET", "channels/c-dev/posts", .error(401, id: "api.context.session_expired.app_error"))
        await session.selectChannel("c-dev")
        #expect(session.connection == .unauthorized)
        #expect(calls == 1)
        #expect(session.lastError == nil)
        #expect(await eventually { server.connector.socket(0)?.isClosed == true })
        server.transport.on("PUT", "users/me1/status", .error(401))
        await session.setStatus(.away)
        #expect(calls == 1)
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-dev", user: "u2", message: "x", createAt: 1)))
        await session.handle(realtime: .connected(needsResync: false))
        await session.handle(realtime: .disconnected("x"))
        #expect(session.connection == .unauthorized)
        #expect(server.transport.count("GET", "users/me") == 1)
    }

    @Test func backgroundUnauthorizedIsDetected() async {
        let server = MockServer()
        let session = await server.startedSession()
        var calls = 0
        session.onUnauthorized = { calls += 1 }
        server.transport.on("POST", "users/ids", .error(401))
        await session.ensureUsers(["zz"])
        #expect(session.connection == .unauthorized)
        #expect(calls == 1)
    }

    @Test func disconnectVerifiesSession() async throws {
        let server = MockServer()
        let session = await server.startedSession()
        var calls = 0
        session.onUnauthorized = { calls += 1 }
        #expect(await eventually { server.connector.sockets.count == 1 })
        let socket = try #require(server.connector.socket(0))
        socket.push(Fixtures.hello("conn1"))
        await settle()
        #expect(session.connection == .connected)
        socket.close()
        #expect(await eventually { session.connection == .reconnecting })
        #expect(await eventually { server.transport.count("GET", "users/me") == 2 })
        #expect(session.connection == .reconnecting)
        server.transport.on("GET", "users/me", .error(401))
        await session.handle(realtime: .disconnected("again"))
        #expect(await eventually { session.connection == .unauthorized })
        #expect(calls == 1)
    }

    @Test func reconnectWithNewConnectionResyncs() async throws {
        let server = MockServer()
        let session = await server.startedSession()
        await session.selectChannel("c-dev")
        await session.selectChannel("c-town")
        #expect(session.timelines["c-dev"]?.loaded == true)
        #expect(await eventually { server.connector.sockets.count == 1 })
        let first = try #require(server.connector.socket(0))
        first.push(Fixtures.hello("conn1"))
        await settle()
        server.addPost(Fixtures.post("p6", channel: "c-town", user: "u2", message: "missed", createAt: 600))
        session.reconnectRealtime()
        #expect(await eventually { server.connector.sockets.count == 2 })
        let second = try #require(server.connector.socket(1))
        second.push(Fixtures.hello("conn2"))
        #expect(await eventually { server.transport.count("GET", "users/me") >= 2 })
        #expect(await eventually { session.timelinePosts(channelId: "c-town").map(\.id) == ["p4", "p5", "p6"] })
        #expect(session.timelines["c-dev"]?.loaded == false)
        #expect(server.transport.count("GET", "users/me/teams/t1/channels") == 2)
        #expect(session.connection == .connected)
        second.push(Fixtures.event("posted", data: ["post": Fixtures.json(Fixtures.post("p7", channel: "c-town", user: "u2", message: "live", createAt: 700))], channel: "c-town", seq: 1))
        #expect(await eventually { session.timelinePosts(channelId: "c-town").last?.id == "p7" })
        session.stop()
    }

    @Test func resyncReloadsOpenThreads() async {
        let server = MockServer()
        server.transport.on("GET", "posts/p5/thread", object: Fixtures.postList([Fixtures.post("p5", channel: "c-town", user: "me1", message: "root", createAt: 500)]))
        let session = await server.startedSession()
        await session.openThread(rootId: "p5")
        await session.resync()
        #expect(server.transport.count("GET", "posts/p5/thread") == 2)
        server.transport.on("GET", "users/me", .error(500, message: "resync failed"))
        await session.resync()
        #expect(session.lastError == "resync failed")
        #expect(server.transport.count("GET", "posts/p5/thread") == 2)
        session.stop()
    }

    @Test func resyncHandlesRemovalFromCurrentTeam() async {
        let server = MockServer()
        let session = await server.startedSession()
        server.transport.on("GET", "users/me/teams", object: [Fixtures.team("t2", "beta", display: "beta")])
        await session.resync()
        #expect(session.currentTeamId == "t2")
        #expect(session.currentChannelId == "c-beta")
        session.stop()
    }

    @Test func resyncDropsMembershipsRemovedWhileOffline() async {
        let server = MockServer()
        let session = await server.startedSession()
        server.transport.on("GET", "users/me/teams/t1/channels", object: [
            Fixtures.channel("c-town", team: "t1", name: "town-square", display: "Town Square", total: 5, lastPostAt: 500),
            Fixtures.channel("c-dm", team: "", type: "D", name: "me1__u2", total: 2, lastPostAt: 900),
        ])
        server.transport.on("GET", "users/me/teams/t1/channels/members", object: [
            Fixtures.member("c-town", user: "me1", msgCount: 5, lastViewedAt: 500),
            Fixtures.member("c-dm", user: "me1", msgCount: 2, lastViewedAt: 900),
        ])
        await session.resync()
        #expect(session.members["c-dev"] == nil)
        #expect(session.members["c-gm"] == nil)
        #expect(session.members["c-town"] != nil)
        #expect(session.sidebar.map(\.channelIds) == [[], ["c-town"], ["c-dm"]])
        session.stop()
    }
}
