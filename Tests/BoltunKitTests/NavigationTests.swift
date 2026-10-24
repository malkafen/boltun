import Foundation
import Testing
@testable import BoltunKit

final class RouteTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: (Int, String)]

    init(_ routes: [String: (Int, String)]) {
        self.routes = routes
    }

    func set(_ key: String, _ status: Int, _ body: String) {
        lock.withLock { routes[key] = (status, body) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path() ?? ""
        let key = "\(request.httpMethod ?? "GET") \(path.replacingOccurrences(of: "/api/v4/", with: ""))"
        let (status, body) = lock.withLock { routes[key] } ?? (404, #"{"id":"missing","message":"missing"}"#)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
struct NavigationTests {
    static let routes: [String: (Int, String)] = [
        "GET users/me": (200, #"{"id":"me","username":"boltun"}"#),
        "GET config/client": (200, "{}"),
        "GET users/me/teams": (200, #"[{"id":"t1","name":"alpha","display_name":"Alpha Team"},{"id":"t2","name":"beta","display_name":"Beta Team"}]"#),
        "GET users/me/teams/unread": (200, "[]"),
        "GET users/me/preferences": (200, "[]"),
        "GET users/me/teams/t1/channels": (200, #"[{"id":"c1","team_id":"t1","name":"town-square","display_name":"Town Square","type":"O"},{"id":"g1","team_id":"","name":"groupname","display_name":"a, b","type":"G"}]"#),
        "GET users/me/teams/t2/channels": (200, #"[{"id":"c2","team_id":"t2","name":"random","display_name":"Random","type":"O"}]"#),
        "GET users/me/teams/t1/channels/members": (200, #"[{"channel_id":"c1","user_id":"me"},{"channel_id":"g1","user_id":"me"}]"#),
        "GET users/me/teams/t2/channels/members": (200, #"[{"channel_id":"c2","user_id":"me"}]"#),
        "GET users/me/teams/t1/channels/categories": (200, #"{"categories":[],"order":[]}"#),
        "GET users/me/teams/t2/channels/categories": (200, #"{"categories":[],"order":[]}"#),
        "GET channels/c1/posts": (200, #"{"order":[],"posts":{}}"#),
        "GET channels/c2/posts": (200, #"{"order":[],"posts":{}}"#),
        "GET channels/g1/posts": (200, #"{"order":[],"posts":{}}"#),
        "GET channels/c9/posts": (200, #"{"order":[],"posts":{}}"#),
        "GET channels/dm/posts": (200, #"{"order":[],"posts":{}}"#),
        "POST channels/members/me/view": (200, #"{"status":"OK"}"#),
        "POST users/ids": (200, "[]"),
        "POST users/status/ids": (200, "[]"),
        "GET posts/p1": (200, #"{"id":"p1","channel_id":"c2","root_id":"","user_id":"me","message":"m"}"#),
        "GET posts/p2": (200, #"{"id":"p2","channel_id":"c9","root_id":"r","user_id":"me","message":"m"}"#),
        "GET channels/c2": (200, #"{"id":"c2","team_id":"t2","name":"random","display_name":"Random","type":"O"}"#),
        "GET channels/c9": (200, #"{"id":"c9","team_id":"t1","name":"archived","display_name":"Archived","type":"O"}"#),
        "POST users/usernames": (200, #"[{"id":"u2","username":"alice"}]"#),
        "POST channels/direct": (200, #"{"id":"dm","team_id":"","name":"me__u2","type":"D"}"#),
        "GET channels/dm/members/me": (200, #"{"channel_id":"dm","user_id":"me"}"#),
    ]

    func session(_ transport: RouteTransport = RouteTransport(NavigationTests.routes)) async throws -> ServerSession {
        let session = ServerSession(serverId: UUID(), client: APIClient(baseURL: URL(string: "http://chat.example.com")!, token: "t", transport: transport))
        try await session.loadInitial()
        return session
    }

    @Test func findsTeamsByNameOrDisplayName() async throws {
        let session = try await session()
        #expect(session.team(named: "ALPHA")?.id == "t1")
        #expect(session.team(named: "Beta Team")?.id == "t2")
        #expect(session.team(named: "gamma") == nil)
    }

    @Test func opensTeamAndChannel() async throws {
        let session = try await session()
        #expect(await session.open(teamName: "beta", channelName: "random"))
        #expect(session.currentTeamId == "t2")
        #expect(session.currentChannelId == "c2")
        #expect(session.channel(named: "Random", teamId: "t2")?.id == "c2")
        #expect(await session.open(teamName: "alpha"))
        #expect(session.currentChannelId == "c1")
        #expect(await session.open(teamName: "alpha", channelName: ""))
        #expect(await session.open(teamName: "alpha", channelName: "groupname"))
        #expect(session.currentChannelId == "g1")
        #expect(!(await session.open(teamName: "alpha", channelName: "missing")))
        #expect(!(await session.open(teamName: "nope", channelName: "random")))
    }

    @Test func opensPermalinks() async throws {
        let session = try await session()
        #expect(await session.openPermalink(postId: "p1")?.channelId == "c2")
        #expect(session.currentTeamId == "t2")
        #expect(session.currentChannelId == "c2")
        let reply = await session.openPermalink(postId: "p2")
        #expect(reply?.rootId == "r")
        #expect(session.currentChannelId == "c9")
        #expect(await session.openPermalink(postId: "p1") != nil)
        #expect(await session.openPermalink(postId: "missing") == nil)
        #expect(session.lastError != nil)
    }

    @Test func opensDirectMessagesByUsername() async throws {
        let transport = RouteTransport(NavigationTests.routes)
        let session = try await session(transport)
        await session.selectTeam("t1")
        #expect(await session.openDirect(username: "@alice", teamName: "beta"))
        #expect(session.currentChannelId == "dm")
        #expect(session.currentTeamId == "t2")
        #expect(await session.openDirect(username: "alice"))
        transport.set("POST users/usernames", 200, "[]")
        #expect(!(await session.openDirect(username: "nobody")))
    }

    @Test func reportsTeamLoadFailures() async throws {
        let transport = RouteTransport(NavigationTests.routes)
        let session = try await session(transport)
        transport.set("GET users/me/teams/t2/channels", 500, "{}")
        #expect(!(await session.ensureTeamLoaded("t2")))
        #expect(!(await session.ensureTeamLoaded("unknown")))
        #expect(!(await session.open(teamName: "beta", channelName: "random")))
        #expect(session.lastError != nil)
    }
}
