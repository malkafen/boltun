import Foundation
import Testing
@testable import BoltunKit

enum Live {
    static let variable = ProcessInfo.processInfo.environment["BOLTUN_LIVE_SERVER"]
    static let enabled = variable != nil

    static let servers: [String] = {
        let custom = (variable ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("http") }
        return custom.isEmpty ? ["http://192.168.15.101:8065", "http://192.168.15.101:8066"] : custom
    }()

    static let user = "boltun"
    static let password = "Boltun-pass1"
    static let admin = "sysadmin"
    static let adminPassword = "Sys@dmin-sample1"
    static let channelName = "boltun-kit-live"

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = ["HTTPEnable": 0, "HTTPSEnable": 0]
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    static let transport = URLSessionTransport(session: session)
    static let connector = URLSessionWebSocketConnector(session: session)

    static func client(_ base: String, token: String? = nil) -> APIClient {
        APIClient(baseURL: URL(string: base)!, token: token, transport: transport)
    }

    static func login(_ base: String, user: String = Live.user, password: String = Live.password) async throws -> (APIClient, User) {
        let result = try await client(base).login(loginId: user, password: password)
        return (client(base, token: result.token), result.user)
    }

    static func realtime(_ client: APIClient, token: String? = nil, handshakeTimeout: Duration = .seconds(20)) -> RealtimeClient {
        RealtimeClient(url: client.webSocketURL, token: token ?? client.token ?? "", connector: connector, maxBackoff: .seconds(2), handshakeTimeout: handshakeTimeout)
    }

    static func team(_ client: APIClient) async throws -> Team {
        try #require(ServerSession.sortedTeams(try await client.myTeams()).first)
    }

    static func liveChannel(_ client: APIClient, team: Team) async throws -> Channel {
        do {
            return try await client.send(Channel.self, .get, "teams/\(team.id)/channels/name/\(channelName)")
        } catch APIError.server(status: 404, _) {
            return try await client.send(Channel.self, .post, "channels", json: [
                "team_id": team.id,
                "name": channelName,
                "display_name": "Boltun Kit Live",
                "type": "P",
            ])
        }
    }

    static func marker() -> String {
        "kit-\(UUID().uuidString.prefix(8))"
    }
}

@Suite(.enabled(if: Live.enabled), .serialized, .timeLimit(.minutes(2)))
struct LiveServerTests {
    @Test(arguments: Live.servers)
    func authentication(base: String) async throws {
        let anonymous = Live.client(base)
        #expect(try await anonymous.ping())
        let config = try await anonymous.clientConfig()
        #expect(config.values["Version"]?.hasPrefix("12.") == true)
        await #expect(throws: APIError.self) {
            _ = try await anonymous.login(loginId: Live.user, password: "wrong-password")
        }
        await #expect(throws: APIError.self) { _ = try await anonymous.me() }
        let (client, user) = try await Live.login(base)
        #expect(user.username == Live.user)
        #expect(try await client.me().id == user.id)
        let (spare, _) = try await Live.login(base)
        try await spare.logout()
        do {
            _ = try await spare.me()
            Issue.record("Token still valid after logout")
        } catch let error as APIError {
            #expect(error.isUnauthorized)
        }
    }

    @Test(arguments: Live.servers)
    func teamsChannelsAndCategories(base: String) async throws {
        let (client, user) = try await Live.login(base)
        let teams = try await client.myTeams()
        #expect(!teams.isEmpty)
        let team = try await Live.team(client)
        let teamMembers = try await client.myTeamMembers()
        #expect(teamMembers.contains { $0.teamId == team.id && $0.userId == user.id })
        let unreads = try await client.myTeamUnreads()
        #expect(Set(unreads.map(\.teamId)).isSubset(of: Set(teams.map(\.id))))
        let channels = try await client.myChannels(teamId: team.id)
        let townSquare = try #require(channels.first { $0.name == "town-square" })
        #expect(townSquare.teamId == team.id)
        #expect(townSquare.type == .open)
        let members = try await client.myChannelMembers(teamId: team.id)
        #expect(members.contains { $0.channelId == townSquare.id && $0.userId == user.id })
        #expect(members.allSatisfy { $0.userId == user.id })
        let categories = try await client.myCategories(teamId: team.id)
        let types = Set(categories.categories.map(\.type))
        #expect(types.isSuperset(of: [.favorites, .channels, .directMessages]))
        #expect(categories.order.count == categories.categories.count)
        #expect(categories.categories.allSatisfy { $0.teamId == team.id && $0.userId == user.id })
        let categorized = Set(categories.categories.flatMap(\.channelIds))
        #expect(categorized.contains(townSquare.id))
        _ = try await client.preferences()
        let byId = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let memberMap = Dictionary(members.map { ($0.channelId, $0) }, uniquingKeysWith: { a, _ in a })
        let sections = SidebarBuilder.sections(
            categories: categories.categories,
            channels: byId,
            members: memberMap,
            hiddenDirect: [],
            displayName: { $0.displayName },
            currentChannelId: nil
        )
        #expect(sections.flatMap(\.channelIds).contains(townSquare.id))
        let stats = try await client.channelStats(channelId: townSquare.id)
        #expect(stats.memberCount >= 1)
        let channel = try await client.channel(id: townSquare.id)
        #expect(channel.name == "town-square")
        let member = try await client.channelMember(channelId: townSquare.id)
        #expect(member.userId == user.id)
        let users = try await client.users(ids: [user.id])
        #expect(users.map(\.username) == [Live.user])
        let statuses = try await client.statuses(userIds: [user.id])
        #expect(statuses.map(\.userId) == [user.id])
    }

    @Test(arguments: Live.servers)
    func postsLifecycle(base: String) async throws {
        let (client, user) = try await Live.login(base)
        let team = try await Live.team(client)
        let channel = try await Live.liveChannel(client, team: team)
        let marker = Live.marker()
        var created: [Post] = []
        for index in 0..<5 {
            let pending = "\(user.id):\(Date().mattermostMillis + Int64(index))"
            let post = try await client.createPost(channelId: channel.id, message: "\(marker) #\(index)", pendingPostId: pending)
            #expect(post.pendingPostId == pending)
            #expect(post.channelId == channel.id)
            created.append(post)
        }
        let ids = created.map(\.id)
        let duplicate = try await client.createPost(channelId: channel.id, message: "\(marker) #4", pendingPostId: created[4].pendingPostId)
        #expect(duplicate.id == ids[4])

        let latest = try await client.posts(channelId: channel.id, page: .latest(perPage: 3))
        #expect(latest.order == [ids[4], ids[3], ids[2]])
        #expect(latest.posts[ids[4]]?.message == "\(marker) #4")
        let older = try await client.posts(channelId: channel.id, page: .before(postId: ids[2], perPage: 2))
        #expect(older.order == [ids[1], ids[0]])
        let newer = try await client.posts(channelId: channel.id, page: .after(postId: ids[1], perPage: 10))
        #expect(Set(newer.order) == Set(ids[2...4]))
        let since = try await client.posts(channelId: channel.id, page: .since(created[0].createAt - 1))
        #expect(Set(ids).isSubset(of: Set(since.posts.keys)))

        let edited = try await client.patchPost(id: ids[4], message: "\(marker) edited")
        #expect(edited.message == "\(marker) edited")
        #expect(edited.editAt > 0)

        let reaction = try await client.addReaction(userId: user.id, postId: ids[3], emojiName: "thumbsup")
        #expect(reaction.emojiName == "thumbsup")
        let reacted = try await client.post(id: ids[3])
        #expect(reacted.metadata.reactions.contains { $0.emojiName == "thumbsup" && $0.userId == user.id })
        try await client.removeReaction(userId: user.id, postId: ids[3], emojiName: "thumbsup")
        #expect(try await client.post(id: ids[3]).metadata.reactions.isEmpty)

        try await client.pinPost(id: ids[0], pinned: true)
        #expect(try await client.pinnedPosts(channelId: channel.id).posts[ids[0]] != nil)
        try await client.pinPost(id: ids[0], pinned: false)

        let reply = try await client.createPost(channelId: channel.id, message: "\(marker) reply", rootId: ids[0])
        let thread = try await client.postThread(postId: ids[0])
        #expect(Set(thread.order).isSuperset(of: [ids[0], reply.id]))
        #expect(try await client.post(id: ids[0]).replyCount == 1)

        let unread = try await client.markPostUnread(userId: user.id, postId: ids[2])
        #expect(unread.channelId == channel.id)
        try await client.viewChannel(channelId: channel.id)

        try await client.deletePost(id: ids[1])
        await #expect(throws: APIError.self) { _ = try await client.post(id: ids[1]) }
        let changes = try await client.posts(channelId: channel.id, page: .since(created[0].createAt - 1))
        #expect((changes.posts[ids[1]]?.deleteAt ?? 0) > 0)
        let page = try await client.posts(channelId: channel.id, page: .latest(perPage: 10))
        #expect(!page.order.contains(ids[1]))
        for id in ids where id != ids[1] { try await client.deletePost(id: id) }
    }

    @Test(arguments: Live.servers)
    func websocketDeliversEvents(base: String) async throws {
        let (client, user) = try await Live.login(base)
        let team = try await Live.team(client)
        let channel = try await Live.liveChannel(client, team: team)
        let realtime = Live.realtime(client)
        let collector = EventCollector(realtime)
        await realtime.start()
        #expect(await eventuallyAsync(timeout: .seconds(15)) { await collector.connections == [false] })
        let marker = Live.marker()
        let post = try await client.createPost(channelId: channel.id, message: marker)
        let postId = post.id
        let event: @Sendable (String) async -> WebSocketEvent? = { name in
            await collector.received.first { $0.event == name && ($0.embedded(Post.self, "post")?.id == postId || $0.string("post_id") == postId || $0.embedded(Reaction.self, "reaction")?.postId == postId) }
        }
        #expect(await eventuallyAsync(timeout: .seconds(15)) { await event(WebSocketEventType.posted) != nil })
        let posted = try #require(await event(WebSocketEventType.posted))
        #expect(posted.broadcast.channelId == channel.id)
        #expect(posted.string("channel_type") == "P")
        #expect(posted.string("sender_name") == "@\(Live.user)")
        #expect(posted.embedded(Post.self, "post")?.message == marker)

        _ = try await client.patchPost(id: post.id, message: "\(marker) edited")
        #expect(await eventuallyAsync(timeout: .seconds(15)) { await event(WebSocketEventType.postEdited) != nil })
        _ = try await client.addReaction(userId: user.id, postId: post.id, emojiName: "smile")
        #expect(await eventuallyAsync(timeout: .seconds(15)) { await event(WebSocketEventType.reactionAdded) != nil })
        try await client.deletePost(id: post.id)
        #expect(await eventuallyAsync(timeout: .seconds(15)) { await event(WebSocketEventType.postDeleted) != nil })

        await realtime.userTyping(channelId: channel.id)
        await realtime.stop()
        #expect(await eventuallyAsync { await collector.finished })
        #expect(await collector.disconnects <= 1)
    }

    @Test(arguments: Live.servers)
    func websocketRejectsBadToken(base: String) async throws {
        let realtime = Live.realtime(Live.client(base), token: "not-a-valid-token", handshakeTimeout: .seconds(3))
        let collector = EventCollector(realtime)
        await realtime.start()
        #expect(await eventuallyAsync(timeout: .seconds(15)) { await collector.disconnects >= 1 })
        #expect(await collector.connections.isEmpty)
        await realtime.stop()
    }

    @MainActor
    @Test(arguments: Live.servers)
    func sessionEndToEnd(base: String) async throws {
        let (client, user) = try await Live.login(base)
        let team = try await Live.team(client)
        let channel = try await Live.liveChannel(client, team: team)
        let session = ServerSession(serverId: UUID(), client: client, realtimeFactory: { url, token in
            RealtimeClient(url: url, token: token, connector: Live.connector, maxBackoff: .seconds(2))
        })
        await session.start()
        #expect(session.connection == .connected)
        #expect(session.me?.id == user.id)
        #expect(session.teams.contains { $0.id == team.id })
        await session.selectTeam(team.id, channelId: channel.id)
        #expect(session.currentChannelId == channel.id)
        #expect(session.timelines[channel.id]?.loaded == true)
        #expect(session.sidebar.flatMap(\.channelIds).contains(channel.id))
        try await Task.sleep(for: .seconds(2))

        let marker = Live.marker()
        #expect(await session.send("\(marker) from session", channelId: channel.id))
        #expect(session.pendingPostIds.isEmpty)
        try await Task.sleep(for: .seconds(1))
        let mine = session.timelinePosts(channelId: channel.id).filter { $0.message == "\(marker) from session" }
        #expect(mine.count == 1)
        let sent = try #require(mine.first)

        let other = try await client.createPost(channelId: channel.id, message: "\(marker) via rest")
        #expect(await eventually(timeout: .seconds(15)) { session.timelinePosts(channelId: channel.id).contains { $0.id == other.id } })

        #expect(await session.edit(postId: sent.id, message: "\(marker) edited"))
        #expect(await eventually(timeout: .seconds(15)) { session.posts[sent.id]?.message == "\(marker) edited" })
        await session.toggleReaction(postId: sent.id, emojiName: "tada")
        #expect(await eventually(timeout: .seconds(15)) { session.posts[sent.id]?.metadata.reactions.contains { $0.emojiName == "tada" } == true })

        let (admin, adminUser) = try await Live.login(base, user: Live.admin, password: Live.adminPassword)
        let direct = try await admin.createDirectChannel(userIds: [adminUser.id, user.id])
        let incoming = try await admin.createPost(channelId: direct.id, message: "\(marker) direct")
        #expect(await eventually(timeout: .seconds(15)) { session.channels[direct.id] != nil && session.posts[incoming.id] != nil })
        #expect(session.unread(channelId: direct.id).unread)
        #expect(session.displayName(channel: try #require(session.channels[direct.id])) == session.displayName(userId: adminUser.id))
        await session.selectChannel(direct.id)
        #expect(await eventually(timeout: .seconds(15)) { !session.unread(channelId: direct.id).unread })

        await session.selectChannel(channel.id)
        await session.delete(postId: sent.id)
        #expect(session.posts[sent.id] == nil)
        try await client.deletePost(id: other.id)
        #expect(await eventually(timeout: .seconds(15)) { !session.timelinePosts(channelId: channel.id).contains { $0.id == other.id } })
        try await admin.deletePost(id: incoming.id)
        #expect(session.lastError == nil)
        session.stop()
    }
}
