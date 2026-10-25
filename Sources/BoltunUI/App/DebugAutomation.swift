import AppKit
import BoltunKit
import Foundation

public struct AutomationState: Codable, Equatable, Sendable {
    public struct Server: Codable, Equatable, Sendable {
        public var index: Int
        public var id: String
        public var name: String
        public var url: String
        public var connection: String
        public var needsLogin: Bool
        public var user: String?
        public var teams: [String]
        public var favoriteTeams: [String]
        public var mutedTeams: [String]
        public var team: String?
        public var channel: String?
        public var channelDisplayName: String?
        public var unread: Bool
        public var mentions: Int
        public var visiblePostCount: Int
        public var lastError: String?
    }

    public var servers: [Server]
    public var selectedServer: Int?
    public var badge: String?
    public var sheet: String?
    public var windowVisible: Bool
    public var sidebarVisible: Bool
    public var threadPaneVisible: Bool
    public var pendingThreadRootId: String?
    public var fontScale: Double
    public var lastRouteError: String?
    var ui: AutomationUIState?

    @MainActor
    public init(model: AppModel, router: AppRouter, windowVisible: Bool) {
        servers = model.servers.enumerated().map { index, server in
            let session = model.session(for: server.id)
            let unread = model.unread(serverId: server.id)
            let channelId = session?.currentChannelId
            return Server(
                index: index,
                id: server.id.uuidString,
                name: server.name,
                url: server.url.absoluteString,
                connection: session.map { Self.describe($0.connection) } ?? "none",
                needsLogin: model.needsLogin.contains(server.id),
                user: session?.me?.username,
                teams: session?.orderedTeams.map(\.name) ?? [],
                favoriteTeams: session?.teamSections.favorites.map(\.name) ?? [],
                mutedTeams: session.map { active in active.orderedTeams.filter { active.isMuted(teamId: $0.id) }.map(\.name) } ?? [],
                team: session?.currentTeam?.name,
                channel: session?.currentChannel?.name,
                channelDisplayName: session?.currentChannel.map { session!.displayName(channel: $0) },
                unread: unread.unread,
                mentions: unread.mentions,
                visiblePostCount: channelId.map { session?.timelinePosts(channelId: $0).count ?? 0 } ?? 0,
                lastError: session?.lastError
            )
        }
        selectedServer = router.selectedIndex
        badge = model.badgeLabel
        sheet = router.sheet?.id
        self.windowVisible = windowVisible
        sidebarVisible = router.isSidebarVisible
        threadPaneVisible = router.isThreadPaneVisible
        pendingThreadRootId = router.pendingThreadRootId
        fontScale = model.settings.fontScale
        lastRouteError = router.lastRouteError
    }

    static func describe(_ state: ConnectionState) -> String {
        switch state {
        case .idle: return "idle"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reconnecting: return "reconnecting"
        case .unauthorized: return "unauthorized"
        case .failed(let message): return "failed: \(message)"
        }
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

@MainActor
public protocol AutomationHost: AnyObject {
    var mainWindow: NSWindow? { get }
    func showMainWindow()
    func deliverTestNotification(title: String, body: String) async
    func activateNotification(_ route: NotificationRoute) async
    func terminate()
}

public enum AutomationError: Error, Equatable, LocalizedError {
    case disabled
    case invalidCommand
    case noWindow(String)
    case renderFailed
    case noServer(Int)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .disabled: return "automation disabled"
        case .invalidCommand: return "invalid command"
        case .noWindow(let target): return "no \(target) window"
        case .renderFailed: return "render failed"
        case .noServer(let index): return "no server at index \(index)"
        case .failed(let message): return message
        }
    }
}

@MainActor
public final class DebugAutomation {
    public nonisolated static let logPath = "/tmp/boltun-automation.log"

    let router: AppRouter
    weak var host: AutomationHost?
    let isEnabled: () -> Bool
    let log: (String) -> Void
    let probe: AutomationProbe

    public init(
        router: AppRouter,
        host: AutomationHost?,
        probe: AutomationProbe = .shared,
        isEnabled: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: DebugCommand.defaultsKey) },
        log: @escaping (String) -> Void = DebugAutomation.appendToLog
    ) {
        self.router = router
        self.host = host
        self.probe = probe
        self.isEnabled = isEnabled
        self.log = log
    }

    var model: AppModel { router.model }

    @discardableResult
    public func handle(_ url: URL) async -> Bool {
        guard DebugCommand.isDebugURL(url), isEnabled() else { return false }
        guard let command = DebugCommand(url: url) else {
            log("error \(url.path()) invalid command")
            return true
        }
        if !command.isProbe { probe.commandReceived() }
        do {
            let detail = try await perform(command)
            log("ok \(url.path())\(detail.isEmpty ? "" : " " + detail)")
        } catch {
            log("error \(url.path()) \(error.localizedDescription)")
        }
        return true
    }

    func perform(_ command: DebugCommand) async throws -> String {
        switch command {
        case .snapshot(let path, let target):
            let window = try window(for: target)
            let overlays = target == .popover ? Self.popoverWindows(excluding: window) : []
            guard let data = Snapshot.png(of: window, overlays: overlays, overlayFill: NSColor(Theme.popover)) else { throw AutomationError.renderFailed }
            try Snapshot.write(data, to: path)
            return path
        case .addServer(let url, let name):
            let resolved: URL
            let config: ClientConfig
            do {
                (resolved, config) = try await model.validate(url: url)
            } catch {
                throw AutomationError.failed(AddServerViewModel.describe(error))
            }
            let server = model.addServer(name: name ?? config.siteName, url: resolved)
            await model.select(serverId: server.id)
            return server.id.uuidString
        case .login(let index, let user, let password):
            let server = try server(at: index)
            try await model.login(serverId: server.id, loginId: user, password: password)
            if router.sheet == .login(server.id) { router.dismissSheet() }
            return Self.connectionSummary(model.session(for: server.id))
        case .logout(let index):
            await model.logout(serverId: try server(at: index).id)
            return ""
        case .removeServer(let index):
            let server = try server(at: index)
            await model.removeServer(server.id)
            return server.id.uuidString
        case .setting(let name, let value):
            switch name {
            case "spellChecking": model.settings.spellChecking = DebugCommand.flag(value)
            case "collapsedThreads": model.settings.collapsedThreads = DebugCommand.flag(value)
            case "showReadStatus": model.settings.showReadStatus = DebugCommand.flag(value)
            default: throw AutomationError.failed("unknown setting \(name)")
            }
            return value
        case .select(let index, let team, let channel):
            let server = try server(at: index)
            await model.select(serverId: server.id)
            if let team {
                guard let session = await router.connectedSession(server.id),
                      await session.open(teamName: team, channelName: channel)
                else { throw AutomationError.failed("could not open \(team)/\(channel ?? "")") }
            }
            return ""
        case .open(let url):
            return await router.open(url: url) ? "" : (router.lastRouteError ?? "not routed")
        case .state(let path):
            var state = AutomationState(model: model, router: router, windowVisible: host?.mainWindow?.isVisible ?? false)
            state.ui = uiState()
            try Snapshot.write(try state.json(), to: path)
            return path
        case .present(let sheet, let index):
            switch sheet {
            case "add-server":
                router.presentAddServer()
            case "login":
                router.presentLogin(serverId: try server(at: index ?? router.selectedIndex ?? 0).id)
            case "browse":
                try currentWorkspace().showBrowseChannels = true
            case "dm":
                try currentWorkspace().showDirectMessages = true
            case "notifications":
                let workspace = try currentWorkspace()
                workspace.notificationPreferences = ChannelNotificationsTarget(id: try currentChannelId(workspace.session))
            default:
                throw AutomationError.invalidCommand
            }
            return ""
        case .settings(let tab):
            router.openSettings(tab: tab)
            return ""
        case .dismiss:
            router.dismissSheet()
            return ""
        case .show:
            host?.showMainWindow()
            return ""
        case .close:
            host?.mainWindow?.performClose(nil)
            return ""
        case .notify(let title, let body):
            await host?.deliverTestNotification(title: title, body: body)
            return ""
        case .quit:
            host?.terminate()
            return ""
        case .notificationClick(let index, let team, let channel, let root):
            await host?.activateNotification(NotificationRoute(serverId: try server(at: index).id, teamId: team, channelId: channel, rootId: root))
            return ""
        case .probe(let request):
            return try await performProbe(request)
        default:
            return try await performInteraction(command)
        }
    }

    func server(at index: Int) throws -> ServerConfig {
        guard model.servers.indices.contains(index) else { throw AutomationError.noServer(index) }
        return model.servers[index]
    }

    func window(for target: DebugCommand.WindowTarget) throws -> NSWindow {
        let found: NSWindow?
        switch target {
        case .main, .popover: found = host?.mainWindow
        case .sheet: found = host?.mainWindow?.attachedSheet
        case .settings: found = NSApp.windows.first { $0.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true && $0.isVisible }
        case .key: found = NSApp.keyWindow
        case .viewer: found = ImageViewerPresenter.shared.window
        }
        guard let found else { throw AutomationError.noWindow(target.rawValue) }
        return found
    }

    static func popoverWindows(excluding window: NSWindow) -> [NSWindow] {
        NSApp.windows.filter { $0 !== window && $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
    }

    static func connectionSummary(_ session: ServerSession?) -> String {
        session.map { AutomationState.describe($0.connection) } ?? "none"
    }

    public nonisolated static func appendToLog(_ line: String) {
        let entry = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        guard let data = entry.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: data)
        }
    }
}
