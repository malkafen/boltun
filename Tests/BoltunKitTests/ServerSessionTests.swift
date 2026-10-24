import Foundation
import Testing
@testable import BoltunKit

@MainActor
@Suite struct ServerSessionStartTests {
    @Test func startLoadsInitialStateAndConnectsRealtime() async throws {
        let server = MockServer()
        let session = server.session()
        await session.start()
        #expect(session.connection == .connected)
        #expect(session.me?.username == "alice")
        #expect(session.myId == "me1")
        #expect(session.users["me1"] != nil)
        #expect(session.config.siteName == "Example Chat")
        #expect(session.teams.map(\.id) == ["t1", "t2"])
        #expect(session.teamUnreads["t2"]?.mentionCount == 2)
        #expect(session.preferences.count == 1)
        #expect(server.transport.last("GET", "users/me")?.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(await eventually { server.connector.sockets.count == 1 })
        #expect(server.connector.urls.first?.absoluteString == "wss://chat.example.com/api/v4/websocket")
        #expect(server.connector.tokens == ["token-1"])
        #expect(await eventually { session.customEmojis["partyparrot"] != nil })
        #expect(session.currentTeam == nil)
        #expect(session.sidebar.isEmpty)
        session.stop()
        #expect(session.connection == .idle)
        #expect(await eventually { server.connector.socket(0)?.isClosed == true })
    }

    @Test func startIsIgnoredWhileConnected() async {
        let server = MockServer()
        let session = server.session()
        await session.start()
        await session.start()
        #expect(server.transport.count("GET", "users/me") == 1)
        session.stop()
    }

    @Test func startWithoutTokenIsUnauthorized() async {
        let server = MockServer()
        let session = server.session(token: nil)
        var calls = 0
        session.onUnauthorized = { calls += 1 }
        await session.start()
        #expect(session.connection == .unauthorized)
        #expect(calls == 1)
        #expect(server.transport.requests.isEmpty)
    }

    @Test func startWithExpiredTokenIsUnauthorized() async {
        let server = MockServer()
        server.transport.on("GET", "users/me", .error(401, id: "api.context.session_expired.app_error"))
        let session = server.session()
        var calls = 0
        session.onUnauthorized = { calls += 1 }
        await session.start()
        #expect(session.connection == .unauthorized)
        #expect(calls == 1)
        await settle()
        #expect(server.connector.sockets.isEmpty)
    }

    @Test func startFailureIsReported() async {
        let server = MockServer()
        server.transport.on("GET", "users/me/teams", .error(500, message: "Database down"))
        let session = server.session()
        await session.start()
        #expect(session.connection == .failed("Database down"))
        #expect(session.lastError == "Database down")
        session.clearError()
        #expect(session.lastError == nil)
        server.transport.on("GET", "users/me/teams", object: [Fixtures.team("t1", "alpha", display: "Alpha")])
        await session.start()
        #expect(session.connection == .connected)
        session.stop()
    }

    @Test func stopDuringStartPreventsConnecting() async {
        let server = MockServer()
        let gate = Gate()
        server.hold("GET", "users/me", gate: gate) { _ in .object(Fixtures.user("me1", "alice")) }
        let session = server.session()
        let task = Task { await session.start() }
        #expect(await eventually { session.connection == .connecting })
        session.stop()
        await gate.open()
        await task.value
        #expect(session.connection == .idle)
        #expect(server.connector.sockets.isEmpty)
    }

    @Test func cancelledStartReturnsToIdle() async {
        let server = MockServer()
        server.transport.on("GET", "users/me") { _ in throw URLError(.cancelled) }
        let session = server.session()
        await session.start()
        #expect(session.connection == .idle)
        #expect(session.lastError == nil)
    }

    @Test func updateTokenChangesClient() {
        let server = MockServer()
        let session = server.session()
        session.updateToken("fresh")
        #expect(session.client.token == "fresh")
    }
}

@MainActor
@Suite struct ServerSessionNavigationTests {
    @Test func selectTeamOpensTownSquareAndBuildsSidebar() async throws {
        let server = MockServer()
        let session = server.session()
        var selections: [String] = []
        session.onSelectionChange = { selections.append("\($0 ?? "-")/\($1 ?? "-")") }
        await session.start()
        await session.selectTeam("t1")
        #expect(session.currentTeamId == "t1")
        #expect(session.currentTeam?.displayName == "Alpha")
        #expect(session.currentChannelId == "c-town")
        #expect(session.currentChannel?.name == "town-square")
        #expect(selections == ["t1/c-town"])
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["p3", "p4", "p5"])
        let timeline = try #require(session.timelines["c-town"])
        #expect(timeline.loaded)
        #expect(timeline.hasMoreOlder)
        #expect(!timeline.isLoading)
        #expect(timeline.lastViewedAtOnOpen == 500)
        #expect(server.viewedChannels == ["c-town"])
        #expect(server.transport.last("POST", "channels/members/me/view")?.jsonObject["prev_channel_id"] as? String == "")
        #expect(session.users["u2"]?.username == "bob")
        #expect(session.statuses["u2"] == .online)
        #expect(session.sidebar.map(\.title) == ["Favorites", "Channels", "Direct Messages"])
        #expect(session.sidebar.map(\.channelIds) == [[], ["c-dev", "c-town"], ["c-dm", "c-gm"]])
        session.stop()
    }

    @Test func selectTeamHonoursRequestedChannel() async {
        let server = MockServer()
        let session = await server.startedSession(team: nil)
        await session.selectTeam("t1", channelId: "c-dev")
        #expect(session.currentChannelId == "c-dev")
        #expect(session.unread(channelId: "c-dev") == .none)
        #expect(session.members["c-dev"]?.msgCount == 3)
        await session.selectTeam("t2")
        #expect(session.currentChannelId == "c-beta")
        #expect(server.transport.last("POST", "channels/members/me/view")?.jsonObject["prev_channel_id"] as? String == "c-dev")
        await session.selectTeam("t1", channelId: "c-beta")
        #expect(session.currentChannelId == "c-town")
        await session.selectTeam("t1", channelId: "c-dm")
        #expect(session.currentChannelId == "c-dm")
        #expect(session.currentTeamId == "t1")
        #expect(server.transport.count("GET", "users/me/teams/t1/channels") == 1)
        session.stop()
    }

    @Test func selectUnknownTeamIsIgnored() async {
        let server = MockServer()
        let session = await server.startedSession()
        await session.selectTeam("t3")
        #expect(session.currentTeamId == "t1")
        session.stop()
    }

    @Test func selectTeamFailureIsReported() async {
        let server = MockServer()
        server.transport.on("GET", "users/me/teams/t2/channels", .error(500, message: "boom"))
        let session = await server.startedSession()
        await session.selectTeam("t2")
        #expect(session.lastError == "boom")
        #expect(session.currentChannelId == "c-town")
        session.stop()
    }

    @Test func teamWithoutChannelsClearsSelection() async {
        let server = MockServer()
        server.transport.on("GET", "users/me/teams/t2/channels", object: [])
        server.transport.on("GET", "users/me/teams/t2/channels/members", object: [])
        server.transport.on("GET", "users/me/teams/t2/channels/categories", object: Fixtures.categories([]))
        let session = server.session()
        var selections: [String] = []
        session.onSelectionChange = { selections.append("\($0 ?? "-")/\($1 ?? "-")") }
        await session.start()
        await session.selectTeam("t2")
        #expect(session.currentChannelId == nil)
        #expect(selections == ["t2/-"])
        session.stop()
    }

    @Test func selectChannelInOtherTeamSwitchesAndLoadsTeam() async {
        let server = MockServer()
        let session = await server.startedSession()
        session.channels["c-beta"] = Channel(id: "c-beta", teamId: "t2", name: "town-square")
        await session.selectChannel("c-beta")
        #expect(session.currentTeamId == "t2")
        #expect(server.transport.count("GET", "users/me/teams/t2/channels") == 1)
        #expect(session.members["c-beta"] != nil)
        session.stop()
    }

    @Test func slowResponseForPreviousChannelDoesNotMarkItViewed() async {
        let server = MockServer()
        let gate = Gate()
        server.holdPosts("c-dev", gate: gate)
        server.setPosts("c-dev", [Fixtures.post("d1", channel: "c-dev", user: "u2", message: "dev", createAt: 50)])
        let session = await server.startedSession()
        let slow = Task { await session.selectChannel("c-dev") }
        #expect(await eventually { server.transport.count("GET", "channels/c-dev/posts") == 1 })
        await session.selectChannel("c-dm")
        await gate.open()
        await slow.value
        #expect(session.currentChannelId == "c-dm")
        #expect(server.viewedChannels == ["c-town", "c-dm"])
        #expect(session.members["c-dev"]?.mentionCount == 1)
        #expect(session.timelinePosts(channelId: "c-dev").map(\.id) == ["d1"])
        session.stop()
    }

    @Test func reselectingChannelFetchesChangesSince() async throws {
        let server = MockServer()
        let session = await server.startedSession()
        await session.selectChannel("c-dev")
        server.addPost(Fixtures.post("p6", channel: "c-town", user: "u2", message: "new", createAt: 600))
        server.updatePost("p4", in: "c-town") { post in
            var post = post
            post["message"] = "edited"
            post["update_at"] = Int64(700)
            post["edit_at"] = Int64(700)
            return post
        }
        server.updatePost("p3", in: "c-town") { post in
            var post = post
            post["message"] = ""
            post["delete_at"] = Int64(800)
            post["update_at"] = Int64(800)
            return post
        }
        server.updatePost("p1", in: "c-town") { post in
            var post = post
            post["message"] = "old edit"
            post["update_at"] = Int64(900)
            return post
        }
        await session.selectChannel("c-town")
        let request = try #require(server.transport.last("GET", "channels/c-town/posts"))
        #expect(request.query == ["since": "500"])
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["p4", "p5", "p6"])
        #expect(session.posts["p4"]?.message == "edited")
        #expect(session.posts["p3"] == nil)
        #expect(session.posts["p1"]?.message == "old edit")
        await session.selectChannel("c-dev")
        await session.selectChannel("c-town")
        #expect(server.transport.last("GET", "channels/c-town/posts")?.query == ["since": "700"])
        session.stop()
    }

    @Test func emptyLoadedChannelReloadsLatest() async {
        let server = MockServer()
        let session = await server.startedSession()
        await session.selectChannel("c-dev")
        await session.selectChannel("c-town")
        await session.selectChannel("c-dev")
        #expect(server.transport.requests("GET", "channels/c-dev/posts").map(\.query) == [["page": "0", "per_page": "3"], ["page": "0", "per_page": "3"]])
        session.stop()
    }

    @Test func loadNewerFailureIsReported() async {
        let server = MockServer()
        let session = await server.startedSession()
        await session.selectChannel("c-dev")
        server.transport.on("GET", "channels/c-town/posts", .error(503, message: "unavailable"))
        await session.selectChannel("c-town")
        #expect(session.lastError == "unavailable")
        #expect(session.timelines["c-town"]?.isLoading == false)
        #expect(session.timelinePosts(channelId: "c-town").count == 3)
        session.stop()
    }

    @Test func loadOlderPaginatesUntilExhausted() async throws {
        let server = MockServer()
        let session = await server.startedSession()
        await session.loadOlder(channelId: "c-town")
        let request = try #require(server.transport.last("GET", "channels/c-town/posts"))
        #expect(request.query == ["before": "p3", "per_page": "3"])
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["p1", "p2", "p3", "p4", "p5"])
        #expect(session.timelines["c-town"]?.hasMoreOlder == false)
        await session.loadOlder(channelId: "c-town")
        await session.loadOlder(channelId: "missing")
        #expect(server.transport.count("GET", "channels/c-town/posts") == 2)
        session.stop()
    }

    @Test func loadOlderFailureKeepsTimeline() async {
        let server = MockServer()
        let session = await server.startedSession()
        server.transport.on("GET", "channels/c-town/posts", .error(500, message: "nope"))
        await session.loadOlder(channelId: "c-town")
        #expect(session.lastError == "nope")
        #expect(session.timelines["c-town"]?.isLoading == false)
        #expect(session.timelines["c-town"]?.hasMoreOlder == true)
        #expect(session.timelinePosts(channelId: "c-town").count == 3)
        session.stop()
    }

    @Test func postArrivingDuringInitialLoadIsKept() async {
        let server = MockServer()
        let gate = Gate()
        server.holdPosts("c-dev", gate: gate)
        server.setPosts("c-dev", [Fixtures.post("d1", channel: "c-dev", user: "u2", message: "older", createAt: 50)])
        let session = await server.startedSession()
        let task = Task { await session.selectChannel("c-dev") }
        #expect(await eventually { server.transport.count("GET", "channels/c-dev/posts") == 1 })
        session.apply(Fixtures.posted(Fixtures.post("live", channel: "c-dev", user: "u2", message: "live", createAt: 1000)))
        await gate.open()
        await task.value
        #expect(session.timelinePosts(channelId: "c-dev").map(\.id) == ["d1", "live"])
        session.stop()
    }

    @Test func loadLatestFailureIsReported() async {
        let server = MockServer()
        server.transport.on("GET", "channels/c-dev/posts", .error(500, message: "broken"))
        let session = await server.startedSession()
        await session.selectChannel("c-dev")
        #expect(session.lastError == "broken")
        #expect(session.timelines["c-dev"]?.loaded == false)
        #expect(session.timelines["c-dev"]?.isLoading == false)
        session.stop()
    }

    @Test func removedChannelIsNotResurrectedByLateResponse() async {
        let server = MockServer()
        let gate = Gate()
        server.holdPosts("c-dev", gate: gate)
        let session = await server.startedSession()
        let task = Task { await session.selectChannel("c-dev") }
        #expect(await eventually { server.transport.count("GET", "channels/c-dev/posts") == 1 })
        session.apply(Fixtures.wsEvent("user_removed", data: ["channel_id": "c-dev", "remover_id": "u2"], user: "me1"))
        await gate.open()
        await task.value
        #expect(session.timelines["c-dev"] == nil)
        #expect(session.members["c-dev"] == nil)
        #expect(await eventually { session.currentChannelId == "c-town" })
        session.stop()
    }

    @Test func markViewedIgnoresUnknownChannel() async {
        let server = MockServer()
        let session = await server.startedSession()
        await session.markViewed(channelId: "nope")
        #expect(server.viewedChannels == ["c-town"])
        server.transport.on("POST", "channels/members/me/view", .error(500))
        await session.markViewed(channelId: "c-dev")
        #expect(session.lastError == nil)
        #expect(session.members["c-dev"]?.mentionCount == 0)
        session.stop()
    }
}

@MainActor
@Suite struct ServerSessionPostingTests {
    @Test func sendShowsPendingPostThenConfirmedOne() async throws {
        let server = MockServer()
        let gate = Gate()
        server.acceptPosts(gate: gate)
        let session = await server.startedSession()
        let task = Task { await session.send("  indented\n\n", channelId: "c-town") }
        #expect(await eventually { server.transport.count("POST", "posts") == 1 })
        let pending = try #require(session.timelinePosts(channelId: "c-town").last)
        #expect(session.isPending(postId: pending.id))
        #expect(pending.message == "  indented")
        #expect(pending.userId == "me1")
        #expect(pending.id.hasPrefix("me1:"))
        let body = try #require(server.transport.last("POST", "posts")?.jsonObject)
        #expect(body["message"] as? String == "  indented")
        #expect(body["pending_post_id"] as? String == pending.id)
        #expect(body["channel_id"] as? String == "c-town")
        await gate.open()
        #expect(await task.value)
        #expect(session.pendingPostIds.isEmpty)
        #expect(session.posts[pending.id] == nil)
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["p3", "p4", "p5", "srv1"])
        #expect(session.channels["c-town"]?.totalMsgCount == 6)
        #expect(session.members["c-town"]?.msgCount == 6)
        #expect(session.unread(channelId: "c-town") == .none)
        session.stop()
    }

    @Test func websocketEchoBeforeResponseDoesNotDuplicate() async throws {
        let server = MockServer()
        let gate = Gate()
        server.acceptPosts(gate: gate)
        let session = await server.startedSession()
        let task = Task { await session.send("hello", channelId: "c-town") }
        #expect(await eventually { server.transport.count("POST", "posts") == 1 })
        let pendingId = try #require(server.transport.last("POST", "posts")?.jsonObject["pending_post_id"] as? String)
        session.apply(Fixtures.posted(Fixtures.post("srv1", channel: "c-town", user: "me1", message: "hello", createAt: 1001, pendingPostId: pendingId), sender: "@alice"))
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["p3", "p4", "p5", "srv1"])
        #expect(session.pendingPostIds.isEmpty)
        await gate.open()
        #expect(await task.value)
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["p3", "p4", "p5", "srv1"])
        #expect(session.channels["c-town"]?.totalMsgCount == 6)
        session.stop()
    }

    @Test func failedSendRemovesPendingPost() async {
        let server = MockServer()
        server.transport.on("POST", "posts", .error(403, message: "Channel is read-only"))
        let session = await server.startedSession()
        let sent = await session.send("hello", channelId: "c-town")
        #expect(!sent)
        #expect(session.lastError == "Channel is read-only")
        #expect(session.pendingPostIds.isEmpty)
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["p3", "p4", "p5"])
        session.stop()
    }

    @Test func blankMessagesAreNotSent() async {
        let server = MockServer()
        server.acceptPosts()
        let session = await server.startedSession()
        #expect(await session.send(" \n\t ", channelId: "c-town") == false)
        #expect(server.transport.count("POST", "posts") == 0)
        #expect(await session.send("", channelId: "c-town", fileIds: ["f1"]))
        #expect(server.transport.last("POST", "posts")?.jsonObject["file_ids"] as? [String] == ["f1"])
        session.stop()
    }

    @Test func pendingIdsAreUniqueWithinTheSameMillisecond() async throws {
        let server = MockServer()
        server.acceptPosts()
        let session = await server.startedSession()
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        session.now = { instant }
        await session.send("one", channelId: "c-town")
        await session.send("two", channelId: "c-town")
        let ids = server.transport.requests("POST", "posts").compactMap { $0.jsonObject["pending_post_id"] as? String }
        #expect(ids == ["me1:1800000000000", "me1:1800000000001"])
        session.stop()
    }

    @Test func replyInOpenThreadUpdatesThreadAndRoot() async {
        let server = MockServer()
        server.acceptPosts()
        server.transport.on("GET", "posts/p5/thread", object: Fixtures.postList([
            Fixtures.post("p5", channel: "c-town", user: "me1", message: "root", createAt: 500, replyCount: 1),
            Fixtures.post("r1", channel: "c-town", user: "u2", message: "reply", createAt: 550, rootId: "p5"),
        ]))
        let session = await server.startedSession()
        await session.openThread(rootId: "p5")
        #expect(session.threadPosts(rootId: "p5").map(\.id) == ["p5", "r1"])
        await session.send("my reply", channelId: "c-town", rootId: "p5")
        #expect(session.threadPosts(rootId: "p5").map(\.id) == ["p5", "r1", "srv1"])
        #expect(session.posts["p5"]?.replyCount == 2)
        #expect(session.posts["p5"]?.lastReplyAt == 1001)
        #expect(session.channels["c-town"]?.totalMsgCountRoot == 5)
        session.closeThread(rootId: "p5")
        #expect(session.threads["p5"] == nil)
        session.stop()
    }

    @Test func editUpdatesPost() async {
        let server = MockServer()
        server.transport.on("PUT", "posts/p5/patch", object: Fixtures.post("p5", channel: "c-town", user: "me1", message: "edited", createAt: 500, updateAt: 600))
        let session = await server.startedSession()
        #expect(await session.edit(postId: "p5", message: "edited"))
        #expect(session.posts["p5"]?.message == "edited")
        #expect(server.transport.last("PUT", "posts/p5/patch")?.jsonObject["message"] as? String == "edited")
        #expect(session.channels["c-town"]?.totalMsgCount == 5)
        server.transport.on("PUT", "posts/p5/patch", .error(403, message: "denied"))
        #expect(await session.edit(postId: "p5", message: "again") == false)
        #expect(session.lastError == "denied")
        session.stop()
    }

    @Test func deletingRootRemovesReplies() async {
        let server = MockServer()
        server.setPosts("c-town", [
            Fixtures.post("p1", channel: "c-town", user: "me1", message: "root", createAt: 100),
            Fixtures.post("r1", channel: "c-town", user: "u2", message: "reply", createAt: 200, rootId: "p1"),
            Fixtures.post("p2", channel: "c-town", user: "u2", message: "other", createAt: 300),
        ])
        server.transport.on("DELETE", "posts/p1", .ok)
        let session = await server.startedSession()
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["p1", "r1", "p2"])
        await session.delete(postId: "p1")
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["p2"])
        #expect(session.posts["r1"] == nil)
        session.apply(Fixtures.wsEvent("post_deleted", data: ["post": Fixtures.json(Fixtures.post("p1", channel: "c-town", user: "me1", message: "", createAt: 100, deleteAt: 9))], channel: "c-town"))
        #expect(session.timelinePosts(channelId: "c-town").map(\.id) == ["p2"])
        server.transport.on("DELETE", "posts/p2", .error(403, message: "denied"))
        await session.delete(postId: "p2")
        #expect(session.lastError == "denied")
        #expect(session.posts["p2"] != nil)
        session.stop()
    }

    @Test func deletingReplyDecrementsRootOnce() async {
        let server = MockServer()
        server.setPosts("c-town", [
            Fixtures.post("p1", channel: "c-town", user: "me1", message: "root", createAt: 100, replyCount: 1),
            Fixtures.post("r1", channel: "c-town", user: "me1", message: "reply", createAt: 200, rootId: "p1"),
        ])
        server.transport.on("DELETE", "posts/r1", .ok)
        let session = await server.startedSession()
        await session.delete(postId: "r1")
        #expect(session.posts["p1"]?.replyCount == 0)
        session.apply(Fixtures.wsEvent("post_deleted", data: ["post": Fixtures.json(Fixtures.post("r1", channel: "c-town", user: "me1", message: "", createAt: 200, rootId: "p1", deleteAt: 9))], channel: "c-town"))
        session.apply(Fixtures.posted(Fixtures.post("r1", channel: "c-town", user: "me1", message: "reply", createAt: 200, rootId: "p1")))
        #expect(session.posts["p1"]?.replyCount == 0)
        #expect(session.posts["r1"] == nil)
        session.stop()
    }

    @Test func toggleReactionAddsAndRemoves() async throws {
        let server = MockServer()
        server.transport.on("POST", "reactions", object: Fixtures.reaction(user: "me1", post: "p5", emoji: "smile", at: 10))
        server.transport.on("DELETE", "users/me1/posts/p5/reactions/smile", .ok)
        let session = await server.startedSession()
        await session.toggleReaction(postId: "p5", emojiName: "smile")
        #expect(session.posts["p5"]?.reactionSummary == [ReactionSummary(emojiName: "smile", userIds: ["me1"])])
        session.apply(Fixtures.wsEvent("reaction_added", data: ["reaction": Fixtures.json(Fixtures.reaction(user: "me1", post: "p5", emoji: "smile", at: 10))], channel: "c-town"))
        #expect(session.posts["p5"]?.metadata.reactions.count == 1)
        await session.toggleReaction(postId: "p5", emojiName: "smile")
        #expect(session.posts["p5"]?.metadata.reactions.isEmpty == true)
        #expect(server.transport.count("DELETE", "users/me1/posts/p5/reactions/smile") == 1)
        await session.toggleReaction(postId: "missing", emojiName: "smile")
        server.transport.on("POST", "reactions", .error(500, message: "reaction failed"))
        await session.toggleReaction(postId: "p5", emojiName: "smile")
        #expect(session.lastError == "reaction failed")
        session.stop()
    }

    @Test func pinAndUpload() async {
        let server = MockServer()
        server.transport.on("POST", "posts/p5/pin", .ok)
        server.transport.on("POST", "files", object: ["file_infos": [["id": "f1", "name": "a.txt"]]], status: 201)
        let session = await server.startedSession()
        await session.setPinned(postId: "p5", pinned: true)
        #expect(session.posts["p5"]?.isPinned == true)
        let info = await session.upload(channelId: "c-town", filename: "a.txt", data: Data("x".utf8), mimeType: "text/plain")
        #expect(info?.id == "f1")
        server.transport.on("POST", "posts/p5/unpin", .error(500, message: "pin failed"))
        await session.setPinned(postId: "p5", pinned: false)
        #expect(session.lastError == "pin failed")
        #expect(session.posts["p5"]?.isPinned == true)
        server.transport.on("POST", "files", .error(413, message: "too large"))
        #expect(await session.upload(channelId: "c-town", filename: "a", data: Data(), mimeType: "x") == nil)
        #expect(session.lastError == "too large")
        session.stop()
    }

    @Test func markUnreadMovesMarkerAndSuppressesAutoView() async {
        let server = MockServer()
        server.transport.on("POST", "users/me1/posts/p4/set_unread", object: ["team_id": "t1", "channel_id": "c-town", "msg_count": 3, "msg_count_root": 3, "mention_count": 0, "mention_count_root": 0, "urgent_mention_count": 0, "last_viewed_at": 399])
        let session = await server.startedSession()
        await session.markUnread(postId: "p4")
        #expect(session.members["c-town"]?.msgCount == 3)
        #expect(session.members["c-town"]?.lastViewedAt == 399)
        #expect(session.timelines["c-town"]?.lastViewedAtOnOpen == 399)
        #expect(session.unread(channelId: "c-town").unread)
        session.apply(Fixtures.posted(Fixtures.post("p9", channel: "c-town", user: "u2", message: "more", createAt: 900)))
        await settle()
        #expect(server.viewedChannels == ["c-town"])
        await session.selectChannel("c-town")
        #expect(server.viewedChannels == ["c-town", "c-town"])
        await session.markUnread(postId: "missing")
        server.transport.on("POST", "users/me1/posts/p4/set_unread", .error(500, message: "unread failed"))
        await session.markUnread(postId: "p4")
        #expect(session.lastError == "unread failed")
        session.stop()
    }

    @Test func openThreadMergesRepliesArrivingDuringLoad() async {
        let server = MockServer()
        let gate = Gate()
        server.hold("GET", "posts/p5/thread", gate: gate) { _ in
            .object(Fixtures.postList([
                Fixtures.post("p5", channel: "c-town", user: "me1", message: "root", createAt: 500),
                Fixtures.post("r1", channel: "c-town", user: "u2", message: "first", createAt: 550, rootId: "p5"),
            ]))
        }
        let session = await server.startedSession()
        let task = Task { await session.openThread(rootId: "p5") }
        #expect(await eventually { session.threads["p5"]?.isLoading == true && server.transport.count("GET", "posts/p5/thread") == 1 })
        session.apply(Fixtures.posted(Fixtures.post("r2", channel: "c-town", user: "u2", message: "second", createAt: 600, rootId: "p5")))
        await gate.open()
        await task.value
        #expect(session.threadPosts(rootId: "p5").map(\.id) == ["p5", "r1", "r2"])
        #expect(session.threads["p5"]?.isLoading == false)
        session.stop()
    }

    @Test func closedThreadIsNotResurrected() async {
        let server = MockServer()
        let gate = Gate()
        server.hold("GET", "posts/p5/thread", gate: gate) { _ in .object(Fixtures.postList([Fixtures.post("p5", channel: "c-town", user: "me1", message: "root", createAt: 500)])) }
        let session = await server.startedSession()
        let task = Task { await session.openThread(rootId: "p5") }
        #expect(await eventually { server.transport.count("GET", "posts/p5/thread") == 1 })
        session.closeThread(rootId: "p5")
        await gate.open()
        await task.value
        #expect(session.threads["p5"] == nil)
        server.transport.on("GET", "posts/p5/thread", .error(404, message: "gone"))
        await session.openThread(rootId: "p5")
        #expect(session.lastError == "gone")
        #expect(session.threads["p5"]?.isLoading == false)
        session.stop()
    }
}
