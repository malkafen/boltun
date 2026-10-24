import Foundation

public enum ChannelType: String, Codable, Sendable {
    case open = "O"
    case `private` = "P"
    case direct = "D"
    case group = "G"

    public var isDirectOrGroup: Bool { self == .direct || self == .group }
}

public struct Channel: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var teamId: String
    public var type: ChannelType
    public var name: String
    public var displayName: String
    public var header: String
    public var purpose: String
    public var lastPostAt: Int64
    public var lastRootPostAt: Int64
    public var totalMsgCount: Int
    public var totalMsgCountRoot: Int
    public var deleteAt: Int64
    public var creatorId: String

    public init(
        id: String,
        teamId: String = "",
        type: ChannelType = .open,
        name: String,
        displayName: String = "",
        header: String = "",
        purpose: String = "",
        lastPostAt: Int64 = 0,
        lastRootPostAt: Int64 = 0,
        totalMsgCount: Int = 0,
        totalMsgCountRoot: Int = 0,
        deleteAt: Int64 = 0,
        creatorId: String = ""
    ) {
        self.id = id
        self.teamId = teamId
        self.type = type
        self.name = name
        self.displayName = displayName
        self.header = header
        self.purpose = purpose
        self.lastPostAt = lastPostAt
        self.lastRootPostAt = lastRootPostAt
        self.totalMsgCount = totalMsgCount
        self.totalMsgCountRoot = totalMsgCountRoot
        self.deleteAt = deleteAt
        self.creatorId = creatorId
    }

    enum CodingKeys: String, CodingKey {
        case id, type, name, header, purpose
        case teamId = "team_id"
        case displayName = "display_name"
        case lastPostAt = "last_post_at"
        case lastRootPostAt = "last_root_post_at"
        case totalMsgCount = "total_msg_count"
        case totalMsgCountRoot = "total_msg_count_root"
        case deleteAt = "delete_at"
        case creatorId = "creator_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        teamId = c.value(.teamId, default: "")
        type = c.value(.type, default: .open)
        name = c.value(.name, default: "")
        displayName = c.value(.displayName, default: "")
        header = c.value(.header, default: "")
        purpose = c.value(.purpose, default: "")
        lastPostAt = c.int64(.lastPostAt)
        lastRootPostAt = c.int64(.lastRootPostAt)
        totalMsgCount = c.int(.totalMsgCount)
        totalMsgCountRoot = c.int(.totalMsgCountRoot)
        deleteAt = c.int64(.deleteAt)
        creatorId = c.value(.creatorId, default: "")
    }

    public var isArchived: Bool { deleteAt > 0 }

    public func directPartnerId(me: String) -> String? {
        guard type == .direct else { return nil }
        let ids = name.components(separatedBy: "__")
        guard ids.count == 2 else { return nil }
        if ids[0] == me && ids[1] == me { return me }
        return ids.first { $0 != me }
    }
}

public struct ChannelMember: Codable, Hashable, Sendable {
    public var channelId: String
    public var userId: String
    public var roles: String
    public var lastViewedAt: Int64
    public var msgCount: Int
    public var msgCountRoot: Int
    public var mentionCount: Int
    public var mentionCountRoot: Int
    public var urgentMentionCount: Int
    public var notifyProps: [String: String]
    public var lastUpdateAt: Int64

    public init(
        channelId: String,
        userId: String,
        roles: String = "channel_user",
        lastViewedAt: Int64 = 0,
        msgCount: Int = 0,
        msgCountRoot: Int = 0,
        mentionCount: Int = 0,
        mentionCountRoot: Int = 0,
        urgentMentionCount: Int = 0,
        notifyProps: [String: String] = [:],
        lastUpdateAt: Int64 = 0
    ) {
        self.channelId = channelId
        self.userId = userId
        self.roles = roles
        self.lastViewedAt = lastViewedAt
        self.msgCount = msgCount
        self.msgCountRoot = msgCountRoot
        self.mentionCount = mentionCount
        self.mentionCountRoot = mentionCountRoot
        self.urgentMentionCount = urgentMentionCount
        self.notifyProps = notifyProps
        self.lastUpdateAt = lastUpdateAt
    }

    enum CodingKeys: String, CodingKey {
        case roles
        case channelId = "channel_id"
        case userId = "user_id"
        case lastViewedAt = "last_viewed_at"
        case msgCount = "msg_count"
        case msgCountRoot = "msg_count_root"
        case mentionCount = "mention_count"
        case mentionCountRoot = "mention_count_root"
        case urgentMentionCount = "urgent_mention_count"
        case notifyProps = "notify_props"
        case lastUpdateAt = "last_update_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channelId = c.value(.channelId, default: "")
        userId = c.value(.userId, default: "")
        roles = c.value(.roles, default: "")
        lastViewedAt = c.int64(.lastViewedAt)
        msgCount = c.int(.msgCount)
        msgCountRoot = c.int(.msgCountRoot)
        mentionCount = c.int(.mentionCount)
        mentionCountRoot = c.int(.mentionCountRoot)
        urgentMentionCount = c.int(.urgentMentionCount)
        let props: JSONObject = c.value(.notifyProps, default: [:])
        notifyProps = props.compactMapValues { $0.stringValue }
        lastUpdateAt = c.int64(.lastUpdateAt)
    }

    public var isMuted: Bool { notifyProps["mark_unread"] == "mention" }

    public var desktopNotifyLevel: String { notifyProps["desktop"] ?? "default" }
}

public enum CategoryType: String, Codable, Sendable {
    case favorites
    case channels
    case directMessages = "direct_messages"
    case custom
}

public enum CategorySorting: String, Codable, Sendable {
    case `default` = ""
    case manual
    case recent
    case alphabetical = "alpha"
}

public struct ChannelCategory: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var userId: String
    public var teamId: String
    public var type: CategoryType
    public var displayName: String
    public var sorting: CategorySorting
    public var muted: Bool
    public var collapsed: Bool
    public var channelIds: [String]

    public init(
        id: String,
        userId: String = "",
        teamId: String = "",
        type: CategoryType,
        displayName: String,
        sorting: CategorySorting = .default,
        muted: Bool = false,
        collapsed: Bool = false,
        channelIds: [String] = []
    ) {
        self.id = id
        self.userId = userId
        self.teamId = teamId
        self.type = type
        self.displayName = displayName
        self.sorting = sorting
        self.muted = muted
        self.collapsed = collapsed
        self.channelIds = channelIds
    }

    enum CodingKeys: String, CodingKey {
        case id, type, sorting, muted, collapsed
        case userId = "user_id"
        case teamId = "team_id"
        case displayName = "display_name"
        case channelIds = "channel_ids"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userId = c.value(.userId, default: "")
        teamId = c.value(.teamId, default: "")
        type = c.value(.type, default: .custom)
        displayName = c.value(.displayName, default: "")
        sorting = c.value(.sorting, default: .default)
        muted = c.value(.muted, default: false)
        collapsed = c.value(.collapsed, default: false)
        channelIds = c.value(.channelIds, default: [])
    }
}

public struct OrderedChannelCategories: Codable, Hashable, Sendable {
    public var categories: [ChannelCategory]
    public var order: [String]

    public init(categories: [ChannelCategory], order: [String]) {
        self.categories = categories
        self.order = order
    }

    public var sorted: [ChannelCategory] {
        let byId = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result = order.compactMap { byId[$0] }
        let seen = Set(order)
        result.append(contentsOf: categories.filter { !seen.contains($0.id) })
        return result
    }
}

public struct ChannelStats: Codable, Hashable, Sendable {
    public var channelId: String
    public var memberCount: Int
    public var pinnedPostCount: Int

    public init(channelId: String, memberCount: Int, pinnedPostCount: Int = 0) {
        self.channelId = channelId
        self.memberCount = memberCount
        self.pinnedPostCount = pinnedPostCount
    }

    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case memberCount = "member_count"
        case pinnedPostCount = "pinnedpost_count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channelId = c.value(.channelId, default: "")
        memberCount = c.int(.memberCount)
        pinnedPostCount = c.int(.pinnedPostCount)
    }
}
