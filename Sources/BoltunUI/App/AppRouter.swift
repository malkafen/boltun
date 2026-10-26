import BoltunKit
import Foundation
import Observation
import SwiftUI

public enum AppSheet: Identifiable, Hashable, Sendable {
    case addServer
    case login(UUID)

    public var id: String {
        switch self {
        case .addServer: return "add-server"
        case .login(let id): return "login-\(id.uuidString)"
        }
    }
}

public enum AppCommand: Hashable, Sendable {
    case focusQuickSwitcher
    case focusSearch
    case focusComposer
    case toggleSidebar
    case toggleThreadPane
    case openThread(rootId: String)
    case highlightPost(postId: String)
}

public struct AppCommandEvent: Hashable, Sendable {
    public let sequence: Int
    public let command: AppCommand
}

@MainActor
@Observable
public final class AppRouter {
    public static let fontScaleRange: ClosedRange<Double> = 0.7...2.0
    public static let fontScaleStep = 0.1

    public let model: AppModel
    public var sheet: AppSheet?
    public var isSidebarVisible = true
    public var isThreadPaneVisible = false
    public var pendingThreadRootId: String?
    public var pendingPostId: String?
    public var settingsTab: SettingsTab = .general
    public private(set) var lastCommand: AppCommandEvent?
    public private(set) var lastRouteError: String?

    @ObservationIgnored public var showMainWindow: () -> Void = {}
    @ObservationIgnored public var openSettingsWindow: () -> Void = {}
    @ObservationIgnored public var openExternalURL: (URL) -> Void = { _ in }
    @ObservationIgnored public var connectionTimeout: Duration = .seconds(20)
    @ObservationIgnored let workspaces = WorkspaceRegistry()
    @ObservationIgnored private var sequence = 0

    public init(model: AppModel) {
        self.model = model
    }

    public func presentAddServer() {
        showMainWindow()
        sheet = .addServer
    }

    public func presentLogin(serverId: UUID) {
        guard model.servers.contains(where: { $0.id == serverId }) else { return }
        showMainWindow()
        sheet = .login(serverId)
    }

    public func dismissSheet() {
        sheet = nil
    }

    public func openSettings(tab: SettingsTab? = nil) {
        if let tab { settingsTab = tab }
        openSettingsWindow()
    }

    public func send(_ command: AppCommand) {
        sequence += 1
        lastCommand = AppCommandEvent(sequence: sequence, command: command)
        switch command {
        case .toggleSidebar:
            withAnimation(.easeInOut(duration: 0.2)) { isSidebarVisible.toggle() }
        case .toggleThreadPane:
            isThreadPaneVisible.toggle()
        case .openThread(let rootId):
            pendingThreadRootId = rootId
            isThreadPaneVisible = true
        case .highlightPost(let postId):
            pendingPostId = postId
        case .focusQuickSwitcher, .focusSearch, .focusComposer:
            break
        }
    }

    public func focusQuickSwitcher() { send(.focusQuickSwitcher) }
    public func focusSearch() { send(.focusSearch) }
    public func focusComposer() { send(.focusComposer) }
    public func toggleSidebar() { send(.toggleSidebar) }
    public func toggleThreadPane() { send(.toggleThreadPane) }

    public func consumePendingThreadRootId() -> String? {
        defer { pendingThreadRootId = nil }
        return pendingThreadRootId
    }

    public func consumePendingPostId() -> String? {
        defer { pendingPostId = nil }
        return pendingPostId
    }

    public var selectedIndex: Int? {
        model.servers.firstIndex { $0.id == model.selectedServerId }
    }

    public func selectServer(number: Int) async {
        await model.selectServer(at: number - 1)
    }

    public func selectNextServer() async {
        await cycleServer(by: 1)
    }

    public func selectPreviousServer() async {
        await cycleServer(by: -1)
    }

    func cycleServer(by offset: Int) async {
        let count = model.servers.count
        guard count > 1 else { return }
        let current = selectedIndex ?? 0
        await model.selectServer(at: ((current + offset) % count + count) % count)
    }

    public func zoomIn() { setFontScale(model.settings.fontScale + Self.fontScaleStep) }
    public func zoomOut() { setFontScale(model.settings.fontScale - Self.fontScaleStep) }
    public func resetZoom() { setFontScale(1.0) }

    public var canZoomIn: Bool { model.settings.fontScale < Self.fontScaleRange.upperBound - 0.001 }
    public var canZoomOut: Bool { model.settings.fontScale > Self.fontScaleRange.lowerBound + 0.001 }

    func setFontScale(_ value: Double) {
        let clamped = min(max((value * 10).rounded() / 10, Self.fontScaleRange.lowerBound), Self.fontScaleRange.upperBound)
        guard clamped != model.settings.fontScale else { return }
        model.settings.fontScale = clamped
    }

    public var currentServerNeedsLogin: Bool {
        model.selectedServerId.map { model.needsLogin.contains($0) } ?? false
    }

    public func signOutCurrentServer() async {
        guard let id = model.selectedServerId else { return }
        await model.logout(serverId: id)
        presentLogin(serverId: id)
    }

    public func presentLoginIfNeeded() {
        guard sheet == nil, let id = model.selectedServerId, model.needsLogin.contains(id) else { return }
        presentLogin(serverId: id)
    }

    public func route(serverId: UUID, teamId: String?, channelId: String?, rootId: String? = nil) async {
        showMainWindow()
        guard model.servers.contains(where: { $0.id == serverId }) else { return }
        if model.selectedServerId != serverId { await model.select(serverId: serverId) }
        guard let session = await connectedSession(serverId) else { return }
        if let teamId, !teamId.isEmpty, session.teams.contains(where: { $0.id == teamId }) {
            await session.selectTeam(teamId, channelId: channelId)
        }
        if let channelId, !channelId.isEmpty {
            if session.currentChannelId == channelId {
                await session.markCurrentChannelViewedIfUnread()
            } else {
                await session.selectChannel(channelId)
            }
        }
        if let rootId, !rootId.isEmpty {
            send(.openThread(rootId: rootId))
        }
    }

    func connectedSession(_ serverId: UUID) async -> ServerSession? {
        let model = self.model
        let ready = await Observe.until(timeout: connectionTimeout) {
            model.session(for: serverId)?.connection == .connected || model.needsLogin.contains(serverId)
        }
        guard ready, let session = model.session(for: serverId), session.connection == .connected else {
            if model.needsLogin.contains(serverId) { presentLogin(serverId: serverId) }
            return nil
        }
        return session
    }

    func reportRouteError(_ message: String?) {
        lastRouteError = message
    }
}
