import AppKit
import BoltunKit
import Foundation
import SwiftUI
@testable import BoltunUI

final class FakeTransport: HTTPTransport, @unchecked Sendable {
    struct Response {
        var status: Int
        var body: String
        var headers: [String: String] = [:]
    }

    private let lock = NSLock()
    private var routes: [String: Response] = [:]
    private var log: [URLRequest] = []

    init(routes: [String: Response] = FakeTransport.standardRoutes) {
        self.routes = routes
    }

    func set(_ key: String, _ response: Response) {
        lock.withLock { routes[key] = response }
    }

    func set(_ key: String, status: Int = 200, _ body: String, headers: [String: String] = [:]) {
        set(key, Response(status: status, body: body, headers: headers))
    }

    var requests: [URLRequest] { lock.withLock { log } }

    func requests(matching key: String) -> [URLRequest] {
        requests.filter { Self.key(for: $0) == key }
    }

    static func key(for request: URLRequest) -> String {
        let path = request.url?.path() ?? ""
        let trimmed = path.range(of: "/api/v4/").map { String(path[$0.upperBound...]) } ?? path
        return "\(request.httpMethod ?? "GET") \(trimmed)"
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let key = Self.key(for: request)
        let response = lock.withLock {
            log.append(request)
            return routes[key]
        } ?? Response(status: 404, body: #"{"id":"not_found","message":"Not found: \#(key)"}"#)
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: response.headers)!
        return (Data(response.body.utf8), http)
    }

    static let me = #"{"id":"me","username":"boltun","notify_props":{"desktop":"mention"}}"#
    static let teams = #"[{"id":"t1","name":"team-one","display_name":"Team One"},{"id":"t2","name":"team-two","display_name":"Team Two"}]"#
    static let channelsT1 = #"[{"id":"c1","team_id":"t1","name":"town-square","display_name":"Town Square","type":"O","total_msg_count":3,"last_post_at":30},{"id":"c2","team_id":"t1","name":"off-topic","display_name":"Off-Topic","type":"O","total_msg_count":1,"last_post_at":10}]"#
    static let channelsT2 = #"[{"id":"c3","team_id":"t2","name":"town-square","display_name":"Town Square","type":"O"},{"id":"c4","team_id":"t2","name":"random","display_name":"Random","type":"O"}]"#
    static let membersT1 = #"[{"channel_id":"c1","user_id":"me","msg_count":1,"mention_count":2},{"channel_id":"c2","user_id":"me","msg_count":1}]"#
    static let membersT2 = #"[{"channel_id":"c3","user_id":"me"},{"channel_id":"c4","user_id":"me"}]"#
    static let posts = #"{"order":["p2","p1"],"posts":{"p1":{"id":"p1","channel_id":"c1","user_id":"me","message":"hello","create_at":10},"p2":{"id":"p2","channel_id":"c1","user_id":"me","message":"world","create_at":20}}}"#
    static let emptyPosts = #"{"order":[],"posts":{}}"#

    static var standardRoutes: [String: Response] {
        var routes: [String: Response] = [
            "GET system/ping": Response(status: 200, body: #"{"status":"OK"}"#),
            "GET config/client": Response(status: 200, body: #"{"SiteName":"Test Site","Version":"12.0.0","EnableSignUpWithGitLab":"true","EnableSaml":"true","SamlLoginButtonText":"Corporate SSO"}"#),
            "POST users/login": Response(status: 200, body: me, headers: ["Token": "session-token"]),
            "POST users/logout": Response(status: 200, body: #"{"status":"OK"}"#),
            "GET users/me": Response(status: 200, body: me),
            "GET users/me/teams": Response(status: 200, body: teams),
            "GET users/me/teams/unread": Response(status: 200, body: #"[{"team_id":"t2","msg_count":4,"mention_count":1}]"#),
            "GET users/me/preferences": Response(status: 200, body: "[]"),
            "GET users/me/teams/t1/channels": Response(status: 200, body: channelsT1),
            "GET users/me/teams/t2/channels": Response(status: 200, body: channelsT2),
            "GET users/me/teams/t1/channels/members": Response(status: 200, body: membersT1),
            "GET users/me/teams/t2/channels/members": Response(status: 200, body: membersT2),
            "GET users/me/teams/t1/channels/categories": Response(status: 200, body: #"{"categories":[],"order":[]}"#),
            "GET users/me/teams/t2/channels/categories": Response(status: 200, body: #"{"categories":[],"order":[]}"#),
            "POST channels/members/me/view": Response(status: 200, body: #"{"status":"OK"}"#),
            "POST users/ids": Response(status: 200, body: "[]"),
            "POST users/status/ids": Response(status: 200, body: "[]"),
            "GET posts/p9": Response(status: 200, body: #"{"id":"p9","channel_id":"c4","root_id":"r9","user_id":"u2","message":"reply","create_at":50}"#),
            "GET posts/r9/thread": Response(status: 200, body: emptyPosts),
            "GET channels/c4": Response(status: 200, body: #"{"id":"c4","team_id":"t2","name":"random","display_name":"Random","type":"O"}"#),
            "POST users/usernames": Response(status: 200, body: #"[{"id":"u2","username":"alice"}]"#),
            "POST channels/direct": Response(status: 200, body: #"{"id":"dm1","team_id":"","name":"me__u2","display_name":"","type":"D"}"#),
            "GET channels/dm1/members/me": Response(status: 200, body: #"{"channel_id":"dm1","user_id":"me"}"#),
        ]
        for channel in ["c1", "c2", "c3", "c4", "dm1"] {
            routes["GET channels/\(channel)/posts"] = Response(status: 200, body: channel == "c1" ? posts : emptyPosts)
        }
        return routes
    }
}

struct IdleConnector: WebSocketConnector {
    func connect(url: URL, token: String) -> WebSocketConnection { IdleConnection() }
}

final class IdleConnection: WebSocketConnection, @unchecked Sendable {
    func send(_ text: String) async throws {}
    func receive() async throws -> String {
        try await Task.sleep(for: .seconds(3600))
        return ""
    }
    func close() {}
}

@MainActor
final class FakeDock: DockControlling {
    var badgeLabel: String?
    var isAppActive = false
    private(set) var attentionRequests = 0
    private(set) var activations = 0

    func requestAttention() { attentionRequests += 1 }
    func activate() { activations += 1 }
}

@MainActor
final class FakeLoginItem: LoginItemControlling {
    var isEnabled = false
    var failure: Error?
    private(set) var calls: [Bool] = []

    func setEnabled(_ enabled: Bool) throws {
        calls.append(enabled)
        if let failure { throw failure }
        isEnabled = enabled
    }
}

@MainActor
final class FakeWebAuthenticator: WebAuthenticating {
    var result: Result<URL, Error>
    private(set) var requests: [(URL, String)] = []

    init(result: Result<URL, Error>) {
        self.result = result
    }

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        requests.append((url, callbackScheme))
        return try result.get()
    }
}

struct TestFailure: Error, LocalizedError {
    var errorDescription: String? { "boom" }
}

@MainActor
struct Harness {
    let transport: FakeTransport
    let store: MemoryAppStateStore
    let credentials: MemoryCredentialStore
    let model: AppModel

    init(servers: [ServerConfig] = [], tokens: [UUID: String] = [:], settings: AppSettings = AppSettings(), transport: FakeTransport = FakeTransport()) {
        self.transport = transport
        store = MemoryAppStateStore(AppState(servers: servers, settings: settings))
        credentials = MemoryCredentialStore(tokens)
        model = AppModel(store: store, credentials: credentials, transport: transport) { url, token in
            RealtimeClient(url: url, token: token, connector: IdleConnector(), sleeper: { _ in try await Task.sleep(for: .seconds(3600)) })
        }
    }

    static func server(_ name: String = "Alpha", port: Int = 8065) -> ServerConfig {
        ServerConfig(name: name, url: URL(string: "http://chat.example.com:\(port)")!)
    }

    static func connected(_ servers: [ServerConfig] = [server()]) async -> Harness {
        let harness = Harness(servers: servers, tokens: Dictionary(uniqueKeysWithValues: servers.map { ($0.id, "token") }))
        await harness.model.startAll()
        return harness
    }

    func environment(center: SilentNotificationCenter = SilentNotificationCenter(), dock: FakeDock = FakeDock(), loginItem: FakeLoginItem = FakeLoginItem(), opened: @escaping (URL) -> Void = { _ in }) -> AppEnvironment {
        AppEnvironment(model: model, center: center, dock: dock, loginItem: loginItem, openURL: opened)
    }
}

@MainActor
enum Render {
    static let outputDirectory = ProcessInfo.processInfo.environment["BOLTUN_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }

    @discardableResult
    static func png<Content: View>(_ view: Content, size: CGSize = CGSize(width: 520, height: 520), name: String) -> Data? {
        let data = Snapshot.png(view, size: size)
        if let data, let outputDirectory {
            try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try? data.write(to: outputDirectory.appending(path: "\(name).png"))
        }
        return data
    }

    static func spin(_ seconds: Double = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}

@MainActor
func eventually(timeout: Double = 20, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}
