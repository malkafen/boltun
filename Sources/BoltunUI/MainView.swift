import AppKit
import BoltunKit
import SwiftUI

public struct MainView: View {
    let model: AppModel
    let onAddServer: () -> Void
    let onLogin: (UUID) -> Void
    @Environment(\.appRouter) private var router
    @State private var localRegistry = WorkspaceRegistry()

    var registry: WorkspaceRegistry { router?.workspaces ?? localRegistry }

    public init(model: AppModel, onAddServer: @escaping () -> Void = {}, onLogin: @escaping (UUID) -> Void = { _ in }) {
        self.model = model
        self.onAddServer = onAddServer
        self.onLogin = onLogin
    }

    public var body: some View {
        HStack(spacing: 0) {
            ServerRail(model: model, onAddServer: onAddServer)
            Rectangle().fill(Color.black.opacity(0.35)).frame(width: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.content)
        .background { WindowTitleView(model: model) }
        .frame(minWidth: 860, minHeight: 520)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onChange(of: model.servers.map(\.id)) { _, ids in registry.prune(keeping: Set(ids)) }
    }

    @ViewBuilder var content: some View {
        if model.servers.isEmpty {
            NoServersView(onAddServer: onAddServer)
        } else if let server = model.selectedServer {
            if model.needsLogin.contains(server.id) {
                LoginPlaceholder(serverName: server.name, serverURL: server.url) { onLogin(server.id) }
            } else if let session = model.session(for: server.id) {
                WorkspaceView(workspace: registry.workspace(for: session, serverURL: server.url), server: server)
                    .id(ObjectIdentifier(session))
            } else {
                ConnectingView(serverName: server.name)
            }
        } else {
            NoServersView(onAddServer: onAddServer)
        }
    }
}

@MainActor
final class WorkspaceRegistry {
    private var workspaces: [UUID: Workspace] = [:]

    func workspace(for session: ServerSession, serverURL: URL) -> Workspace {
        if let existing = workspaces[session.serverId], existing.session === session, existing.serverURL == serverURL {
            return existing
        }
        let workspace = Workspace(session: session, serverURL: serverURL)
        workspaces[session.serverId] = workspace
        return workspace
    }

    func existing(serverId: UUID) -> Workspace? {
        workspaces[serverId]
    }

    func prune(keeping ids: Set<UUID>) {
        workspaces = workspaces.filter { ids.contains($0.key) }
    }

    var count: Int { workspaces.count }
}

struct WorkspaceView: View {
    @Bindable var workspace: Workspace
    var server: ServerConfig?
    @Environment(\.appRouter) private var router
    @State private var sidebarWidth: CGFloat = 250
    @State private var paneWidth: CGFloat = 400

    var body: some View {
        let session = workspace.session
        HStack(spacing: 0) {
            if router?.isSidebarVisible ?? true {
                HStack(spacing: 0) {
                    ChannelSidebar(workspace: workspace)
                        .frame(width: sidebarWidth)
                    ResizeHandle(width: $sidebarWidth, range: 200...380, direction: 1)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            ChannelView(workspace: workspace)
                .frame(minWidth: 380)
            if workspace.rightPane != nil {
                ResizeHandle(width: $paneWidth, range: 300...640, direction: -1)
                RightPaneView(workspace: workspace)
                    .frame(width: paneWidth)
            }
        }
        .overlay {
            if workspace.showQuickSwitcher {
                QuickSwitcherView(workspace: workspace)
            }
        }
        .background { WorkspaceShortcuts(workspace: workspace) }
        .sheet(isPresented: $workspace.showBrowseChannels) { BrowseChannelsSheet(workspace: workspace) }
        .sheet(isPresented: $workspace.showDirectMessages) { DirectMessageSheet(workspace: workspace) }
        .sheet(item: $workspace.previewFile) { file in ImagePreviewSheet(workspace: workspace, file: file) }
        .alert("Delete message?", isPresented: Binding(get: { workspace.pendingDeletion != nil }, set: { if !$0 { workspace.pendingDeletion = nil } })) {
            Button("Delete", role: .destructive) { Task { await workspace.confirmDelete() } }
            Button("Cancel", role: .cancel) { workspace.pendingDeletion = nil }
        } message: {
            Text("This message will be permanently deleted for everyone.")
        }
        .environment(\.openURL, OpenURLAction { url in
            Task { await workspace.handle(link: url) }
            return .handled
        })
        .task(id: session.connection == .connected) {
            guard session.connection == .connected, session.currentTeamId == nil,
                  let target = SelectionRestore.target(teams: session.teams, server: server)
            else { return }
            await session.selectTeam(target.teamId, channelId: target.channelId)
        }
        .task { await workspace.consumePendingRoute(router) }
        .onChange(of: router?.lastCommand) { _, event in
            guard let event else { return }
            Task { await workspace.perform(event.command, router: router) }
        }
        .onChange(of: workspace.rightPane != nil, initial: true) { _, visible in
            if router?.isThreadPaneVisible != visible { router?.isThreadPaneVisible = visible }
        }
    }
}

struct WindowTitleView: View {
    let model: AppModel

    var body: some View {
        WindowTitleSetter(title: WindowTitle.text(model: model))
            .frame(width: 0, height: 0)
    }
}

enum WindowTitle {
    @MainActor
    static func text(model: AppModel) -> String {
        guard let server = model.selectedServer else { return "Boltun" }
        guard let session = model.session(for: server.id), let channel = session.currentChannel else { return server.name }
        return "\(session.displayName(channel: channel)) — \(server.name)"
    }
}

struct WindowTitleSetter: NSViewRepresentable {
    let title: String

    final class TitleView: NSView {
        var title = "" {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            if let window, window.title != title { window.title = title }
        }
    }

    func makeNSView(context: Context) -> TitleView {
        let view = TitleView()
        view.title = title
        return view
    }

    func updateNSView(_ view: TitleView, context: Context) {
        view.title = title
    }
}

struct WorkspaceShortcuts: View {
    let workspace: Workspace

    var body: some View {
        ZStack {
            HiddenShortcut(key: .upArrow, modifiers: [.option, .command]) { Task { await workspace.navigate(offset: -1) } }
            HiddenShortcut(key: .downArrow, modifiers: [.option, .command]) { Task { await workspace.navigate(offset: 1) } }
            HiddenShortcut(key: .upArrow, modifiers: [.option, .shift]) { Task { await workspace.navigateUnread(forward: false) } }
            HiddenShortcut(key: .downArrow, modifiers: [.option, .shift]) { Task { await workspace.navigateUnread(forward: true) } }
        }
    }
}

struct ResizeHandle: View {
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    let direction: CGFloat
    @State private var start: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.3))
            .frame(width: 1)
            .overlay(
                Color.clear
                    .frame(width: 7)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let origin = start ?? width
                                if start == nil { start = width }
                                width = min(range.upperBound, max(range.lowerBound, origin + direction * value.translation.width))
                            }
                            .onEnded { _ in start = nil }
                    )
            )
    }
}

struct LoginPlaceholder: View {
    let serverName: String
    let serverURL: URL
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 46))
                .foregroundStyle(Theme.textSecondary)
            Text(serverName).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text(serverURL.absoluteString).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
            Text("You need to log in to this server to see your messages.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Button(action: onLogin) {
                Text("Log in")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.content)
    }
}

struct NoServersView: View {
    let onAddServer: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "server.rack").font(.system(size: 44)).foregroundStyle(Theme.textSecondary)
            Text("No servers yet").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text("Add a Mattermost server to get started.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            Button(action: onAddServer) {
                Text("Add Server")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.content)
    }
}

struct ConnectingView: View {
    let serverName: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Connecting to \(serverName)…").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.content)
    }
}

enum SelectionRestore {
    static func target(teams: [Team], server: ServerConfig?) -> (teamId: String, channelId: String?)? {
        let remembered = server?.lastTeamId.flatMap { id in teams.contains { $0.id == id } ? id : nil }
        guard let teamId = remembered ?? teams.first?.id else { return nil }
        return (teamId, server?.lastChannelByTeam[teamId])
    }
}
