import Foundation
import Observation

@MainActor
@Observable
public final class AppModel {
    public private(set) var servers: [ServerConfig]
    public private(set) var sessions: [UUID: ServerSession] = [:]
    public var settings: AppSettings {
        didSet { persist() }
    }
    public private(set) var selectedServerId: UUID?
    public private(set) var needsLogin: Set<UUID> = []

    @ObservationIgnored let store: AppStateStoring
    @ObservationIgnored let credentials: CredentialStore
    @ObservationIgnored let transport: HTTPTransport
    @ObservationIgnored let realtimeFactory: ((URL, String) -> RealtimeClient)?
    @ObservationIgnored public var onNotification: ((MentionNotification) -> Void)?
    @ObservationIgnored public var isAppActive: () -> Bool = { true }

    public init(
        store: AppStateStoring,
        credentials: CredentialStore,
        transport: HTTPTransport = URLSessionTransport(),
        realtimeFactory: ((URL, String) -> RealtimeClient)? = nil
    ) {
        self.store = store
        self.credentials = credentials
        self.transport = transport
        self.realtimeFactory = realtimeFactory
        let state = store.load()
        servers = state.servers
        settings = state.settings
        selectedServerId = state.settings.lastServerId.flatMap { id in state.servers.contains { $0.id == id } ? id : nil } ?? state.servers.first?.id
    }

    public var selectedServer: ServerConfig? { servers.first { $0.id == selectedServerId } }

    public var selectedSession: ServerSession? { selectedServerId.flatMap { sessions[$0] } }

    public func session(for serverId: UUID) -> ServerSession? { sessions[serverId] }

    public func unread(serverId: UUID) -> ChannelUnread {
        sessions[serverId]?.totalUnread ?? .none
    }

    public var totalMentions: Int {
        servers.reduce(0) { $0 + unread(serverId: $1.id).mentions }
    }

    public var hasUnread: Bool {
        servers.contains { unread(serverId: $0.id).unread }
    }

    public var badgeLabel: String? {
        guard settings.showUnreadBadge else { return nil }
        let mentions = totalMentions
        if mentions > 0 { return mentions > 99 ? "99+" : String(mentions) }
        return hasUnread ? "•" : nil
    }

    public func startAll() async {
        await withTaskGroup(of: Void.self) { group in
            for server in servers {
                let session = makeSession(for: server)
                let serverId = server.id
                group.addTask {
                    await session.start()
                    await self.restoreSelectionIfSelected(serverId: serverId)
                }
            }
        }
    }

    func restoreSelectionIfSelected(serverId: UUID) async {
        guard selectedServerId == serverId else { return }
        await restoreSelection(serverId: serverId)
    }

    public func stopAll() {
        for session in sessions.values { session.stop() }
    }

    @discardableResult
    func makeSession(for server: ServerConfig) -> ServerSession {
        if let existing = sessions[server.id] { return existing }
        let token = credentials.token(for: server.id)
        let session = ServerSession(serverId: server.id, client: APIClient(baseURL: server.url, token: token, transport: transport), realtimeFactory: realtimeFactory)
        session.isAppActive = { [weak self] in
            guard let self else { return false }
            return self.isAppActive() && self.selectedServerId == server.id
        }
        session.onNotification = { [weak self] in self?.onNotification?($0) }
        session.onUnauthorized = { [weak self] in self?.needsLogin.insert(server.id) }
        session.onSelectionChange = { [weak self] teamId, channelId in
            self?.rememberSelection(serverId: server.id, teamId: teamId, channelId: channelId)
        }
        if token == nil { needsLogin.insert(server.id) }
        sessions[server.id] = session
        return session
    }

    func restoreSelection(serverId: UUID) async {
        guard let session = sessions[serverId], session.connection == .connected, session.currentTeamId == nil,
              let server = servers.first(where: { $0.id == serverId })
        else { return }
        let teamId = server.lastTeamId.flatMap { id in session.teams.contains { $0.id == id } ? id : nil } ?? session.teams.first?.id
        guard let teamId else { return }
        await session.selectTeam(teamId, channelId: server.lastChannelByTeam[teamId])
    }

    func rememberSelection(serverId: UUID, teamId: String?, channelId: String?) {
        guard let index = servers.firstIndex(where: { $0.id == serverId }) else { return }
        servers[index].lastTeamId = teamId
        if let teamId, let channelId { servers[index].lastChannelByTeam[teamId] = channelId }
        persist()
    }

    public func select(serverId: UUID) async {
        guard servers.contains(where: { $0.id == serverId }) else { return }
        selectedServerId = serverId
        settings.lastServerId = serverId
        await restoreSelection(serverId: serverId)
    }

    public func selectServer(at index: Int) async {
        guard servers.indices.contains(index) else { return }
        await select(serverId: servers[index].id)
    }

    public func validate(url raw: String) async throws -> (URL, ClientConfig) {
        let url = try APIClient.normalize(raw)
        let client = APIClient(baseURL: url, transport: transport)
        do {
            _ = try await client.ping()
            return (url, try await client.clientConfig())
        } catch let error as APIError {
            if case .invalidURL = error { throw error }
            if url.scheme == "https", !raw.contains("://"), let fallback = URL(string: url.absoluteString.replacingOccurrences(of: "https://", with: "http://")) {
                let insecure = APIClient(baseURL: fallback, transport: transport)
                if (try? await insecure.ping()) == true {
                    return (fallback, try await insecure.clientConfig())
                }
            }
            throw error
        }
    }

    @discardableResult
    public func addServer(name: String, url: URL) -> ServerConfig {
        if let existing = servers.first(where: { $0.url == url }) { return existing }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = ServerConfig(name: trimmed.isEmpty ? (url.host() ?? url.absoluteString) : trimmed, url: url)
        servers.append(server)
        needsLogin.insert(server.id)
        if selectedServerId == nil { selectedServerId = server.id }
        persist()
        return server
    }

    public func updateServer(_ server: ServerConfig) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        let urlChanged = servers[index].url != server.url
        servers[index].name = server.name
        servers[index].url = server.url
        if urlChanged {
            sessions[server.id]?.stop()
            sessions[server.id] = nil
            credentials.removeToken(for: server.id)
            needsLogin.insert(server.id)
        }
        persist()
    }

    public func removeServer(_ serverId: UUID) async {
        if let session = sessions[serverId] {
            session.stop()
            let client = session.client
            Task.detached { try? await client.logout() }
        }
        sessions[serverId] = nil
        credentials.removeToken(for: serverId)
        servers.removeAll { $0.id == serverId }
        needsLogin.remove(serverId)
        if selectedServerId == serverId { selectedServerId = servers.first?.id }
        settings.lastServerId = selectedServerId
        persist()
    }

    public func moveServers(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { servers[$0] }
        var remaining = servers.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(insertAt, remaining.count)))
        servers = remaining
        persist()
    }

    public func login(serverId: UUID, loginId: String, password: String, mfaToken: String? = nil) async throws {
        guard let server = servers.first(where: { $0.id == serverId }) else { return }
        let client = APIClient(baseURL: server.url, transport: transport)
        let result = try await client.login(loginId: loginId, password: password, mfaToken: mfaToken)
        try await activate(serverId: serverId, token: result.token)
    }

    public func login(serverId: UUID, accessToken: String) async throws {
        guard let server = servers.first(where: { $0.id == serverId }) else { return }
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await APIClient(baseURL: server.url, token: token, transport: transport).me()
        try await activate(serverId: serverId, token: token)
    }

    func activate(serverId: UUID, token: String) async throws {
        guard let server = servers.first(where: { $0.id == serverId }) else { return }
        try credentials.setToken(token, for: serverId)
        sessions[serverId]?.stop()
        sessions[serverId] = nil
        needsLogin.remove(serverId)
        let session = makeSession(for: server)
        await session.start()
        if selectedServerId == serverId { await restoreSelection(serverId: serverId) }
    }

    public func logout(serverId: UUID) async {
        if let session = sessions[serverId] {
            try? await session.client.logout()
            session.stop()
        }
        sessions[serverId] = nil
        credentials.removeToken(for: serverId)
        needsLogin.insert(serverId)
    }

    func persist() {
        try? store.save(AppState(servers: servers, settings: settings))
    }
}
