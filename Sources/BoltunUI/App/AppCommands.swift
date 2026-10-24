import BoltunKit
import SwiftUI

public struct AppCommands: Commands {
    let router: AppRouter

    public init(router: AppRouter) {
        self.router = router
    }

    private var model: AppModel { router.model }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Server…") { router.presentAddServer() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button(signOutTitle) { Task { await router.signOutCurrentServer() } }
                .disabled(model.selectedServer == nil || router.currentServerNeedsLogin)
            if router.currentServerNeedsLogin, let id = model.selectedServerId {
                Button("Log In…") { router.presentLogin(serverId: id) }
            }
        }

        CommandGroup(after: .textEditing) {
            Divider()
            Button("Search Messages") { router.focusSearch() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        CommandGroup(before: .toolbar) {
            Button(router.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") { router.toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            Button(router.isThreadPaneVisible ? "Hide Thread Pane" : "Show Thread Pane") { router.toggleThreadPane() }
                .keyboardShortcut(".", modifiers: .command)
            Divider()
            Button("Actual Size") { router.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
            Button("Zoom In") { router.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!router.canZoomIn)
            Button("Zoom Out") { router.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!router.canZoomOut)
            Divider()
        }

        CommandMenu("Go") {
            Button("Switch Channel…") { router.focusQuickSwitcher() }
                .keyboardShortcut("k", modifiers: .command)
            Button("Message Composer") { router.focusComposer() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            Button("Next Server") { Task { await router.selectNextServer() } }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled(model.servers.count < 2)
            Button("Previous Server") { Task { await router.selectPreviousServer() } }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled(model.servers.count < 2)
            Divider()
            ForEach(Array(model.servers.prefix(9).enumerated()), id: \.element.id) { index, server in
                Button(server.name) { Task { await router.selectServer(number: index + 1) } }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }

        CommandGroup(before: .windowList) {
            Button("Boltun") { router.showMainWindow() }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Divider()
        }

        CommandGroup(replacing: .help) {
            Button("Report an Issue…") { router.openExternalURL(AppInfo.issuesURL) }
            Button("Boltun on GitHub") { router.openExternalURL(AppInfo.repositoryURL) }
        }
    }

    var signOutTitle: String {
        model.selectedServer.map { "Sign Out of \($0.name)" } ?? "Sign Out"
    }
}

public struct StatusMenuContent: View {
    let router: AppRouter

    public init(router: AppRouter) {
        self.router = router
    }

    public var body: some View {
        let model = router.model
        Button("Open Boltun") { router.showMainWindow() }
        Divider()
        ForEach(model.servers) { server in
            Button(Self.title(server: server, unread: model.unread(serverId: server.id))) {
                Task {
                    router.showMainWindow()
                    await model.select(serverId: server.id)
                }
            }
        }
        if !model.servers.isEmpty { Divider() }
        Button("Settings…") { router.openSettings() }
        Button("Quit Boltun") { NSApp.terminate(nil) }
    }

    static func title(server: ServerConfig, unread: ChannelUnread) -> String {
        if unread.mentions > 0 { return "\(server.name) — \(unread.mentions) mention\(unread.mentions == 1 ? "" : "s")" }
        if unread.unread { return "\(server.name) — unread" }
        return server.name
    }
}
