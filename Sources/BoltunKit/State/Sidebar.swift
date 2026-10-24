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
        currentChannelId: String?,
        directMessageLimit limit: Int? = SidebarBuilder.directMessageLimit
    ) -> [SidebarSection] {
        func visible(_ id: String) -> Bool {
            guard let channel = channels[id] else { return false }
            if id == currentChannelId { return true }
            return members[id] != nil && !channel.isArchived && !hiddenDirect.contains(id)
        }
        let categorized = Set(categories.flatMap(\.channelIds))
        var candidates = Set(members.keys)
        if let currentChannelId { candidates.insert(currentChannelId) }
        let orphans = candidates.filter { !categorized.contains($0) && visible($0) }.sorted()
        let directOrphans = orphans.filter { channels[$0]?.type.isDirectOrGroup == true }
        let regularOrphans = orphans.filter { channels[$0]?.type.isDirectOrGroup == false }

        var lists = categories
        appendOrphans(regularOrphans, type: .channels, id: "channels", title: "Channels", to: &lists)
        appendOrphans(directOrphans, type: .directMessages, id: "direct_messages", title: "Direct Messages", to: &lists)

        var claimed = Set<String>()
        var result: [SidebarSection] = []
        for category in lists {
            var seen = Set<String>()
            var ids = category.channelIds.filter { id in
                guard visible(id), !claimed.contains(id) else { return false }
                return seen.insert(id).inserted
            }
            ids = sort(ids, category: category, channels: channels, displayName: displayName)
            if category.type == .directMessages, let limit, ids.count > limit {
                let overflow = ids.dropFirst(limit).filter { id in
                    id == currentChannelId || (channels[id].map { unread(channel: $0, member: members[id]).unread } ?? false)
                }
                ids = Array(ids.prefix(limit)) + overflow
            }
            claimed.formUnion(ids)
            result.append(SidebarSection(id: category.id, title: category.displayName, type: category.type, collapsed: category.collapsed, channelIds: ids))
        }
        return result
    }

    static func appendOrphans(_ orphans: [String], type: CategoryType, id: String, title: String, to lists: inout [ChannelCategory]) {
        guard !orphans.isEmpty else { return }
        if let index = lists.firstIndex(where: { $0.type == type }) {
            lists[index].channelIds.append(contentsOf: orphans)
        } else {
            lists.append(ChannelCategory(id: id, type: type, displayName: title, channelIds: orphans))
        }
    }

    public static func directMessageLimit(preference: String?) -> Int? {
        guard let preference else { return directMessageLimit }
        if preference == "all" { return nil }
        guard let value = Int(preference), value > 0 else { return directMessageLimit }
        return value
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
