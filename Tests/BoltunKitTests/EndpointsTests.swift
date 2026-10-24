import Foundation
import Testing
@testable import BoltunKit

@Suite struct EndpointsTests {
    let transport = FakeTransport()
    var client: APIClient { APIClient(baseURL: URL(string: "https://chat.example.com")!, token: "tok", transport: transport) }

    func only(_ method: String, _ path: String) throws -> URLRequest {
        let matching = transport.requests(method, path)
        try #require(matching.count == 1, "expected one \(method) \(path), got \(transport.requests.map { "\($0.httpMethod ?? "") \($0.url?.absoluteString ?? "")" })")
        return matching[0]
    }

    @Test func ping() async throws {
        transport.on("GET", "system/ping", json: #"{"ActiveSearchBackend":"database","status":"OK"}"#)
        #expect(try await client.ping())
        transport.on("GET", "system/ping", json: #"{"status":"unhealthy"}"#)
        #expect(try await client.ping() == false)
    }

    @Test func clientConfigUsesOldFormatAndStringifiesValues() async throws {
        transport.on("GET", "config/client", object: ["SiteName": "Chat", "Version": "12.0.1", "EnableX": true, "Limit": 5, "Nested": ["a": 1]])
        let config = try await client.clientConfig()
        #expect(try only("GET", "config/client").query == ["format": "old"])
        #expect(config["SiteName"] == "Chat")
        #expect(config["EnableX"] == "true")
        #expect(config["Limit"] == "5")
        #expect(config["Nested"] == nil)
    }

    @Test func loginReadsTokenHeader() async throws {
        transport.on("POST", "users/login", .object(Fixtures.user("u1", "alice"), headers: ["Token": "session-token"]))
        let result = try await client.login(loginId: "alice", password: "secret", mfaToken: "123456")
        #expect(result.token == "session-token")
        #expect(result.user.username == "alice")
        let body = try only("POST", "users/login").jsonObject
        #expect(body["login_id"] as? String == "alice")
        #expect(body["password"] as? String == "secret")
        #expect(body["token"] as? String == "123456")
        #expect(body["device_id"] as? String == "")
    }

    @Test func loginOmitsEmptyMFAToken() async throws {
        transport.on("POST", "users/login", .object(Fixtures.user("u1", "alice"), headers: ["token": "lowercase"]))
        let result = try await client.login(loginId: "alice", password: "secret", mfaToken: "")
        #expect(result.token == "lowercase")
        #expect(try only("POST", "users/login").jsonObject["token"] == nil)
    }

    @Test func loginWithoutTokenHeaderFails() async {
        transport.on("POST", "users/login", .object(Fixtures.user("u1", "alice")))
        await #expect(throws: APIError.invalidResponse) { try await client.login(loginId: "a", password: "b") }
        transport.on("POST", "users/login", .json("{}", headers: ["Token": "t"]))
        await #expect(throws: APIError.self) { try await client.login(loginId: "a", password: "b") }
    }

    @Test func loginRejectsBadCredentials() async {
        transport.on("POST", "users/login", .error(401, id: "api.user.login.invalid_credentials_email_username", message: "Enter a valid email or username and/or password."))
        do {
            _ = try await client.login(loginId: "a", password: "b")
            Issue.record("expected failure")
        } catch let error as APIError {
            #expect(error.isUnauthorized)
            #expect(error.localizedDescription == "Enter a valid email or username and/or password.")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func userAndTeamEndpoints() async throws {
        transport.on("POST", "users/logout", .ok)
        transport.on("GET", "users/me", object: Fixtures.user("me", "me"))
        transport.on("GET", "users/me/teams", object: [Fixtures.team("t1", "a", display: "A")])
        transport.on("GET", "users/me/teams/members", object: [["team_id": "t1", "user_id": "me", "roles": "team_user"]])
        transport.on("GET", "users/me/teams/unread", object: [["team_id": "t1", "msg_count": 1, "mention_count": 0]])
        try await client.logout()
        #expect(try await client.me().id == "me")
        #expect(try await client.myTeams().map(\.id) == ["t1"])
        #expect(try await client.myTeamMembers().first?.teamId == "t1")
        #expect(try await client.myTeamUnreads().first?.msgCount == 1)
        _ = try only("POST", "users/logout")
    }

    @Test func channelListingEndpoints() async throws {
        transport.on("GET", "users/me/teams/t1/channels", object: [Fixtures.channel("c1", team: "t1", name: "town-square")])
        transport.on("GET", "users/me/teams/t1/channels/members", object: [Fixtures.member("c1", user: "me")])
        transport.on("GET", "users/me/teams/t1/channels/categories", object: Fixtures.categories([
            Fixtures.category("cat", user: "me", team: "t1", type: "channels", display: "Channels", channels: ["c1"]),
        ]))
        #expect(try await client.myChannels(teamId: "t1").map(\.name) == ["town-square"])
        #expect(try await client.myChannelMembers(teamId: "t1").map(\.channelId) == ["c1"])
        #expect(try await client.myCategories(teamId: "t1").sorted.map(\.id) == ["cat"])
    }

    @Test func updateCategorySendsFullCategory() async throws {
        let category = ChannelCategory(id: "cat", userId: "me", teamId: "t1", type: .custom, displayName: "Work", sorting: .alphabetical, collapsed: true, channelIds: ["c2", "c1"])
        transport.on("PUT", "users/me/teams/t1/channels/categories/cat") { request in .json(request.bodyText) }
        let updated = try await client.updateCategory(category)
        #expect(updated == category)
        let body = try only("PUT", "users/me/teams/t1/channels/categories/cat").jsonObject
        #expect(body["sorting"] as? String == "alpha")
        #expect(body["collapsed"] as? Bool == true)
        #expect(body["channel_ids"] as? [String] == ["c2", "c1"])
        #expect(body["user_id"] as? String == "me")
        #expect(body["type"] as? String == "custom")
    }

    @Test func batchCategoryUpdateAndOrder() async throws {
        let work = ChannelCategory(id: "cat", userId: "me", teamId: "t1", type: .custom, displayName: "Work", sorting: .manual, channelIds: ["c2"])
        let channels = ChannelCategory(id: "chan", userId: "me", teamId: "t1", type: .channels, displayName: "Channels", channelIds: ["c1"])
        transport.on("PUT", "users/me/teams/t1/channels/categories") { request in .json(request.bodyText) }
        transport.on("PUT", "users/me/teams/t1/channels/categories/order") { request in .json(request.bodyText) }
        #expect(try await client.updateCategories(teamId: "t1", [work, channels]) == [work, channels])
        let body = try only("PUT", "users/me/teams/t1/channels/categories").jsonBody as? [[String: Any]]
        #expect(body?.map { $0["id"] as? String } == ["cat", "chan"])
        #expect(body?.first?["sorting"] as? String == "manual")
        #expect(body?.last?["sorting"] as? String == "")
        #expect(try await client.updateCategoryOrder(teamId: "t1", order: ["chan", "cat"]) == ["chan", "cat"])
        #expect(try only("PUT", "users/me/teams/t1/channels/categories/order").jsonBody as? [String] == ["chan", "cat"])
    }

    @Test func singleChannelEndpoints() async throws {
        transport.on("GET", "channels/c1", object: Fixtures.channel("c1", team: "t1", name: "dev"))
        transport.on("GET", "channels/c1/members/me", object: Fixtures.member("c1", user: "me", msgCount: 4))
        transport.on("GET", "channels/c1/stats", object: ["channel_id": "c1", "member_count": 9, "pinnedpost_count": 2])
        transport.on("POST", "channels/members/me/view", .ok)
        #expect(try await client.channel(id: "c1").name == "dev")
        #expect(try await client.channelMember(channelId: "c1").msgCount == 4)
        #expect(try await client.channelStats(channelId: "c1").memberCount == 9)
        try await client.viewChannel(channelId: "c1", previousChannelId: "c0")
        let body = try only("POST", "channels/members/me/view").jsonObject
        #expect(body["channel_id"] as? String == "c1")
        #expect(body["prev_channel_id"] as? String == "c0")
    }

    @Test func directAndGroupChannels() async throws {
        transport.on("POST", "channels/direct", object: Fixtures.channel("d", team: "", type: "D", name: "a__b"))
        transport.on("POST", "channels/group", object: Fixtures.channel("g", team: "", type: "G", name: "hash"))
        #expect(try await client.createDirectChannel(userIds: ["a", "b"]).type == .direct)
        #expect(try await client.createGroupChannel(userIds: ["a", "b", "c"]).type == .group)
        #expect(try only("POST", "channels/direct").jsonBody as? [String] == ["a", "b"])
        #expect(try only("POST", "channels/group").jsonBody as? [String] == ["a", "b", "c"])
    }

    @Test func browseJoinLeave() async throws {
        transport.on("GET", "teams/t1/channels/autocomplete", object: [Fixtures.channel("c1", team: "t1", name: "dev")])
        transport.on("GET", "teams/t1/channels", object: [Fixtures.channel("c2", team: "t1", name: "random")])
        transport.on("POST", "channels/c2/members", object: Fixtures.member("c2", user: "me"))
        transport.on("DELETE", "channels/c2/members/me", .ok)
        #expect(try await client.autocompleteChannels(teamId: "t1", name: "de").count == 1)
        #expect(try only("GET", "teams/t1/channels/autocomplete").query == ["name": "de"])
        #expect(try await client.publicChannels(teamId: "t1", page: 2, perPage: 50).first?.id == "c2")
        #expect(try only("GET", "teams/t1/channels").query == ["page": "2", "per_page": "50"])
        #expect(try await client.joinChannel(channelId: "c2", userId: "me").channelId == "c2")
        #expect(try only("POST", "channels/c2/members").jsonObject["user_id"] as? String == "me")
        try await client.leaveChannel(channelId: "c2", userId: "me")
        _ = try only("DELETE", "channels/c2/members/me")
    }

    @Test(arguments: [
        (PostPage.latest(perPage: 30), ["page": "0", "per_page": "30"]),
        (PostPage.before(postId: "p9", perPage: 20), ["before": "p9", "per_page": "20"]),
        (PostPage.after(postId: "p1", perPage: 10), ["after": "p1", "per_page": "10"]),
        (PostPage.since(1_700_000_000_000), ["since": "1700000000000"]),
    ])
    func postPagingQueries(page: PostPage, query: [String: String]) async throws {
        transport.on("GET", "channels/c1/posts", object: Fixtures.postList([Fixtures.post("p1", channel: "c1", user: "u", message: "m", createAt: 1)]))
        let list = try await client.posts(channelId: "c1", page: page)
        #expect(list.order == ["p1"])
        #expect(try only("GET", "channels/c1/posts").query == query)
    }

    @Test func postEndpoints() async throws {
        transport.on("GET", "posts/p1/thread", object: Fixtures.postList([Fixtures.post("p1", channel: "c", user: "u", message: "root", createAt: 1)]))
        transport.on("GET", "posts/p1", object: Fixtures.post("p1", channel: "c", user: "u", message: "root", createAt: 1))
        transport.on("POST", "posts") { request in
            var post = Fixtures.post("new", channel: "c", user: "u", message: "", createAt: 2)
            for (key, value) in request.jsonObject { post[key] = value }
            return .object(post, status: 201)
        }
        transport.on("PUT", "posts/p1/patch", object: Fixtures.post("p1", channel: "c", user: "u", message: "edited", createAt: 1))
        transport.on("DELETE", "posts/p1", .ok)
        transport.on("POST", "posts/p1/pin", .ok)
        transport.on("POST", "posts/p1/unpin", .ok)
        #expect(try await client.postThread(postId: "p1").order == ["p1"])
        #expect(try await client.post(id: "p1").message == "root")
        let created = try await client.createPost(channelId: "c", message: "hello", rootId: "p1", fileIds: ["f1"], pendingPostId: "u:1")
        #expect(created.message == "hello")
        #expect(created.rootId == "p1")
        let body = try only("POST", "posts").jsonObject
        #expect(body["channel_id"] as? String == "c")
        #expect(body["file_ids"] as? [String] == ["f1"])
        #expect(body["pending_post_id"] as? String == "u:1")
        #expect(try await client.patchPost(id: "p1", message: "edited").message == "edited")
        #expect(try only("PUT", "posts/p1/patch").jsonObject["message"] as? String == "edited")
        try await client.deletePost(id: "p1")
        try await client.pinPost(id: "p1", pinned: true)
        try await client.pinPost(id: "p1", pinned: false)
        _ = try only("DELETE", "posts/p1")
        _ = try only("POST", "posts/p1/pin")
        _ = try only("POST", "posts/p1/unpin")
    }

    @Test func markPostUnread() async throws {
        transport.on("POST", "users/me/posts/p1/set_unread", object: ["team_id": "t", "channel_id": "c", "msg_count": 3, "mention_count": 1, "msg_count_root": 2, "mention_count_root": 1, "urgent_mention_count": 0, "last_viewed_at": 99])
        let unread = try await client.markPostUnread(userId: "me", postId: "p1")
        #expect(unread.msgCount == 3)
        #expect(unread.lastViewedAt == 99)
        #expect(try only("POST", "users/me/posts/p1/set_unread").jsonObject["collapsed_threads_supported"] as? Bool == false)
    }

    @Test func reactions() async throws {
        transport.on("POST", "reactions", object: Fixtures.reaction(user: "me", post: "p1", emoji: "+1"))
        transport.on("DELETE", "users/me/posts/p1/reactions/+1", .ok)
        let reaction = try await client.addReaction(userId: "me", postId: "p1", emojiName: "+1")
        #expect(reaction.emojiName == "+1")
        #expect(try only("POST", "reactions").jsonObject as? [String: String] == ["user_id": "me", "post_id": "p1", "emoji_name": "+1"])
        try await client.removeReaction(userId: "me", postId: "p1", emojiName: "+1")
        _ = try only("DELETE", "users/me/posts/p1/reactions/+1")
    }

    @Test func userLookups() async throws {
        transport.on("POST", "users/ids", object: [Fixtures.user("u1", "a")])
        transport.on("POST", "users/usernames", object: [Fixtures.user("u2", "b")])
        #expect(try await client.users(ids: []).isEmpty)
        #expect(try await client.usersByUsernames([]).isEmpty)
        #expect(transport.requests.isEmpty)
        #expect(try await client.users(ids: ["u1"]).map(\.id) == ["u1"])
        #expect(try await client.usersByUsernames(["b"]).map(\.id) == ["u2"])
        #expect(try only("POST", "users/ids").jsonBody as? [String] == ["u1"])
        #expect(try only("POST", "users/usernames").jsonBody as? [String] == ["b"])
    }

    @Test func autocompleteUsersMergesOutOfChannel() async throws {
        transport.on("GET", "users/autocomplete", object: ["users": [Fixtures.user("u1", "ann")], "out_of_channel": [Fixtures.user("u2", "andy")]])
        let users = try await client.autocompleteUsers(name: "an", teamId: "t1", channelId: "c1", limit: 10)
        #expect(users.map(\.id) == ["u1", "u2"])
        #expect(try only("GET", "users/autocomplete").query == ["name": "an", "in_team": "t1", "in_channel": "c1", "limit": "10"])
        transport.reset()
        transport.on("GET", "users/autocomplete", object: ["users": [Fixtures.user("u1", "ann")]])
        #expect(try await client.autocompleteUsers(name: "an").count == 1)
        #expect(try only("GET", "users/autocomplete").query == ["name": "an", "limit": "25"])
    }

    @Test func statusesAndPreferences() async throws {
        transport.on("POST", "users/status/ids", object: [["user_id": "u1", "status": "away"]])
        transport.on("PUT", "users/me/status", object: ["user_id": "me", "status": "dnd"])
        transport.on("GET", "users/me/preferences", object: [["user_id": "me", "category": "theme", "name": "", "value": "{}"]])
        transport.on("PUT", "users/me/preferences", .ok)
        #expect(try await client.statuses(userIds: []).isEmpty)
        #expect(try await client.statuses(userIds: ["u1"]).first?.status == .away)
        try await client.setStatus(userId: "me", status: .dnd)
        #expect(try only("PUT", "users/me/status").jsonObject as? [String: String] == ["user_id": "me", "status": "dnd"])
        #expect(try await client.preferences().first?.category == "theme")
        try await client.savePreferences(userId: "me", [Preference(userId: "me", category: "c", name: "n", value: "v")])
        let saved = try only("PUT", "users/me/preferences").jsonBody as? [[String: String]]
        #expect(saved == [["user_id": "me", "category": "c", "name": "n", "value": "v"]])
    }

    @Test func searchAndCollections() async throws {
        transport.on("POST", "teams/t1/posts/search", object: ["order": ["p"], "posts": ["p": Fixtures.post("p", channel: "c", user: "u", message: "x", createAt: 1)], "matches": NSNull()])
        transport.on("GET", "users/me/posts/flagged", object: Fixtures.postList([]))
        transport.on("GET", "channels/c1/pinned", object: Fixtures.postList([]))
        #expect(try await client.searchPosts(teamId: "t1", terms: "x from:bob", page: 1, perPage: 20).order == ["p"])
        let body = try only("POST", "teams/t1/posts/search").jsonObject
        #expect(body["terms"] as? String == "x from:bob")
        #expect(body["is_or_search"] as? Bool == false)
        #expect(body["page"] as? Int == 1)
        #expect(body["per_page"] as? Int == 20)
        #expect(body["time_zone_offset"] as? Int == TimeZone.current.secondsFromGMT())
        _ = try await client.flaggedPosts(userId: "me", page: 1, perPage: 5)
        #expect(try only("GET", "users/me/posts/flagged").query == ["page": "1", "per_page": "5"])
        _ = try await client.pinnedPosts(channelId: "c1")
        _ = try only("GET", "channels/c1/pinned")
    }

    @Test func emoji() async throws {
        transport.on("GET", "emoji/name/parrot", object: ["id": "e1", "name": "parrot", "creator_id": "u"])
        transport.on("GET", "emoji", object: [["id": "e1", "name": "parrot"]])
        #expect(try await client.customEmoji(name: "parrot").id == "e1")
        #expect(try await client.customEmojis(page: 3, perPage: 10).count == 1)
        #expect(try only("GET", "emoji").query == ["page": "3", "per_page": "10", "sort": "name"])
    }

    @Test func uploadBuildsMultipartBody() async throws {
        transport.on("POST", "files", object: ["file_infos": [["id": "f1", "name": "a\"b.png", "mime_type": "image/png", "size": 3]], "client_ids": []], status: 201)
        let info = try await client.uploadFile(channelId: "c1", filename: "a\"b.png", data: Data([0xFF, 0x00, 0x01]), mimeType: "image/png")
        #expect(info.id == "f1")
        let request = try only("POST", "files")
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary=boltun-"))
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        let body = try #require(request.httpBody)
        var expected = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"channel_id\"\r\n\r\nc1\r\n".utf8)
        expected.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"a_b.png\"\r\nContent-Type: image/png\r\n\r\n".utf8))
        expected.append(Data([0xFF, 0x00, 0x01]))
        expected.append(Data("\r\n--\(boundary)--\r\n".utf8))
        #expect(body == expected)
    }

    @Test func uploadWithoutFileInfosFails() async {
        transport.on("POST", "files", object: ["file_infos": []], status: 201)
        await #expect(throws: APIError.invalidResponse) { try await client.uploadFile(channelId: "c", filename: "a", data: Data()) }
    }

    @Test func mediaURLs() {
        #expect(client.fileURL(id: "f").absoluteString == "https://chat.example.com/api/v4/files/f")
        #expect(client.fileThumbnailURL(id: "f").absoluteString == "https://chat.example.com/api/v4/files/f/thumbnail")
        #expect(client.filePreviewURL(id: "f").absoluteString == "https://chat.example.com/api/v4/files/f/preview")
        #expect(client.profileImageURL(userId: "u").absoluteString == "https://chat.example.com/api/v4/users/u/image")
        #expect(client.profileImageURL(userId: "u", lastPictureUpdate: 12).absoluteString == "https://chat.example.com/api/v4/users/u/image?_=12")
        #expect(client.customEmojiImageURL(id: "e").absoluteString == "https://chat.example.com/api/v4/emoji/e/image")
        #expect(client.teamIconURL(teamId: "t").absoluteString == "https://chat.example.com/api/v4/teams/t/image")
        #expect(client.teamIconURL(teamId: "t", lastIconUpdate: 7).absoluteString == "https://chat.example.com/api/v4/teams/t/image?_=7")
    }
}
