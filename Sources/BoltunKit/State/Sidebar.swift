import Foundation

public struct SidebarSection: Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var type: CategoryType
    public var collapsed: Bool
    public var channelIds: [String]

    public init(id: String, title: String, type: CategoryType, collapsed: Bool, channelIds: [String]) {
        self.id = id
        self.title = title
        self.type = type
        self.collapsed = collapsed
        self.channelIds = channelIds
    }
}

public struct ChannelUnread: Hashable, Sendable {
    public var unread: Bool
    public var mentions: Int

    public init(unread: Bool = false, mentions: Int = 0) {
        self.unread = unread
        self.mentions = mentions
    }

    public static let none = ChannelUnread()
}

public enum SidebarBuilder {
    public static let directMessageLimit = 40

    public static func unread(channel: Channel, member: ChannelMember?) -> ChannelUnread {
        guard let member else { return .none }
        let unread = channel.totalMsgCount > member.msgCount && !member.isMuted
        return ChannelUnread(unread: unread, mentions: member.mentionCount)
    }

    public static func sections(
        categories: [ChannelCategory],
        channels: [String: Channel],
        members: [String: ChannelMember],
        hiddenDirect: Set<String>,
        displayName: (Channel) -> String,
        currentChannelId: String?
    ) -> [SidebarSection] {
        var claimed = Set<String>()
        var result: [SidebarSection] = []
        for category in categories {
            var ids = category.channelIds.filter { id in
                guard let channel = channels[id], members[id] != nil || id == currentChannelId else { return false }
                if channel.isArchived && id != currentChannelId { return false }
                if hiddenDirect.contains(id) && id != currentChannelId { return false }
                return !claimed.contains(id)
            }
            ids = sort(ids, category: category, channels: channels, displayName: displayName)
            if category.type == .directMessages && ids.count > directMessageLimit {
                let unreadIds = Set(ids.filter { id in channels[id].map { unread(channel: $0, member: members[id]).unread } ?? false })
                var kept = Array(ids.prefix(directMessageLimit))
                kept.append(contentsOf: ids.dropFirst(directMessageLimit).filter { unreadIds.contains($0) || $0 == currentChannelId })
                ids = kept
            }
            claimed.formUnion(ids)
            result.append(SidebarSection(id: category.id, title: category.displayName, type: category.type, collapsed: category.collapsed, channelIds: ids))
        }
        let orphans = members.keys.filter { id in
            guard !claimed.contains(id), let channel = channels[id], !channel.isArchived else { return false }
            return !hiddenDirect.contains(id)
        }
        if !orphans.isEmpty {
            let direct = orphans.filter { channels[$0]?.type.isDirectOrGroup == true }
            let regular = orphans.filter { channels[$0]?.type.isDirectOrGroup == false }
            if let index = result.firstIndex(where: { $0.type == .channels }) {
                result[index].channelIds = sortAlphabetical(result[index].channelIds + regular, channels: channels, displayName: displayName)
            } else if !regular.isEmpty {
                result.append(SidebarSection(id: "channels", title: "Channels", type: .channels, collapsed: false, channelIds: sortAlphabetical(regular, channels: channels, displayName: displayName)))
            }
            if let index = result.firstIndex(where: { $0.type == .directMessages }) {
                result[index].channelIds = sortRecent(result[index].channelIds + direct, channels: channels)
            } else if !direct.isEmpty {
                result.append(SidebarSection(id: "direct_messages", title: "Direct Messages", type: .directMessages, collapsed: false, channelIds: sortRecent(direct, channels: channels)))
            }
        }
        return result
    }

    static func sort(_ ids: [String], category: ChannelCategory, channels: [String: Channel], displayName: (Channel) -> String) -> [String] {
        switch category.sorting {
        case .alphabetical:
            return sortAlphabetical(ids, channels: channels, displayName: displayName)
        case .recent:
            return sortRecent(ids, channels: channels)
        case .manual:
            return ids
        case .default:
            switch category.type {
            case .directMessages: return sortRecent(ids, channels: channels)
            case .custom: return ids
            case .channels, .favorites: return sortAlphabetical(ids, channels: channels, displayName: displayName)
            }
        }
    }

    static func sortAlphabetical(_ ids: [String], channels: [String: Channel], displayName: (Channel) -> String) -> [String] {
        ids.sorted { a, b in
            let left = channels[a].map(displayName) ?? a
            let right = channels[b].map(displayName) ?? b
            let order = left.localizedCaseInsensitiveCompare(right)
            return order == .orderedSame ? a < b : order == .orderedAscending
        }
    }

    static func sortRecent(_ ids: [String], channels: [String: Channel]) -> [String] {
        ids.sorted { a, b in
            let left = channels[a]?.lastPostAt ?? 0
            let right = channels[b]?.lastPostAt ?? 0
            return left == right ? a < b : left > right
        }
    }
}
