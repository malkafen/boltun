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

    var hintText: String? {
        switch hint {
        case .none: nil
        case .connecting: "Connecting…"
        case .reconnecting: "Reconnecting…"
        case .needsLogin: "Login required"
        case .failed: "Cannot connect"
        }
    }

    var tooltip: String {
        [name, hintText, shortcutLabel].compactMap(\.self).joined(separator: " — ")
    }

    var menuTitle: String {
        let label = SwitcherLabel.text(name: name, unread: ChannelUnread(unread: unread, mentions: mentions), current: selected)
        return [label, hintText].compactMap(\.self).joined(separator: " — ")
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

    static func otherServersUnread(_ tiles: [ServerTileModel]) -> ChannelUnread {
        tiles.filter { !$0.selected }.reduce(into: ChannelUnread()) { result, tile in
            result.unread = result.unread || tile.unread
            result.mentions += tile.mentions
        }
    }
}

enum SwitcherLabel {
    static func text(name: String, unread: ChannelUnread, current: Bool) -> String {
        var label = current ? "✓ \(name)" : name
        if unread.mentions > 0 {
            label += "  (\(BadgeText.count(unread.mentions)))"
        } else if unread.unread {
            label += "  •"
        }
        return label
    }
}

struct ServerMenuItems: View {
    let model: AppModel
    let onAddServer: () -> Void

    var body: some View {
        ForEach(ServerTileModel.make(model: model)) { tile in
            Button(tile.menuTitle) { Task { await model.select(serverId: tile.id) } }
        }
        Divider()
        Button("Add Server…", action: onAddServer)
    }
}

struct ServerSwitcher: View {
    let model: AppModel
    let onAddServer: () -> Void

    var body: some View {
        let tiles = ServerTileModel.make(model: model)
        Menu {
            ServerMenuItems(model: model, onAddServer: onAddServer)
        } label: {
            ServerSwitcherLabel(current: tiles.first(where: \.selected), others: ServerTileModel.otherServersUnread(tiles))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tiles.first(where: \.selected).map { "\($0.tooltip) — click to switch servers" } ?? "Add or switch servers")
    }
}

struct ServerSwitcherLabel: View {
    let current: ServerTileModel?
    let others: ChannelUnread

    var body: some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.railTile)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(current?.initials ?? "+")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                )
                .opacity(current?.hint == .needsLogin || current?.hint == .failed ? 0.55 : 1)
                .overlay(alignment: .topTrailing) { othersBadge.offset(x: 7, y: -5) }
                .overlay(alignment: .bottomTrailing) { hintIcon.offset(x: 5, y: 5) }
            HStack(spacing: 2) {
                Text(current?.name ?? "Servers")
                    .font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: 58)
        }
        .frame(width: LeftRail.width)
        .contentShape(Rectangle())
    }

    @ViewBuilder var othersBadge: some View {
        if others.mentions > 0 {
            CountBadge(count: others.mentions)
                .overlay(Capsule().strokeBorder(Theme.serverRail, lineWidth: 2))
        } else if others.unread {
            Circle().fill(Color.white).frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(Theme.serverRail, lineWidth: 2))
        }
    }

    @ViewBuilder var hintIcon: some View {
        switch current?.hint ?? .none {
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
