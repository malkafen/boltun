import Foundation
import Testing
@testable import BoltunKit

@MainActor
@Suite struct ServerSessionUnreadTests {
    @Test func unreadMathAcrossChannelsTeamsAndDirectMessages() async {
        let server = MockServer()
        let session = await server.startedSession()
        #expect(session.unread(channelId: "c-dev") == ChannelUnread(unread: true, mentions: 1))
        #expect(session.unread(channelId: "c-town") == .none)
        #expect(session.unread(channelId: "missing") == .none)
        #expect(session.teamUnread(teamId: "t1") == ChannelUnread(unread: true, mentions: 1))
        #expect(session.teamUnread(teamId: "t2") == ChannelUnread(unread: true, mentions: 2))
        #expect(session.teamUnread(teamId: "unknown") == .none)
        #expect(session.directUnread == .none)
        #expect(session.totalUnread == ChannelUnread(unread: true, mentions: 3))
        session.apply(Fixtures.posted(Fixtures.post("dm1", channel: "c-dm", user: "u2", message: "ping", createAt: 950), channelType: "D", team: ""))
        #expect(session.directUnread == ChannelUnread(unread: true, mentions: 1))
        #expect(session.totalUnread == ChannelUnread(unread: true, mentions: 4))
        session.stop()
    }

    @Test func mutedChannelCountsMentionsButNotUnread() async {
        let server = MockServer()
        server.transport.on("GET", "users/me/teams/t1/channels/members", object: [
            Fixtures.member("c-town", user: "me1", msgCount: 5),
            Fixtures.member("c-dev", user: "me1", msgCount: 1, mentions: 2, markUnread: "mention"),
        ])
        let session = await server.startedSession()
        #expect(session.unread(channelId: "c-dev") == ChannelUnread(unread: false, mentions: 2))
        #expect(session.teamUnread(teamId: "t1") == ChannelUnread(unread: false, mentions: 2))
        #expect(session.unread(channelId: "c-dm") == .none)
        session.stop()
    }
}

@MainActor
@Suite struct ServerSessionPresentationTests {
    @Test func displayNamesFollowPreferences() async {
        let server = MockServer()
        let session = await server.startedSession()
        #expect(session.nameDisplay == .username)
        #expect(session.displayName(userId: "u2") == "bob")
        #expect(session.displayName(userId: "ghost") == "Someone")
        #expect(session.displayName(channel: session.channels["c-dm"]!) == "bob")
        #expect(session.displayName(channel: session.channels["c-gm"]!) == "alice, bob, carol")
        #expect(session.displayName(channel: Channel(id: "x", name: "raw-name")) == "raw-name")
        #expect(session.displayName(channel: Channel(id: "self", type: .direct, name: "me1__me1")) == "alice (you)")
        #expect(session.displayName(channel: Channel(id: "bad", type: .direct, name: "weird", displayName: "Fallback")) == "Fallback")
        let post = Post(id: "x", userId: "u2", channelId: "c", message: "", props: ["from_webhook": .string("true"), "override_username": .string("hook")])
        #expect(session.displayName(for: post) == "hook")
        await session.savePreference(category: PreferenceCategory.displaySettings, name: PreferenceName.nameFormat, value: "full_name")
        #expect(session.nameDisplay == .fullName)
        #expect(session.displayName(userId: "u2") == "Bob Builder")
        #expect(session.preferenceValue(category: PreferenceCategory.displaySettings, name: PreferenceName.nameFormat) == "full_name")
        #expect(server.transport.last("PUT", "users/me1/preferences") != nil)
        session.users["me1"] = nil
        #expect(session.displayName(userId: "me1") == "alice")
        session.stop()
    }

    @Test func nameDisplayFallsBackToServerConfig() async {
        let server = MockServer()
        var config = Fixtures.clientConfig
        config["TeammateNameDisplay"] = "nickname_full_name"
        server.transport.on("GET", "config/client", object: config)
        let session = await server.startedSession()
        #expect(session.nameDisplay == .nickname)
        #expect(session.displayName(userId: "u2") == "bobby")
        session.stop()
    }

    @Test func hiddenDirectChannelsAndLimitPreference() async {
        let server = MockServer()
        server.transport.on("GET", "users/me/preferences", object: [
            ["user_id": "me1", "category": "direct_channel_show", "name": "u2", "value": "false"],
            ["user_id": "me1", "category": "group_channel_show", "name": "c-gm", "value": "false"],
            ["user_id": "me1", "category": "group_channel_show", "name": "other", "value": "true"],
        ])
        let session = await server.startedSession()
        #expect(session.hiddenDirectChannelIds == ["c-dm", "c-gm"])
        #expect(session.sidebar.last?.channelIds == [])
        session.apply(Fixtures.wsEvent("preferences_deleted", data: ["preferences": Fixtures.json([
            ["user_id": "me1", "category": "direct_channel_show", "name": "u2", "value": "false"],
            ["user_id": "me1", "category": "group_channel_show", "name": "c-gm", "value": "false"],
        ])]))
        #expect(session.sidebar.last?.channelIds == ["c-dm", "c-gm"])
        session.apply(Fixtures.wsEvent("preferences_changed", data: ["preferences": Fixtures.json([
            ["user_id": "me1", "category": "sidebar_settings", "name": "limit_visible_dms_gms", "value": "1"],
        ])]))
        #expect(session.sidebar.last?.channelIds == ["c-dm"])
        session.stop()
    }

    @Test func typingIndicatorsExpire() async {
        let server = MockServer()
        let session = await server.startedSession()
        session.typingTimeout = .milliseconds(80)
        session.apply(Fixtures.wsEvent("typing", data: ["user_id": "u2", "parent_id": ""], channel: "c-town"))
        session.apply(Fixtures.wsEvent("typing", data: ["user_id": "me1", "parent_id": ""], channel: "c-town"))
        session.apply(Fixtures.wsEvent("typing", data: ["user_id": "u3", "parent_id": "p5"], channel: "c-town"))
        session.apply(Fixtures.wsEvent("typing", data: ["user_id": ""], channel: "c-town"))
        #expect(session.typingUsers(channelId: "c-town") == ["bob"])
        #expect(await eventually { session.users["u3"] != nil })
        #expect(session.typingUsers(channelId: "c-town", parentId: "p5") == ["carol"])
        #expect(await eventually { session.typing.isEmpty })
        #expect(session.typingUsers(channelId: "c-town").isEmpty)
        session.stop()
    }

    @Test func postedMessageClearsTypingIndicator() async {
        let server = MockServer()
        let session = await server.startedSession()
        session.apply(Fixtures.wsEvent("typing", data: ["user_id": "u2", "parent_id": ""], channel: "c-town"))
        #expect(session.typingUsers(channelId: "c-town") == ["bob"])
        session.apply(Fixtures.posted(Fixtures.post("p9", channel: "c-town", user: "u2", message: "done", createAt: 900)))
        #expect(session.typingUsers(channelId: "c-town").isEmpty)
        #expect(session.typing["c-town"] == nil)
        session.stop()
    }

    @Test func typingStaleEntriesAreFilteredByClock() async {
        let server = MockServer()
        let session = await server.startedSession()
        var clock = Date(timeIntervalSince1970: 1000)
        session.now = { clock }
        session.apply(Fixtures.wsEvent("typing", data: ["user_id": "u2", "parent_id": ""], channel: "c-town"))
        #expect(session.typingUsers(channelId: "c-town") == ["bob"])
        clock = clock.addingTimeInterval(10)
        #expect(session.typingUsers(channelId: "c-town").isEmpty)
        session.stop()
    }

    @Test func userTypingIsSentAndThrottled() async throws {
        let server = MockServer()
        let session = await server.startedSession()
        var clock = Date(timeIntervalSince1970: 1000)
        session.now = { clock }
        #expect(await eventually { server.connector.sockets.count == 1 })
        let socket = try #require(server.connector.socket(0))
        socket.push(Fixtures.hello("conn1"))
        #expect(await eventually { socket.sent.count == 1 })
        session.userTyping(channelId: "c-town")
        session.userTyping(channelId: "c-town")
        session.userTyping(channelId: "c-town", parentId: "p5")
        #expect(await eventually { socket.sent.count == 3 })
        clock = clock.addingTimeInterval(4)
        session.userTyping(channelId: "c-town")
        #expect(await eventually { socket.sent.count == 4 })
        let actions = socket.sentObjects.dropFirst().map { $0["data"] as? [String: String] }
        #expect(actions == [["channel_id": "c-town", "parent_id": ""], ["channel_id": "c-town", "parent_id": "p5"], ["channel_id": "c-town", "parent_id": ""]])
        session.stop()
        clock = clock.addingTimeInterval(10)
        session.userTyping(channelId: "c-town")
    }
}

@MainActor
@Suite struct ServerSessionActionTests {
    @Test func favoritesMoveBetweenCategories() async throws {
        let server = MockServer()
        server.transport.on("PUT", "users/me/teams/t1/channels/categories/fav1") { .json($0.bodyText) }
        server.transport.on("PUT", "users/me/teams/t1/channels/categories/chan1") { .json($0.bodyText) }
        server.transport.on("PUT", "users/me/teams/t1/channels/categories/dm1") { .json($0.bodyText) }
        let session = await server.startedSession()
        await session.setFavorite(channelId: "c-dev", favorite: true)
        #expect(session.isFavorite(channelId: "c-dev"))
        #expect(session.sidebar.map(\.channelIds) == [["c-dev"], ["c-town"], ["c-dm", "c-gm"]])
        #expect(server.transport.last("PUT", "users/me/teams/t1/channels/categories/fav1")?.jsonObject["channel_ids"] as? [String] == ["c-dev"])
        #expect(server.transport.last("PUT", "users/me/teams/t1/channels/categories/chan1")?.jsonObject["channel_ids"] as? [String] == ["c-town"])
        await session.setFavorite(channelId: "c-dev", favorite: true)
        #expect(server.transport.count("PUT", "users/me/teams/t1/channels/categories/fav1") == 1)
        await session.setFavorite(channelId: "c-dev", favorite: false)
        #expect(!session.isFavorite(channelId: "c-dev"))
        #expect(session.categories["t1"]?.first { $0.id == "chan1" }?.channelIds == ["c-dev", "c-town"])
        await session.setFavorite(channelId: "c-dev", favorite: false)
        await session.setFavorite(channelId: "c-dm", favorite: true)
        await session.setFavorite(channelId: "c-dm", favorite: false)
        #expect(session.categories["t1"]?.first { $0.id == "dm1" }?.channelIds.first == "c-dm")
        #expect(server.transport.count("GET", "users/me/teams/t1/channels/categories") == 1)
        session.stop()
    }

    @Test func favoriteFailureReloadsCategories() async {
        let server = MockServer()
        server.transport.on("PUT", "users/me/teams/t1/channels/categories/fav1", .error(500))
        let session = await server.startedSession()
        await session.setFavorite(channelId: "c-dev", favorite: true)
        #expect(server.transport.count("GET", "users/me/teams/t1/channels/categories") == 2)
        #expect(!session.isFavorite(channelId: "c-dev"))
        session.stop()
    }

    @Test func favoritesNeedATeam() async {
        let server = MockServer()
        let session = await server.startedSession(team: nil)
        await session.setFavorite(channelId: "c-dev", favorite: true)
        await session.setCategoryCollapsed("chan1", collapsed: true)
        #expect(!session.isFavorite(channelId: "c-dev"))
        #expect(await session.search("x").isEmpty)
        #expect(await session.autocompleteChannels("x").isEmpty)
        #expect(await session.browsePublicChannels().isEmpty)
        #expect(server.transport.requests.allSatisfy { $0.httpMethod == "GET" || $0.url?.path == "/api/v4/users/ids" || $0.url?.path == "/api/v4/users/status/ids" })
        session.stop()
    }

    @Test func collapseCategory() async {
        let server = MockServer()
        server.transport.on("PUT", "users/me/teams/t1/channels/categories/dm1") { .json($0.bodyText) }
        let session = await server.startedSession()
        await session.setCategoryCollapsed("dm1", collapsed: true)
        #expect(session.sidebar.last?.collapsed == true)
        #expect(server.transport.last("PUT", "users/me/teams/t1/channels/categories/dm1")?.jsonObject["collapsed"] as? Bool == true)
        await session.setCategoryCollapsed("missing", collapsed: true)
        session.stop()
    }

    @Test func searchLoadsAuthorsAndChannels() async {
        let server = MockServer()
        server.transport.on("POST", "teams/t1/posts/search", object: [
            "order": ["s2", "s1"],
            "posts": [
                "s1": Fixtures.post("s1", channel: "c-other", user: "u3", message: "needle one", createAt: 10),
                "s2": Fixtures.post("s2", channel: "c-town", user: "u2", message: "needle two", createAt: 20),
            ],
        ])
        server.transport.on("GET", "channels/c-other", object: Fixtures.channel("c-other", team: "t1", name: "other", display: "Other"))
        let session = await server.startedSession()
        let found = await session.search("needle")
        #expect(found.map(\.id) == ["s2", "s1"])
        #expect(session.users["u3"]?.username == "carol")
        #expect(session.channels["c-other"]?.displayName == "Other")
        #expect(session.posts["s1"] != nil)
        #expect(await session.search("   ").isEmpty)
        #expect(server.transport.count("POST", "teams/t1/posts/search") == 1)
        server.transport.on("POST", "teams/t1/posts/search", .error(500, message: "search down"))
        #expect(await session.search("needle").isEmpty)
        #expect(session.lastError == "search down")
        session.stop()
    }

    @Test func autocompleteAndBrowse() async {
        let server = MockServer()
        server.transport.on("GET", "users/autocomplete", object: ["users": [Fixtures.user("u7", "zed")], "out_of_channel": []])
        server.transport.on("GET", "teams/t1/channels/autocomplete", object: [Fixtures.channel("c-dev", team: "t1", name: "dev")])
        server.transport.on("GET", "teams/t1/channels", object: [
            Fixtures.channel("c-open", team: "t1", name: "open"),
            Fixtures.channel("c-old", team: "t1", name: "old", deleteAt: 5),
        ])
        let session = await server.startedSession()
        #expect(await session.autocompleteUsers("ze", channelId: "c-town").map(\.id) == ["u7"])
        #expect(session.users["u7"] != nil)
        #expect(server.transport.last("GET", "users/autocomplete")?.query["in_channel"] == "c-town")
        #expect(await session.autocompleteChannels("de").map(\.id) == ["c-dev"])
        #expect(await session.browsePublicChannels().map(\.id) == ["c-open"])
        server.transport.on("GET", "users/autocomplete", .error(500))
        #expect(await session.autocompleteUsers("ze", channelId: nil).isEmpty)
        #expect(session.lastError == nil)
        server.transport.on("GET", "teams/t1/channels", .error(500, message: "browse failed"))
        #expect(await session.browsePublicChannels().isEmpty)
        #expect(session.lastError == "browse failed")
        session.stop()
    }

    @Test func joinAndLeaveChannels() async {
        let server = MockServer()
        server.transport.on("POST", "channels/c-open/members", object: Fixtures.member("c-open", user: "me1"))
        server.transport.on("GET", "channels/c-open/posts", object: Fixtures.postList([]))
        server.transport.on("DELETE", "channels/c-open/members/me1", .ok)
        let session = await server.startedSession()
        let channel = Channel(id: "c-open", teamId: "t1", name: "open", displayName: "Open")
        await session.join(channel: channel)
        #expect(session.currentChannelId == "c-open")
        #expect(session.members["c-open"] != nil)
        #expect(server.transport.last("POST", "channels/c-open/members")?.jsonObject["user_id"] as? String == "me1")
        #expect(server.transport.count("GET", "users/me/teams/t1/channels/categories") == 2)
        #expect(session.sidebar[1].channelIds.contains("c-open"))
        await session.leave(channelId: "c-open")
        #expect(session.members["c-open"] == nil)
        #expect(await eventually { session.currentChannelId == "c-town" })
        #expect(!session.sidebar[1].channelIds.contains("c-open"))
        server.transport.on("DELETE", "channels/c-dev/members/me1", .error(403, message: "cannot leave"))
        await session.leave(channelId: "c-dev")
        #expect(session.lastError == "cannot leave")
        server.transport.on("POST", "channels/c-x/members", .error(403, message: "private"))
        await session.join(channel: Channel(id: "c-x", name: "x"))
        #expect(session.lastError == "private")
        session.stop()
    }

    @Test func openDirectCreatesAndUnhidesChannel() async {
        let server = MockServer()
        server.transport.on("GET", "users/me/preferences", object: [["user_id": "me1", "category": "direct_channel_show", "name": "u3", "value": "false"]])
        server.transport.on("POST", "channels/direct", object: Fixtures.channel("c-dm3", team: "", type: "D", name: "me1__u3"))
        server.transport.on("GET", "channels/c-dm3/members/me", object: Fixtures.member("c-dm3", user: "me1"))
        server.transport.on("GET", "channels/c-dm3/posts", object: Fixtures.postList([]))
        server.transport.on("PUT", "users/me1/preferences", .ok)
        let session = await server.startedSession()
        await session.openDirect(userId: "u3")
        #expect(session.currentChannelId == "c-dm3")
        #expect(server.transport.last("POST", "channels/direct")?.jsonBody as? [String] == ["me1", "u3"])
        #expect(session.users["u3"] != nil)
        #expect(session.preferenceValue(category: PreferenceCategory.directChannelShow, name: "u3") == "true")
        #expect(server.transport.count("PUT", "users/me1/preferences") == 1)
        #expect(session.sidebar.last?.channelIds.contains("c-dm3") == true)
        server.transport.on("POST", "channels/direct", .error(500, message: "dm failed"))
        await session.openDirect(userId: "u2")
        #expect(session.lastError == "dm failed")
        session.stop()
    }

    @Test func openDirectFallsBackToLocalMember() async {
        let server = MockServer()
        server.transport.on("POST", "channels/direct", object: Fixtures.channel("c-dm4", team: "", type: "D", name: "me1__u3"))
        let session = await server.startedSession()
        await session.openDirect(userId: "u3")
        #expect(session.members["c-dm4"]?.userId == "me1")
        session.stop()
    }

    @Test func statusChanges() async {
        let server = MockServer()
        server.transport.on("PUT", "users/me1/status", object: ["user_id": "me1", "status": "dnd"])
        let session = await server.startedSession()
        await session.setStatus(.dnd)
        #expect(session.statuses["me1"] == .dnd)
        server.transport.on("PUT", "users/me1/status", .error(500, message: "status failed"))
        await session.setStatus(.away)
        #expect(session.statuses["me1"] == .dnd)
        #expect(session.lastError == "status failed")
        await session.refreshStatuses(["u3"])
        #expect(session.statuses["u3"] == .online)
        session.stop()
        let fresh = server.session()
        await fresh.setStatus(.online)
        #expect(fresh.statuses.isEmpty)
    }

    @Test func ensureUsersBatchesAndRetriesFailures() async {
        let server = MockServer()
        let session = server.session()
        let ids = (0..<250).map { "x\($0)" }
        await session.ensureUsers(ids + [""])
        #expect(server.transport.requests("POST", "users/ids").map { ($0.jsonBody as? [String])?.count } == [100, 100, 50])
        await session.ensureUsers(ids)
        #expect(server.transport.count("POST", "users/ids") == 3)
        server.transport.on("POST", "users/ids", .error(500))
        await session.ensureUsers(["y1"])
        server.users([Fixtures.user("y1", "yuri")])
        server.transport.on("POST", "users/ids", object: [Fixtures.user("y1", "yuri")])
        await session.ensureUsers(["y1"])
        #expect(session.users["y1"]?.username == "yuri")
    }

    @Test func customEmojiPagingStopsOnShortPage() async {
        let server = MockServer()
        let page = (0..<200).map { ["id": "e\($0)", "name": "emoji\($0)"] }
        server.transport.on("GET", "emoji") { request in
            request.query["page"] == "0" ? .object(page) : .object([["id": "last", "name": "last"]])
        }
        let session = server.session()
        await session.start()
        #expect(await eventually { session.customEmojis["last"] != nil })
        #expect(session.customEmojis.count == 201)
        #expect(server.transport.count("GET", "emoji") == 2)
        session.stop()
    }

    @Test func customEmojiSkippedWhenDisabled() async {
        let server = MockServer()
        var config = Fixtures.clientConfig
        config["EnableCustomEmoji"] = "false"
        server.transport.on("GET", "config/client", object: config)
        let session = server.session()
        await session.start()
        await settle()
        #expect(server.transport.count("GET", "emoji") == 0)
        session.stop()
    }
}
