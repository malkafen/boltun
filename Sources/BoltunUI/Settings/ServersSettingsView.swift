import BoltunKit
import SwiftUI

public struct ServersSettingsView: View {
    enum SheetRoute: Identifiable, Hashable {
        case add
        case edit(ServerConfig)
        case login(UUID)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let server): return "edit-\(server.id)"
            case .login(let id): return "login-\(id)"
            }
        }
    }

    let model: AppModel
    @State private var selection: UUID?
    @State private var sheet: SheetRoute?
    @State private var pendingRemoval: ServerConfig?

    public init(model: AppModel, selection: UUID? = nil) {
        self.model = model
        _selection = State(initialValue: selection)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            List(selection: $selection) {
                ForEach(model.servers) { server in
                    ServerRow(server: server, status: ServerStatus(model: model, serverId: server.id))
                        .tag(server.id)
                        .contextMenu { rowMenu(server) }
                }
                .onMove { model.moveServers(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds(.disabled)
            .overlay {
                if model.servers.isEmpty {
                    Text("No servers yet").foregroundStyle(Theme.textSecondary)
                }
            }
            controls
            Text("Drag servers to change their order in the sidebar.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(20)
        .sheet(item: $sheet) { route in
            sheetContent(route)
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "server")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { server in
            Button("Remove", role: .destructive) {
                Task { await model.removeServer(server.id) }
                if selection == server.id { selection = nil }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You will be signed out and the server will be removed from Boltun.")
        }
    }

    private var selectedServer: ServerConfig? {
        model.servers.first { $0.id == selection }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button { sheet = .add } label: { Image(systemName: "plus").frame(width: 16) }
                .help("Add Server")
                .accessibilityIdentifier("settings-add-server")
            Button { pendingRemoval = selectedServer } label: { Image(systemName: "minus").frame(width: 16) }
                .help("Remove Server")
                .disabled(selectedServer == nil)
            Spacer()
            if let server = selectedServer {
                Button("Edit…") { sheet = .edit(server) }
                if model.needsLogin.contains(server.id) {
                    Button("Log In…") { sheet = .login(server.id) }
                } else {
                    Button("Log Out") { Task { await model.logout(serverId: server.id) } }
                }
            }
        }
        .controlSize(.regular)
    }

    @ViewBuilder
    private func rowMenu(_ server: ServerConfig) -> some View {
        Button("Edit…") { sheet = .edit(server) }
        if model.needsLogin.contains(server.id) {
            Button("Log In…") { sheet = .login(server.id) }
        } else {
            Button("Log Out") { Task { await model.logout(serverId: server.id) } }
        }
        Divider()
        Button("Remove…", role: .destructive) { pendingRemoval = server }
    }

    @ViewBuilder
    private func sheetContent(_ route: SheetRoute) -> some View {
        switch route {
        case .add:
            ServerSetupFlow(model: model) { sheet = nil }
        case .edit(let server):
            EditServerView(viewModel: EditServerViewModel(model: model, server: server)) { sheet = nil }
        case .login(let id):
            ServerSetupFlow(model: model, stage: .login(id)) { sheet = nil }
        }
    }
}

public struct ServerStatus: Equatable {
    public enum Kind: Equatable {
        case connected
        case connecting
        case signedOut
        case offline
        case error(String)
    }

    public var kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    @MainActor
    public init(model: AppModel, serverId: UUID) {
        if model.needsLogin.contains(serverId) {
            kind = .signedOut
            return
        }
        switch model.session(for: serverId)?.connection {
        case .connected: kind = .connected
        case .connecting, .reconnecting: kind = .connecting
        case .unauthorized: kind = .signedOut
        case .failed(let message): kind = .error(message)
        case .idle, .none: kind = .offline
        }
    }

    public var label: String {
        switch kind {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .signedOut: return "Signed out"
        case .offline: return "Not connected"
        case .error(let message): return message
        }
    }

    public var color: Color {
        switch kind {
        case .connected: return Theme.online
        case .connecting: return Theme.away
        case .signedOut, .offline: return Theme.textSecondary
        case .error: return Theme.dnd
        }
    }
}

struct ServerRow: View {
    let server: ServerConfig
    let status: ServerStatus

    var body: some View {
        HStack(spacing: 10) {
            Text(server.initials)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(server.url.absoluteString)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(status.color).frame(width: 7, height: 7)
                Text(status.label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
