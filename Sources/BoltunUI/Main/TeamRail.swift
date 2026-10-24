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
    var favorite = false
    var muted = false
    var previousId: String?
    var nextId: String?

    var shortcutLabel: String? { index < 9 ? "⌃⌘\(index + 1)" : nil }

    var tooltip: String {
        [name, shortcutLabel, muted ? "muted" : nil].compactMap(\.self).joined(separator: " — ")
    }

    @MainActor
    static func make(session: ServerSession) -> [TeamTileModel] {
        let sections = session.teamSections
        let favoriteIds = Set(sections.favorites.map(\.id))
        let ordered = sections.all
        return ordered.enumerated().map { index, team in
            let unread = session.teamUnread(teamId: team.id)
            let favorite = favoriteIds.contains(team.id)
            let section = favorite ? sections.favorites : sections.others
            let position = section.firstIndex { $0.id == team.id } ?? 0
            return TeamTileModel(
                id: team.id,
                name: team.displayName.isEmpty ? team.name : team.displayName,
                initials: team.initials,
                index: index,
                selected: team.id == session.currentTeamId,
                unread: unread.unread,
                mentions: unread.mentions,
                iconURL: team.lastTeamIconUpdate > 0 ? session.client.teamIconURL(teamId: team.id, lastIconUpdate: team.lastTeamIconUpdate) : nil,
                favorite: favorite,
                muted: session.isMuted(teamId: team.id),
                previousId: position > 0 ? section[position - 1].id : nil,
                nextId: position + 1 < section.count ? section[position + 1].id : nil
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
        guard let id = TeamNavigator.team(number: number, in: orderedTeams.map(\.id)) else { return }
        await switchTeam(id: id)
    }

    func cycleTeam(offset: Int) async {
        guard let id = ChannelNavigator.adjacent(in: orderedTeams.map(\.id), from: currentTeamId, offset: offset) else { return }
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
    @State private var dragging: String?

    var body: some View {
        let tiles = TeamTileModel.make(session: session)
        let favorites = tiles.filter(\.favorite)
        let others = tiles.filter { !$0.favorite }
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 8) {
                ForEach(favorites) { tile in row(tile) }
                if !favorites.isEmpty {
                    TeamSectionDivider()
                        .onDrop(of: [.plainText], delegate: dropDelegate(.endOfFavorites))
                }
                ForEach(others) { tile in row(tile) }
                Color.clear
                    .frame(width: LeftRail.width, height: 44)
                    .contentShape(Rectangle())
                    .onDrop(of: [.plainText], delegate: dropDelegate(.endOfOthers))
            }
            .padding(.bottom, 12)
            .animation(.easeOut(duration: 0.15), value: tiles.map(\.id))
            .animation(.easeOut(duration: 0.15), value: favorites.count)
        }
    }

    func row(_ tile: TeamTileModel) -> some View {
        TeamTile(tile: tile, client: session.client) {
            dragging = nil
            Task { await session.switchTeam(id: tile.id) }
        }
        .equatable()
        .contextMenu { TeamTileMenu(tile: tile, session: session) }
        .onDrag {
            dragging = tile.id
            return NSItemProvider(object: tile.id as NSString)
        }
        .onDrop(of: [.plainText], delegate: dropDelegate(.team(tile.id)))
    }

    func dropDelegate(_ target: TeamDropTarget) -> TeamDropDelegate {
        TeamDropDelegate(target: target, session: session, dragging: $dragging)
    }
}

struct TeamSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 32, height: 1)
            .frame(width: LeftRail.width, height: 9)
            .contentShape(Rectangle())
    }
}

struct TeamTileMenu: View {
    let tile: TeamTileModel
    let session: ServerSession

    var body: some View {
        Button(tile.favorite ? "Remove from Favorites" : "Add to Favorites") {
            session.setFavorite(teamId: tile.id, favorite: !tile.favorite)
        }
        Button(ChannelNotifyLabels.teamMuteTitle(muted: tile.muted)) {
            session.setMuted(teamId: tile.id, !tile.muted)
        }
        if tile.previousId != nil || tile.nextId != nil {
            Divider()
        }
        if let previous = tile.previousId {
            Button("Move Up") { session.moveTeam(tile.id, to: previous) }
        }
        if let next = tile.nextId {
            Button("Move Down") { session.moveTeam(tile.id, to: next) }
        }
    }
}

enum TeamDropTarget: Equatable {
    case team(String)
    case endOfFavorites
    case endOfOthers
}

extension ServerSession {
    func moveTeam(_ teamId: String, onto target: TeamDropTarget) {
        switch target {
        case .team(let targetId): moveTeam(teamId, to: targetId)
        case .endOfFavorites: moveTeamToEnd(teamId, favorite: true)
        case .endOfOthers: moveTeamToEnd(teamId, favorite: false)
        }
    }
}

struct TeamDropDelegate: DropDelegate {
    let target: TeamDropTarget
    let session: ServerSession
    @Binding var dragging: String?

    func validateDrop(info: DropInfo) -> Bool {
        dragging != nil
    }

    func dropEntered(info: DropInfo) {
        guard let dragging, target != .team(dragging) else { return }
        withAnimation(.easeOut(duration: 0.15)) { session.moveTeam(dragging, onto: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
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
                .fill(tile.muted && !tile.selected ? Color.white.opacity(0.35) : Color.white)
                .frame(width: 4, height: indicatorHeight)
                .animation(.easeOut(duration: 0.12), value: indicatorHeight)
            Spacer(minLength: 0)
            Button(action: action) {
                icon
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: tile.selected || hovering ? 12 : 16))
                    .opacity(tile.muted && !tile.selected ? 0.5 : (tile.selected || hovering ? 1 : 0.8))
                    .overlay(alignment: .topTrailing) { badge.offset(x: 7, y: -5) }
                    .overlay(alignment: .bottomTrailing) { mutedIndicator.offset(x: 5, y: 4) }
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
            CountBadge(count: tile.mentions, color: tile.muted ? Color.white.opacity(0.25) : Theme.mentionBadge)
                .overlay(Capsule().strokeBorder(Theme.serverRail, lineWidth: 2))
        } else if tile.unread && !tile.selected {
            Circle().fill(tile.muted ? Color.white.opacity(0.35) : Color.white).frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(Theme.serverRail, lineWidth: 2))
        }
    }

    @ViewBuilder var mutedIndicator: some View {
        if tile.muted {
            MutedBellIcon(size: 9)
                .padding(2)
                .background(Circle().fill(Theme.serverRail))
        }
    }
}
