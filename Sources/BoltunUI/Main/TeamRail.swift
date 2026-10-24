import BoltunKit
import SwiftUI

struct TeamTileModel: Equatable, Identifiable {
    var id: String
    var name: String
    var initials: String
    var index: Int
    var selected: Bool
    var unread: Bool
    var mentions: Int
    var iconURL: URL?

    var shortcutLabel: String? { index < 9 ? "⌃⌘\(index + 1)" : nil }

    var tooltip: String {
        [name, shortcutLabel].compactMap(\.self).joined(separator: " — ")
    }

    @MainActor
    static func make(session: ServerSession) -> [TeamTileModel] {
        session.teams.enumerated().map { index, team in
            let unread = session.teamUnread(teamId: team.id)
            return TeamTileModel(
                id: team.id,
                name: team.displayName.isEmpty ? team.name : team.displayName,
                initials: team.initials,
                index: index,
                selected: team.id == session.currentTeamId,
                unread: unread.unread,
                mentions: unread.mentions,
                iconURL: team.lastTeamIconUpdate > 0 ? session.client.teamIconURL(teamId: team.id, lastIconUpdate: team.lastTeamIconUpdate) : nil
            )
        }
    }
}

enum TeamNavigator {
    static func team(number: Int, in ids: [String]) -> String? {
        ids.indices.contains(number - 1) ? ids[number - 1] : nil
    }
}

extension ServerSession {
    func switchTeam(id: String) async {
        guard id != currentTeamId else { return }
        await selectTeam(id)
    }

    func switchTeam(number: Int) async {
        guard let id = TeamNavigator.team(number: number, in: teams.map(\.id)) else { return }
        await switchTeam(id: id)
    }

    func cycleTeam(offset: Int) async {
        guard let id = ChannelNavigator.adjacent(in: teams.map(\.id), from: currentTeamId, offset: offset) else { return }
        await switchTeam(id: id)
    }
}

struct LeftRail: View {
    let model: AppModel
    let onAddServer: () -> Void

    static let width: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            ServerSwitcher(model: model, onAddServer: onAddServer)
                .padding(.top, 12)
            Rectangle().fill(Theme.separator).frame(width: 32, height: 1).padding(.vertical, 10)
            if let session = currentSession {
                TeamList(session: session)
            } else {
                Spacer()
            }
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Theme.serverRail)
    }

    var currentSession: ServerSession? {
        guard let id = model.selectedServerId, !model.needsLogin.contains(id) else { return nil }
        return model.session(for: id)
    }
}

struct TeamList: View {
    let session: ServerSession

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 8) {
                ForEach(TeamTileModel.make(session: session)) { tile in
                    TeamTile(tile: tile, client: session.client) {
                        Task { await session.switchTeam(id: tile.id) }
                    }
                    .equatable()
                }
            }
            .padding(.bottom, 12)
        }
    }
}

struct TeamTile: View, Equatable {
    let tile: TeamTileModel
    let client: APIClient?
    let action: () -> Void
    @State private var hovering = false

    nonisolated static func == (lhs: TeamTile, rhs: TeamTile) -> Bool {
        MainActor.assumeIsolated { lhs.tile == rhs.tile }
    }

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
                icon
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: tile.selected || hovering ? 12 : 16))
                    .opacity(tile.selected || hovering ? 1 : 0.8)
                    .overlay(alignment: .topTrailing) { badge.offset(x: 7, y: -5) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(tile.tooltip)
            Spacer(minLength: 0)
        }
        .frame(width: LeftRail.width, height: 44)
    }

    var icon: some View {
        RemoteImage(url: tile.iconURL, client: client, maxPixel: 96) {
            Rectangle()
                .fill(tile.selected ? Theme.railTileSelected : Theme.railTile)
                .overlay(
                    Text(tile.initials)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(tile.selected ? .white : Theme.textPrimary)
                )
        }
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
}
