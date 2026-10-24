import Foundation
import SwiftUI
import Testing
@testable import BoltunKit
@testable import BoltunUI

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["BOLTUN_LIVE_SERVER"] != nil))
@MainActor
struct MainLiveTests {
    var environment: [String: String] { ProcessInfo.processInfo.environment }

    func server(_ raw: String, name: String) async throws -> (ServerConfig, String) {
        let url = try APIClient.normalize(raw)
        let result = try await APIClient(baseURL: url).login(loginId: environment["BOLTUN_LIVE_USER"] ?? "boltun", password: environment["BOLTUN_LIVE_PASSWORD"] ?? "Boltun-pass1")
        return (ServerConfig(name: name, url: url), result.token)
    }

    @Test func liveMainWindowSnapshot() async throws {
        var servers: [ServerConfig] = []
        var tokens: [UUID: String] = [:]
        let (primary, token) = try await server(environment["BOLTUN_LIVE_SERVER"]!, name: "Boltun Test")
        servers.append(primary)
        tokens[primary.id] = token
        if let raw = environment["BOLTUN_LIVE_SERVER2"], let (second, secondToken) = try? await server(raw, name: "Second Server") {
            servers.append(second)
            tokens[second.id] = secondToken
        }
        let model = AppModel(store: MemoryAppStateStore(AppState(servers: servers)), credentials: MemoryCredentialStore(tokens))
        await model.startAll()
        defer { model.stopAll() }
        let session = try #require(model.selectedSession)
        #expect(session.connection == .connected)
        #expect(await eventually(timeout: .seconds(10)) { session.currentChannelId != nil })
        let busiest = session.channels.values
            .filter { $0.teamId == session.currentTeamId && $0.type == .open && session.members[$0.id] != nil }
            .max { $0.totalMsgCount < $1.totalMsgCount }
        if let busiest { await session.selectChannel(busiest.id) }
        let channelId = try #require(session.currentChannelId)
        #expect(await eventually(timeout: .seconds(10)) { session.timelines[channelId]?.loaded == true })
        _ = await eventually(timeout: .seconds(3)) { session.timelinePosts(channelId: channelId).allSatisfy { session.users[$0.userId] != nil } }
        let view = MainView(model: model)
        let rep = await Snapshot.render(view, size: CGSize(width: 1280, height: 800), name: "main-live", settle: .seconds(3))
        #expect(Snapshot.distinctColors(rep) > 12)

        if let root = session.timelinePosts(channelId: channelId).last(where: { !$0.isSystemMessage && !$0.isDeleted }) {
            let workspace = Workspace(session: session, serverURL: primary.url)
            await workspace.openThread(rootId: root.threadId)
            workspace.searchQuery = "deploy"
            await Snapshot.render(WorkspaceView(workspace: workspace), size: CGSize(width: 1280, height: 800), name: "main-live-thread", settle: .seconds(2))
            await workspace.search()
            await Snapshot.render(WorkspaceView(workspace: workspace), size: CGSize(width: 1280, height: 800), name: "main-live-search", settle: .seconds(2))
            workspace.showQuickSwitcher = true
            await Snapshot.render(WorkspaceView(workspace: workspace), size: CGSize(width: 1280, height: 800), name: "main-live-switcher", settle: .seconds(1))
        }
    }
}
