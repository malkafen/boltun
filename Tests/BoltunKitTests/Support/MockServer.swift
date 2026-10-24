import Foundation
@testable import BoltunKit

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

final class MockServer: @unchecked Sendable {
    let transport = FakeTransport()
    let connector = FakeConnector()
    private let lock = NSLock()
    private var channelPosts: [String: [[String: Any]]] = [:]
    private var directory: [String: [String: Any]] = [:]

    static let me = "me1"
    static let baseURL = URL(string: "https://chat.example.com")!

    init(pageSize: Int = 3) {
        users([
            Fixtures.user("me1", "alice", first: "Alice", last: "Liddell"),
            Fixtures.user("u2", "bob", first: "Bob", last: "Builder", nickname: "bobby"),
            Fixtures.user("u3", "carol"),
        ])
        transport.on("GET", "users/me", object: Fixtures.user("me1", "alice", first: "Alice", last: "Liddell"))
        transport.on("GET", "config/client", object: Fixtures.clientConfig)
        transport.on("GET", "users/me/teams", object: [
            Fixtures.team("t2", "beta", display: "beta"),
            Fixtures.team("t1", "alpha", display: "Alpha"),
            Fixtures.team("t3", "gone", display: "Gone", deleteAt: 5),
        ])
        transport.on("GET", "users/me/teams/unread", object: [
            ["team_id": "t1", "msg_count": 2, "mention_count": 1, "msg_count_root": 2, "mention_count_root": 1, "thread_count": 0, "thread_mention_count": 0],
            ["team_id": "t2", "msg_count": 4, "mention_count": 2, "msg_count_root": 4, "mention_count_root": 2, "thread_count": 0, "thread_mention_count": 0],
        ])
        transport.on("GET", "users/me/preferences", object: [
            ["user_id": "me1", "category": "tutorial_step", "name": "me1", "value": "0"],
        ])
        let direct = Fixtures.channel("c-dm", team: "", type: "D", name: "me1__u2", total: 2, lastPostAt: 900)
        let group = Fixtures.channel("c-gm", team: "", type: "G", name: "gmhash", display: "alice, bob, carol", total: 1, lastPostAt: 800)
        transport.on("GET", "users/me/teams/t1/channels", object: [
            Fixtures.channel("c-town", team: "t1", name: "town-square", display: "Town Square", total: 5, lastPostAt: 500),
            Fixtures.channel("c-dev", team: "t1", name: "dev", display: "Development", total: 3, lastPostAt: 300),
            direct,
            group,
        ])
        transport.on("GET", "users/me/teams/t1/channels/members", object: [
            Fixtures.member("c-town", user: "me1", msgCount: 5, lastViewedAt: 500),
            Fixtures.member("c-dev", user: "me1", msgCount: 1, mentions: 1, lastViewedAt: 100),
            Fixtures.member("c-dm", user: "me1", msgCount: 2, lastViewedAt: 900),
            Fixtures.member("c-gm", user: "me1", msgCount: 1, lastViewedAt: 800),
        ])
        transport.on("GET", "users/me/teams/t1/channels/categories", object: Fixtures.categories([
            Fixtures.category("fav1", user: "me1", team: "t1", type: "favorites", display: "Favorites", channels: []),
            Fixtures.category("chan1", user: "me1", team: "t1", type: "channels", display: "Channels", channels: ["c-town", "c-dev"]),
            Fixtures.category("dm1", user: "me1", team: "t1", type: "direct_messages", display: "Direct Messages", sorting: "recent", channels: ["c-dm", "c-gm"]),
        ]))
        transport.on("GET", "users/me/teams/t2/channels", object: [
            Fixtures.channel("c-beta", team: "t2", name: "town-square", display: "Beta Square", total: 4, lastPostAt: 400),
            direct,
            group,
        ])
        transport.on("GET", "users/me/teams/t2/channels/members", object: [
            Fixtures.member("c-beta", user: "me1", msgCount: 0, mentions: 2),
            Fixtures.member("c-dm", user: "me1", msgCount: 2, lastViewedAt: 900),
            Fixtures.member("c-gm", user: "me1", msgCount: 1, lastViewedAt: 800),
        ])
        transport.on("GET", "users/me/teams/t2/channels/categories", object: Fixtures.categories([
            Fixtures.category("fav2", user: "me1", team: "t2", type: "favorites", display: "Favorites", channels: []),
            Fixtures.category("chan2", user: "me1", team: "t2", type: "channels", display: "Channels", channels: ["c-beta"]),
            Fixtures.category("dm2", user: "me1", team: "t2", type: "direct_messages", display: "Direct Messages", channels: ["c-dm", "c-gm"]),
        ]))
        transport.on("POST", "users/ids") { [self] request in
            let ids = request.jsonBody as? [String] ?? []
            return .object(self.lock.withLock { ids.compactMap { self.directory[$0] } })
        }
        transport.on("POST", "users/status/ids") { request in
            let ids = request.jsonBody as? [String] ?? []
            return .object(ids.map { ["user_id": $0, "status": "online", "manual": false, "last_activity_at": 1] })
        }
        transport.on("POST", "channels/members/me/view", object: ["status": "OK", "last_viewed_at_times": [:]])
        transport.on("GET", "emoji", object: [["id": "e1", "name": "partyparrot", "creator_id": "u2"]])
        for channelId in ["c-town", "c-dev", "c-dm", "c-gm", "c-beta"] {
            transport.on("GET", "channels/\(channelId)/posts") { [self] request in
                .object(self.page(channelId: channelId, query: request.query))
            }
        }
        setPosts("c-town", (1...5).map { index in
            Fixtures.post("p\(index)", channel: "c-town", user: index % 2 == 0 ? "u2" : "me1", message: "message \(index)", createAt: Int64(index * 100))
        })
    }

    func users(_ list: [[String: Any]]) {
        lock.withLock {
            for user in list { directory[user["id"] as! String] = user }
        }
    }

    func setPosts(_ channelId: String, _ posts: [[String: Any]]) {
        lock.withLock { channelPosts[channelId] = posts }
    }

    func addPost(_ post: [String: Any]) {
        lock.withLock { channelPosts[post["channel_id"] as! String, default: []].append(post) }
    }

    func updatePost(_ id: String, in channelId: String, _ change: ([String: Any]) -> [String: Any]) {
        lock.withLock {
            guard var list = channelPosts[channelId], let index = list.firstIndex(where: { $0["id"] as? String == id }) else { return }
            list[index] = change(list[index])
            channelPosts[channelId] = list
        }
    }

    func page(channelId: String, query: [String: String]) -> [String: Any] {
        let collapsed = query["collapsedThreads"] == "true"
        let all = lock.withLock { channelPosts[channelId] ?? [] }
            .filter { !collapsed || ($0["root_id"] as? String ?? "").isEmpty }
            .sorted { ($0["create_at"] as! Int64) > ($1["create_at"] as! Int64) }
        if let since = query["since"].flatMap(Int64.init) {
            let changed = all.filter { post in
                let update = post["update_at"] as? Int64 ?? 0
                let delete = post["delete_at"] as? Int64 ?? 0
                return update > since || delete > since
            }
            return Fixtures.postList(changed)
        }
        let live = all.filter { ($0["delete_at"] as? Int64 ?? 0) == 0 }
        let perPage = Int(query["per_page"] ?? "60") ?? 60
        if let before = query["before"] {
            guard let pivot = live.first(where: { $0["id"] as? String == before })?["create_at"] as? Int64 else { return Fixtures.postList([]) }
            return Fixtures.postList(Array(live.filter { ($0["create_at"] as! Int64) < pivot }.prefix(perPage)))
        }
        return Fixtures.postList(Array(live.prefix(perPage)))
    }

    func acceptPosts(gate: Gate? = nil) {
        let counter = Counter()
        transport.on("POST", "posts") { [self] request in
            if let gate { await gate.wait() }
            let body = request.jsonObject
            let number = counter.next()
            var post = Fixtures.post(
                "srv\(number)",
                channel: body["channel_id"] as? String ?? "",
                user: Self.me,
                message: body["message"] as? String ?? "",
                createAt: Int64(1000 + number),
                rootId: body["root_id"] as? String ?? "",
                pendingPostId: body["pending_post_id"] as? String ?? ""
            )
            post["file_ids"] = body["file_ids"] ?? []
            self.addPost(post)
            return .object(post, status: 201)
        }
    }

    func hold(_ method: String, _ path: String, gate: Gate, then response: @escaping @Sendable (URLRequest) -> FakeResponse) {
        transport.on(method, path) { request in
            await gate.wait()
            return response(request)
        }
    }

    func holdPosts(_ channelId: String, gate: Gate) {
        hold("GET", "channels/\(channelId)/posts", gate: gate) { [self] request in
            .object(self.page(channelId: channelId, query: request.query))
        }
    }

    var viewedChannels: [String] {
        transport.requests("POST", "channels/members/me/view").compactMap { $0.jsonObject["channel_id"] as? String }
    }

    func realtimeFactory(sleeper: RealtimeClient.Sleeper? = nil) -> (URL, String) -> RealtimeClient {
        let connector = self.connector
        let sleep = sleeper ?? { _ in try await Task.sleep(for: .seconds(3600)) }
        return { url, token in
            RealtimeClient(url: url, token: token, connector: connector, handshakeTimeout: nil, sleeper: sleep)
        }
    }

    @MainActor
    func session(token: String? = "token-1", pageSize: Int = 3) -> ServerSession {
        let client = APIClient(baseURL: Self.baseURL, token: token, transport: transport)
        return ServerSession(serverId: UUID(), client: client, pageSize: pageSize, realtimeFactory: realtimeFactory())
    }

    @MainActor
    func startedSession(pageSize: Int = 3, team: String? = "t1") async -> ServerSession {
        let session = session(pageSize: pageSize)
        await session.start()
        if let team { await session.selectTeam(team) }
        return session
    }
}
