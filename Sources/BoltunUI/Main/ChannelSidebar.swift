import BoltunKit
import SwiftUI

struct SidebarRowModel: Equatable, Identifiable {
    enum Icon: Equatable {
        case open
        case `private`
        case archived
        case group
        case direct(userId: String, status: UserStatusValue, avatarURL: URL?)
    }

    var id: String
    var title: String
    var icon: Icon
    var unread: Bool
    var mentions: Int
    var muted: Bool
    var selected: Bool
    var favorite: Bool
    var isDirect: Bool

    @MainActor
    static func make(channelId: String, session: ServerSession) -> SidebarRowModel? {
        guard let channel = session.channels[channelId] else { return nil }
        let unread = session.unread(channelId: channelId)
        let icon: Icon
        if channel.isArchived {
            icon = .archived
        } else {
            switch channel.type {
            case .open: icon = .open
            case .private: icon = .private
            case .group: icon = .group
            case .direct:
                let partner = channel.directPartnerId(me: session.myId) ?? ""
                icon = .direct(
                    userId: partner,
                    status: session.statuses[partner] ?? .offline,
                    avatarURL: partner.isEmpty ? nil : session.client.profileImageURL(userId: partner, lastPictureUpdate: session.users[partner]?.lastPictureUpdate ?? 0)
                )
            }
        }
        return SidebarRowModel(
            id: channelId,
            title: session.displayName(channel: channel),
            icon: icon,
            unread: unread.unread,
            mentions: unread.mentions,
            muted: session.members[channelId]?.isMuted ?? false,
            selected: channelId == session.currentChannelId,
            favorite: session.isFavorite(channelId: channelId),
            isDirect: channel.type.isDirectOrGroup
        )
    }

    static func visibleIds(section: SidebarSection, rows: [String: SidebarRowModel]) -> [String] {
        guard section.collapsed else { return section.channelIds }
        return section.channelIds.filter { id in
            guard let row = rows[id] else { return false }
            return row.selected || row.unread || row.mentions > 0
        }
    }
}

struct ChannelSidebar: View {
    let workspace: Workspace

    var body: some View {
        let session = workspace.session
        let sections = session.sidebar.filter { $0.type != .favorites || !$0.channelIds.isEmpty }
        let rows = Dictionary(uniqueKeysWithValues: sections.flatMap(\.channelIds).compactMap { id in SidebarRowModel.make(channelId: id, session: session).map { (id, $0) } })
        VStack(spacing: 0) {
            SidebarHeader(workspace: workspace)
            FindChannelButton { workspace.openQuickSwitcher() }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        SidebarSectionHeader(section: section, hasUnread: section.channelIds.contains { rows[$0]?.unread == true }) {
                            Task { await session.setCategoryCollapsed(section.id, collapsed: !section.collapsed) }
                        } onAdd: {
                            if section.type == .directMessages { workspace.showDirectMessages = true } else { workspace.showBrowseChannels = true }
                        }
                        ForEach(SidebarRowModel.visibleIds(section: section, rows: rows), id: \.self) { id in
                            if let row = rows[id] {
                                SidebarRow(row: row, client: session.client) {
                                    Task { await workspace.select(channelId: id) }
                                }
                                .equatable()
                                .contextMenu { SidebarContextMenu(workspace: workspace, row: row) }
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .background(Theme.sidebar)
    }
}

struct SidebarContextMenu: View {
    let workspace: Workspace
    let row: SidebarRowModel

    var body: some View {
        let session = workspace.session
        Button(row.favorite ? "Remove from Favorites" : "Add to Favorites") {
            Task { await session.setFavorite(channelId: row.id, favorite: !row.favorite) }
        }
        Button("Mark as Read") { Task { await session.markViewed(channelId: row.id) } }
            .disabled(!row.unread && row.mentions == 0)
        if let channel = session.channels[row.id], !row.isDirect {
            Button("Copy Link") { workspace.copyLink(channel) }
        }
        Divider()
        if row.isDirect {
            Button("Close Conversation") { Task { await workspace.closeConversation(channelId: row.id) } }
        } else if session.channels[row.id]?.name != "town-square" {
            Button("Leave Channel", role: .destructive) { Task { await session.leave(channelId: row.id) } }
        }
    }
}

extension Workspace {
    func closeConversation(channelId: String) async {
        guard let channel = session.channels[channelId] else { return }
        if channel.type == .direct, let partner = channel.directPartnerId(me: session.myId) {
            await session.savePreference(category: PreferenceCategory.directChannelShow, name: partner, value: "false")
        } else if channel.type == .group {
            await session.savePreference(category: PreferenceCategory.groupChannelShow, name: channelId, value: "false")
        }
        if session.currentChannelId == channelId {
            if let next = navigationOrder.first(where: { $0 != channelId }) { await select(channelId: next) }
        }
    }
}

struct SidebarHeader: View {
    let workspace: Workspace
    @Environment(\.appRouter) private var router

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                if let router {
                    ServerMenuItems(model: router.model, onAddServer: router.presentAddServer)
                }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(teamName)
                            .scaledFont(15, weight: .bold)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .scaledFont(10, weight: .bold)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize()
                    }
                    if let serverName {
                        Text(serverName)
                            .scaledFont(11)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .help([teamName, serverName].compactMap(\.self).joined(separator: " — ") + " — click to switch servers")
            Spacer(minLength: 4)
            MyStatusMenu(session: workspace.session)
            Menu {
                Button("Browse Channels") { workspace.showBrowseChannels = true }
                Button("New Direct Message") { workspace.showDirectMessages = true }
            } label: {
                Image(systemName: "square.and.pencil")
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Browse channels or start a direct message")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    var teamName: String { workspace.session.currentTeam?.displayName ?? "Boltun" }

    var serverName: String? { router?.model.selectedServer?.name }
}

struct MyStatusMenu: View {
    let session: ServerSession

    var status: UserStatusValue { session.statuses[session.myId] ?? .offline }

    var avatarURL: URL? {
        session.me.map { session.client.profileImageURL(userId: $0.id, lastPictureUpdate: $0.lastPictureUpdate) }
    }

    var body: some View {
        let current = status
        Menu {
            ForEach(UserStatusValue.selectable, id: \.self) { option in
                Button {
                    Task { await session.setStatus(option) }
                } label: {
                    if option == current {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Avatar(url: avatarURL, client: session.client, name: session.me?.username ?? "", size: 26, status: current)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointerStyle(.link)
        .help("Your status: \(current.title)")
        .accessibilityLabel("Set status, currently \(current.title)")
    }
}

struct FindChannelButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").scaledFont(11, weight: .semibold)
                Text("Find channel").scaledFont(12.5)
                Spacer()
                Text("⌘K").scaledFont(11, weight: .medium).opacity(0.7)
            }
            .foregroundStyle(Theme.sidebarText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SidebarSectionHeader: View {
    let section: SidebarSection
    var hasUnread = false
    let onToggle: () -> Void
    let onAdd: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.down")
                .scaledFont(8.5, weight: .bold)
                .rotationEffect(.degrees(section.collapsed ? -90 : 0))
                .frame(width: 10)
            Text(section.title.uppercased())
                .scaledFont(11, weight: .semibold)
                .tracking(0.3)
                .lineLimit(1)
            Spacer()
            if hovering && (section.type == .directMessages || section.type == .channels) {
                Button(action: onAdd) {
                    Image(systemName: "plus").scaledFont(11, weight: .semibold)
                }
                .buttonStyle(.plain)
                .help(section.type == .directMessages ? "Write a direct message" : "Browse channels")
            }
        }
        .foregroundStyle(Theme.sidebarSectionTitle)
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { hovering = $0 }
    }
}

struct SidebarRow: View, Equatable {
    let row: SidebarRowModel
    let client: APIClient
    let action: () -> Void
    @State private var hovering = false

    nonisolated static func == (lhs: SidebarRow, rhs: SidebarRow) -> Bool {
        MainActor.assumeIsolated { lhs.row == rhs.row }
    }

    var emphasized: Bool { row.selected || ((row.unread || row.mentions > 0) && !row.muted) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon.frame(width: 20, height: 20)
                Text(row.title)
                    .scaledFont(13.5, weight: emphasized && !row.selected ? .semibold : .regular)
                    .foregroundStyle(emphasized ? Theme.sidebarTextUnread : Theme.sidebarText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if row.mentions > 0 {
                    CountBadge(count: row.mentions, color: row.muted ? Color.white.opacity(0.25) : Theme.mentionBadge)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(minHeight: 30)
            .background(background)
            .overlay(alignment: .leading) {
                if row.selected { Rectangle().fill(Theme.accent).frame(width: 3) }
            }
            .opacity(row.muted && !row.selected ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    var background: Color {
        if row.selected { return Theme.sidebarActive }
        return hovering ? Theme.sidebarHover : .clear
    }

    @ViewBuilder var icon: some View {
        let tint = emphasized ? Theme.sidebarTextUnread : Theme.sidebarText.opacity(0.8)
        switch row.icon {
        case .open: Image(systemName: "globe").scaledFont(12.5).foregroundStyle(tint)
        case .private: Image(systemName: "lock.fill").scaledFont(12).foregroundStyle(tint)
        case .archived: Image(systemName: "archivebox").scaledFont(12).foregroundStyle(tint)
        case .group:
            Text("\(row.title.split(separator: ",").count)")
                .scaledFont(10.5, weight: .bold)
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.14)))
        case .direct(_, let status, let avatarURL):
            Avatar(url: avatarURL, client: client, name: row.title, size: 20, status: status)
        }
    }
}
