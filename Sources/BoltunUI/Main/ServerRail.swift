import BoltunKit
import SwiftUI

struct ServerTileModel: Equatable, Identifiable {
    enum Hint: Equatable {
        case none
        case connecting
        case reconnecting
        case needsLogin
        case failed
    }

    var id: UUID
    var name: String
    var initials: String
    var index: Int
    var selected: Bool
    var unread: Bool
    var mentions: Int
    var hint: Hint

    var shortcutLabel: String? { index < 9 ? "⌘\(index + 1)" : nil }

    var tooltip: String {
        var parts = [name]
        switch hint {
        case .none: break
        case .connecting: parts.append("Connecting…")
        case .reconnecting: parts.append("Reconnecting…")
        case .needsLogin: parts.append("Login required")
        case .failed: parts.append("Cannot connect")
        }
        if let shortcutLabel { parts.append(shortcutLabel) }
        return parts.joined(separator: " — ")
    }

    @MainActor
    static func make(model: AppModel) -> [ServerTileModel] {
        model.servers.enumerated().map { index, server in
            let unread = model.unread(serverId: server.id)
            return ServerTileModel(
                id: server.id,
                name: server.name,
                initials: server.initials,
                index: index,
                selected: server.id == model.selectedServerId,
                unread: unread.unread,
                mentions: unread.mentions,
                hint: hint(needsLogin: model.needsLogin.contains(server.id), connection: model.session(for: server.id)?.connection)
            )
        }
    }

    static func hint(needsLogin: Bool, connection: ConnectionState?) -> Hint {
        if needsLogin { return .needsLogin }
        switch connection {
        case .connecting: return .connecting
        case .reconnecting: return .reconnecting
        case .unauthorized: return .needsLogin
        case .failed: return .failed
        default: return .none
        }
    }
}

struct ServerRail: View {
    let model: AppModel
    let onAddServer: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(ServerTileModel.make(model: model)) { tile in
                        ServerTile(tile: tile) { Task { await model.select(serverId: tile.id) } }
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            Rectangle().fill(Theme.separator).frame(width: 32, height: 1).padding(.vertical, 8)
            Button(action: onAddServer) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("Add a server")
            .padding(.bottom, 14)
        }
        .frame(width: 64)
        .frame(maxHeight: .infinity)
        .background(Theme.serverRail)
    }
}

struct ServerTile: View {
    let tile: ServerTileModel
    let action: () -> Void
    @State private var hovering = false

    var indicatorHeight: CGFloat {
        if tile.selected { return 32 }
        if hovering { return 18 }
        return tile.unread || tile.mentions > 0 ? 8 : 0
    }

    var body: some View {
        HStack(spacing: 0) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 3, topTrailingRadius: 3)
                .fill(Color.white)
                .frame(width: 4, height: indicatorHeight)
                .animation(.easeOut(duration: 0.12), value: indicatorHeight)
            Spacer(minLength: 0)
            Button(action: action) {
                RoundedRectangle(cornerRadius: tile.selected || hovering ? 12 : 16)
                    .fill(tile.selected ? Theme.railTileSelected : Theme.railTile)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(tile.initials)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(tile.selected ? .white : Theme.textPrimary)
                    )
                    .opacity(tile.hint == .needsLogin || tile.hint == .failed ? 0.55 : 1)
                    .overlay(alignment: .topTrailing) { badge.offset(x: 7, y: -5) }
                    .overlay(alignment: .bottomTrailing) { hintIcon.offset(x: 5, y: 5) }
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(tile.tooltip)
            Spacer(minLength: 0)
        }
        .frame(width: 64, height: 44)
    }

    @ViewBuilder var badge: some View {
        if tile.mentions > 0 {
            CountBadge(count: tile.mentions)
                .overlay(Capsule().strokeBorder(Theme.serverRail, lineWidth: 2))
        } else if tile.unread && !tile.selected {
            Circle().fill(Color.white).frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(Theme.serverRail, lineWidth: 2))
        }
    }

    @ViewBuilder var hintIcon: some View {
        switch tile.hint {
        case .none:
            EmptyView()
        case .connecting, .reconnecting:
            hintCircle("arrow.triangle.2.circlepath", color: Theme.warning)
        case .needsLogin:
            hintCircle("key.fill", color: Theme.warning)
        case .failed:
            hintCircle("exclamationmark", color: Theme.mention)
        }
    }

    func hintCircle(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 7.5, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 15, height: 15)
            .background(Circle().fill(color))
            .overlay(Circle().strokeBorder(Theme.serverRail, lineWidth: 2))
    }
}
