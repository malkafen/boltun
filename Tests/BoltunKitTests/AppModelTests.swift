import Foundation
import Testing
@testable import BoltunKit

@MainActor
struct AppHarness {
    let server = MockServer()
    let store: MemoryAppStateStore
    let credentials: MemoryCredentialStore
    let first: ServerConfig
    let second: ServerConfig

    init(lastServer: Int? = nil, tokens: Bool = true, lastTeam: String? = nil, lastChannels: [String: String] = [:]) {
        let first = ServerConfig(name: "First", url: URL(string: "https://one.example.com")!, lastTeamId: lastTeam, lastChannelByTeam: lastChannels)
        let second = ServerConfig(name: "Second", url: URL(string: "https://two.example.com")!)
        var settings = AppSettings()
        settings.lastServerId = lastServer.map { [first, second][$0].id }
        self.first = first
        self.second = second
        store = MemoryAppStateStore(AppState(servers: [first, second], settings: settings))
        credentials = MemoryCredentialStore(tokens ? [first.id: "token-1", second.id: "token-2"] : [:])
    }

    func model() -> AppModel {
        AppModel(store: store, credentials: credentials, transport: server.transport, realtimeFactory: server.realtimeFactory())
    }
}

@MainActor
@Suite struct AppModelServerTests {
    @Test func restoresSelectedServer() {
        let harness = AppHarness(lastServer: 1)
        let app = harness.model()
        #expect(app.selectedServerId == harness.second.id)
        #expect(app.selectedServer?.name == "Second")
        #expect(app.servers.map(\.name) == ["First", "Second"])
        let fallback = AppHarness()
        #expect(fallback.model().selectedServerId == fallback.first.id)
        var settings = AppSettings()
        settings.lastServerId = UUID()
        let stale = AppModel(store: MemoryAppStateStore(AppState(servers: [harness.first], settings: settings)), credentials: MemoryCredentialStore())
        #expect(stale.selectedServerId == harness.first.id)
        let empty = AppModel(store: MemoryAppStateStore(), credentials: MemoryCredentialStore())
        #expect(empty.selectedServerId == nil)
        #expect(empty.selectedServer == nil)
        #expect(empty.selectedSession == nil)
        #expect(empty.badgeLabel == nil)
    }

    @Test func addServer() {
        let app = AppModel(store: MemoryAppStateStore(), credentials: MemoryCredentialStore())
        let url = URL(string: "https://chat.example.com")!
        let added = app.addServer(name: "  Work  ", url: url)
        #expect(added.name == "Work")
        #expect(app.selectedServerId == added.id)
        #expect(app.needsLogin.contains(added.id))
        #expect(app.addServer(name: "Again", url: url).id == added.id)
        let unnamed = app.addServer(name: " ", url: URL(string: "https://other.example.com")!)
        #expect(unnamed.name == "other.example.com")
        #expect(app.selectedServerId == added.id)
        #expect(app.servers.count == 2)
        #expect(app.store.load().servers.map(\.id) == [added.id, unnamed.id])
    }

    @Test func updateServer() async {
        let harness = AppHarness()
        let app = harness.model()
        await app.startAll()
        let session = app.session(for: harness.first.id)
        var renamed = harness.first
        renamed.name = "Renamed"
        app.updateServer(renamed)
        #expect(app.servers[0].name == "Renamed")
        #expect(app.session(for: harness.first.id) === session)
        #expect(harness.credentials.token(for: harness.first.id) == "token-1")
        var moved = app.servers[0]
        moved.url = URL(string: "https://moved.example.com")!
        app.updateServer(moved)
        #expect(app.servers[0].url == moved.url)
        #expect(app.session(for: harness.first.id) == nil)
        #expect(session?.connection == .idle)
        #expect(harness.credentials.token(for: harness.first.id) == nil)
        #expect(app.needsLogin.contains(harness.first.id))
        #expect(harness.store.load().servers[0].url == moved.url)
        app.updateServer(ServerConfig(name: "Ghost", url: moved.url))
        #expect(app.servers.count == 2)
    }

    @Test func moveServers() {
        let harness = AppHarness()
        let app = harness.model()
        let third = app.addServer(name: "Third", url: URL(string: "https://three.example.com")!)
        app.moveServers(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(app.servers.map(\.name) == ["Second", "Third", "First"])
        app.moveServers(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(app.servers.map(\.name) == ["First", "Second", "Third"])
        app.moveServers(fromOffsets: IndexSet([0, 2]), toOffset: 2)
        #expect(app.servers.map(\.name) == ["Second", "First", "Third"])
        #expect(harness.store.load().servers.map(\.name) == ["Second", "First", "Third"])
        #expect(app.servers.last?.id == third.id)
    }

    @Test func removeServer() async throws {
        let harness = AppHarness()
        harness.server.transport.on("POST", "users/logout", .ok)
        let app = harness.model()
        await app.startAll()
        let session = try #require(app.session(for: harness.first.id))
        await app.removeServer(harness.first.id)
        #expect(session.connection == .idle)
        #expect(app.session(for: harness.first.id) == nil)
        #expect(app.servers.map(\.id) == [harness.second.id])
        #expect(app.selectedServerId == harness.second.id)
        #expect(app.settings.lastServerId == harness.second.id)
        #expect(harness.credentials.token(for: harness.first.id) == nil)
        await eventuallyAsync { harness.server.transport.count("POST", "users/logout") == 1 }
        await app.removeServer(harness.second.id)
        #expect(app.selectedServerId == nil)
        #expect(harness.store.load().servers.isEmpty)
        await app.removeServer(UUID())
    }

    @Test func settingsPersist() {
        let harness = AppHarness()
        let app = harness.model()
        app.settings.fontScale = 1.5
        #expect(harness.store.load().settings.fontScale == 1.5)
    }
}

@MainActor
@Suite struct AppModelSessionTests {
    @Test func startAllRestoresSelection() async throws {
        let harness = AppHarness(lastTeam: "t1", lastChannels: ["t1": "c-dev"])
        let app = harness.model()
        await app.startAll()
        let session = try #require(app.selectedSession)
        #expect(session.connection == .connected)
        #expect(session.currentTeamId == "t1")
        #expect(session.currentChannelId == "c-dev")
        #expect(app.sessions.count == 2)
        #expect(app.session(for: harness.second.id)?.currentTeamId == nil)
        #expect(app.needsLogin.isEmpty)
    }

    @Test func restoreFallsBackToFirstTeam() async throws {
        let harness = AppHarness(lastTeam: "t9")
        let app = harness.model()
        await app.startAll()
        let session = try #require(app.selectedSession)
        #expect(session.currentTeamId == "t1")
        #expect(session.currentChannelId == "c-town")
        #expect(app.servers[0].lastTeamId == "t1")
        #expect(app.servers[0].lastChannelByTeam["t1"] == "c-town")
        #expect(harness.store.load().servers[0].lastChannelByTeam["t1"] == "c-town")
    }

    @Test func rememberSelectionTracksChannels() async throws {
        let harness = AppHarness(lastTeam: "t1")
        let app = harness.model()
        await app.startAll()
        let session = try #require(app.selectedSession)
        await session.selectChannel("c-dev")
        #expect(app.servers[0].lastChannelByTeam == ["t1": "c-dev"])
        app.rememberSelection(serverId: harness.first.id, teamId: nil, channelId: "x")
        #expect(app.servers[0].lastTeamId == nil)
        #expect(app.servers[0].lastChannelByTeam == ["t1": "c-dev"])
        app.rememberSelection(serverId: UUID(), teamId: "t1", channelId: "x")
    }

    @Test func selectServer() async {
        let harness = AppHarness()
        let app = harness.model()
        await app.startAll()
        #expect(app.session(for: harness.second.id)?.currentTeamId == nil)
        await app.selectServer(at: 1)
        #expect(app.selectedServerId == harness.second.id)
        #expect(app.settings.lastServerId == harness.second.id)
        #expect(app.session(for: harness.second.id)?.currentTeamId == "t1")
        #expect(harness.store.load().settings.lastServerId == harness.second.id)
        await app.selectServer(at: 5)
        await app.select(serverId: UUID())
        #expect(app.selectedServerId == harness.second.id)
        await app.select(serverId: harness.first.id)
        #expect(app.selectedSession?.currentTeamId == "t1")
    }

    @Test func missingTokenNeedsLogin() async {
        let harness = AppHarness(tokens: false)
        let app = harness.model()
        await app.startAll()
        #expect(app.needsLogin == [harness.first.id, harness.second.id])
        #expect(app.selectedSession?.connection == .unauthorized)
        #expect(harness.server.transport.requests.isEmpty)
    }

    @Test func unauthorizedSessionNeedsLogin() async {
        let harness = AppHarness()
        harness.server.transport.on("GET", "users/me", .error(401, id: "api.context.session_expired.app_error"))
        let app = harness.model()
        await app.startAll()
        #expect(app.needsLogin == [harness.first.id, harness.second.id])
        #expect(app.selectedSession?.connection == .unauthorized)
    }

    @Test func badge() async throws {
        let harness = AppHarness()
        let app = harness.model()
        #expect(app.badgeLabel == nil)
        await app.startAll()
        let session = try #require(app.selectedSession)
        #expect(session.currentChannelId == "c-town")
        #expect(app.unread(serverId: harness.first.id) == ChannelUnread(unread: true, mentions: 3))
        #expect(app.totalMentions == 6)
        #expect(app.hasUnread)
        #expect(app.badgeLabel == "6")
        let other = try #require(app.session(for: harness.second.id))
        other.teamUnreads["t1"] = TeamUnread(teamId: "t1", msgCount: 1, mentionCount: 200)
        #expect(app.badgeLabel == "99+")
        for session in app.sessions.values {
            session.teamUnreads = [:]
            for id in Array(session.members.keys) { session.members[id]?.mentionCount = 0 }
        }
        #expect(app.totalMentions == 0)
        #expect(app.badgeLabel == "•")
        for session in app.sessions.values {
            for (id, channel) in session.channels { session.members[id]?.msgCount = channel.totalMsgCount }
        }
        #expect(app.hasUnread == false)
        #expect(app.badgeLabel == nil)
        app.settings.showUnreadBadge = false
        other.teamUnreads["t1"] = TeamUnread(teamId: "t1", msgCount: 1, mentionCount: 2)
        #expect(app.badgeLabel == nil)
        #expect(app.unread(serverId: UUID()) == .none)
    }

    @Test func notificationsAndActivity() async throws {
        let harness = AppHarness()
        let app = harness.model()
        await app.startAll()
        var received: [MentionNotification] = []
        app.onNotification = { received.append($0) }
        let first = try #require(app.session(for: harness.first.id))
        let second = try #require(app.session(for: harness.second.id))
        let note = MentionNotification(serverId: harness.first.id, teamId: "t1", channelId: "c", postId: "p", rootId: "", title: "T", body: "B")
        first.onNotification?(note)
        #expect(received == [note])
        #expect(first.isAppActive())
        #expect(second.isAppActive() == false)
        app.isAppActive = { false }
        #expect(first.isAppActive() == false)
        app.stopAll()
        #expect(first.connection == .idle)
        #expect(second.connection == .idle)
    }
}

@MainActor
@Suite struct AppModelLoginTests {
    func loginRoute(_ server: MockServer, token: String = "fresh") {
        server.transport.on("POST", "users/login") { request in
            let body = request.jsonObject
            guard body["password"] as? String == "secret" else {
                return .error(401, id: "api.user.login.invalid_credentials_email_username", message: "Bad")
            }
            return .object(Fixtures.user("me1", "alice"), headers: ["Token": token])
        }
    }

    @Test func passwordLogin() async throws {
        let harness = AppHarness(tokens: false)
        loginRoute(harness.server)
        let app = harness.model()
        await app.startAll()
        await #expect(throws: APIError.self) {
            try await app.login(serverId: harness.first.id, loginId: "alice", password: "wrong")
        }
        #expect(app.needsLogin.contains(harness.first.id))
        try await app.login(serverId: harness.first.id, loginId: "alice", password: "secret")
        #expect(harness.credentials.token(for: harness.first.id) == "fresh")
        #expect(app.needsLogin == [harness.second.id])
        let session = try #require(app.selectedSession)
        #expect(session.connection == .connected)
        #expect(session.currentTeamId == "t1")
        #expect(harness.server.transport.last("GET", "users/me")?.value(forHTTPHeaderField: "Authorization") == "Bearer fresh")
        let login = try #require(harness.server.transport.last("POST", "users/login"))
        #expect(login.jsonObject["login_id"] as? String == "alice")
        #expect(login.jsonObject["token"] == nil)
        try await app.login(serverId: UUID(), loginId: "a", password: "secret")
    }

    @Test func mfaLogin() async throws {
        let harness = AppHarness(tokens: false)
        harness.server.transport.on("POST", "users/login") { request in
            guard request.jsonObject["token"] as? String == "123456" else {
                return .error(401, id: "mfa.validate_token.authenticate.app_error", message: "MFA")
            }
            return .object(Fixtures.user("me1", "alice"), headers: ["Token": "mfa-token"])
        }
        let app = harness.model()
        await #expect(throws: APIError.mfaRequired) {
            try await app.login(serverId: harness.second.id, loginId: "alice", password: "secret")
        }
        try await app.login(serverId: harness.second.id, loginId: "alice", password: "secret", mfaToken: "123456")
        #expect(harness.credentials.token(for: harness.second.id) == "mfa-token")
        #expect(app.session(for: harness.second.id)?.connection == .connected)
        #expect(app.session(for: harness.second.id)?.currentTeamId == nil)
    }

    @Test func accessTokenLogin() async throws {
        let harness = AppHarness(tokens: false)
        harness.server.transport.on("GET", "users/me") { request in
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer pat-1" else {
                return .error(401, id: "api.context.session_expired.app_error")
            }
            return .object(Fixtures.user("me1", "alice"))
        }
        let app = harness.model()
        await #expect(throws: APIError.self) {
            try await app.login(serverId: harness.first.id, accessToken: "bad")
        }
        #expect(harness.credentials.token(for: harness.first.id) == nil)
        try await app.login(serverId: harness.first.id, accessToken: "  pat-1\n")
        #expect(harness.credentials.token(for: harness.first.id) == "pat-1")
        #expect(app.selectedSession?.connection == .connected)
        try await app.login(serverId: UUID(), accessToken: "pat-1")
    }

    @Test func reloginReplacesSession() async throws {
        let harness = AppHarness()
        loginRoute(harness.server, token: "second-token")
        let app = harness.model()
        await app.startAll()
        let old = try #require(app.selectedSession)
        try await app.login(serverId: harness.first.id, loginId: "alice", password: "secret")
        let fresh = try #require(app.selectedSession)
        #expect(fresh !== old)
        #expect(old.connection == .idle)
        #expect(fresh.connection == .connected)
    }

    @Test func activateFailsWhenCredentialStoreFails() async throws {
        let harness = AppHarness(tokens: false)
        loginRoute(harness.server)
        let app = AppModel(store: harness.store, credentials: FailingCredentials(), transport: harness.server.transport, realtimeFactory: harness.server.realtimeFactory())
        await #expect(throws: CredentialStoreError.keychain(-1)) {
            try await app.login(serverId: harness.first.id, loginId: "alice", password: "secret")
        }
        #expect(app.session(for: harness.first.id) == nil)
    }

    @Test func logout() async throws {
        let harness = AppHarness()
        harness.server.transport.on("POST", "users/logout", .ok)
        let app = harness.model()
        await app.startAll()
        let session = try #require(app.selectedSession)
        await app.logout(serverId: harness.first.id)
        #expect(harness.server.transport.count("POST", "users/logout") == 1)
        #expect(session.connection == .idle)
        #expect(app.selectedSession == nil)
        #expect(harness.credentials.token(for: harness.first.id) == nil)
        #expect(app.needsLogin == [harness.first.id])
        await app.logout(serverId: harness.first.id)
        #expect(harness.server.transport.count("POST", "users/logout") == 1)
    }
}

final class FailingCredentials: CredentialStore {
    func token(for serverId: UUID) -> String? { nil }
    func setToken(_ token: String, for serverId: UUID) throws { throw CredentialStoreError.keychain(-1) }
    func removeToken(for serverId: UUID) {}
}

@MainActor
@Suite struct AppModelValidateTests {
    func app(_ transport: FakeTransport) -> AppModel {
        AppModel(store: MemoryAppStateStore(), credentials: MemoryCredentialStore(), transport: transport)
    }

    @Test func validatesServer() async throws {
        let transport = FakeTransport()
        transport.on("GET", "system/ping", .ok)
        transport.on("GET", "config/client", object: ["Version": "12.0.1", "SiteName": "Chat", "EnableSignInWithEmail": "true"])
        let (url, config) = try await app(transport).validate(url: " chat.example.com/ ")
        #expect(url.absoluteString == "https://chat.example.com")
        #expect(config.values["Version"] == "12.0.1")
    }

    @Test func rejectsInvalidURL() async {
        await #expect(throws: APIError.invalidURL("ftp://x")) {
            try await app(FakeTransport()).validate(url: "ftp://x")
        }
    }

    @Test func fallsBackToHTTP() async throws {
        let transport = FakeTransport()
        transport.on("GET", "system/ping") { request in
            if request.url?.scheme == "https" { throw FakeTransportError() }
            return .ok
        }
        transport.on("GET", "config/client", object: ["Version": "12.0.1"])
        let (url, _) = try await app(transport).validate(url: "192.168.1.5:8065")
        #expect(url.absoluteString == "http://192.168.1.5:8065")
        await #expect(throws: APIError.self) {
            try await app(transport).validate(url: "https://192.168.1.5:8065")
        }
    }

    @Test func reportsOriginalErrorWhenFallbackFails() async {
        let transport = FakeTransport()
        transport.on("GET", "system/ping") { _ in throw FakeTransportError() }
        await #expect(throws: APIError.transport("The network connection was lost.")) {
            try await app(transport).validate(url: "chat.example.com")
        }
        #expect(transport.requests.map { $0.url?.scheme } == ["https", "http"])
    }
}
