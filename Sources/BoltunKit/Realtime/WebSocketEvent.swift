import Foundation

public struct WebSocketBroadcast: Codable, Hashable, Sendable {
    public var channelId: String
    public var teamId: String
    public var userId: String
    public var omitUsers: [String: Bool]

    public init(channelId: String = "", teamId: String = "", userId: String = "", omitUsers: [String: Bool] = [:]) {
        self.channelId = channelId
        self.teamId = teamId
        self.userId = userId
        self.omitUsers = omitUsers
    }

    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case teamId = "team_id"
        case userId = "user_id"
        case omitUsers = "omit_users"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channelId = c.value(.channelId, default: "")
        teamId = c.value(.teamId, default: "")
        userId = c.value(.userId, default: "")
        omitUsers = c.value(.omitUsers, default: [:])
    }
}

public struct WebSocketEvent: Codable, Hashable, Sendable {
    public var event: String
    public var data: JSONObject
    public var broadcast: WebSocketBroadcast
    public var seq: Int64

    public init(event: String, data: JSONObject = [:], broadcast: WebSocketBroadcast = WebSocketBroadcast(), seq: Int64 = 0) {
        self.event = event
        self.data = data
        self.broadcast = broadcast
        self.seq = seq
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        event = c.value(.event, default: "")
        data = c.value(.data, default: [:])
        broadcast = c.value(.broadcast, default: WebSocketBroadcast())
        seq = c.int64(.seq)
    }

    public static func parse(_ text: String) -> WebSocketEvent? {
        guard let data = text.data(using: .utf8),
              let event = try? MattermostJSON.decoder.decode(WebSocketEvent.self, from: data),
              !event.event.isEmpty
        else { return nil }
        return event
    }

    public func embedded<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let value = data[key] else { return nil }
        let raw: Data?
        switch value {
        case .string(let string): raw = string.data(using: .utf8)
        case .object, .array: raw = try? MattermostJSON.encoder.encode(value)
        default: raw = nil
        }
        guard let raw else { return nil }
        return try? MattermostJSON.decoder.decode(T.self, from: raw)
    }

    public func string(_ key: String) -> String? { data[key]?.stringValue }

    public var channelId: String {
        let value = broadcast.channelId
        return value.isEmpty ? (string("channel_id") ?? "") : value
    }
}

public enum WebSocketEventType {
    public static let hello = "hello"
    public static let posted = "posted"
    public static let postEdited = "post_edited"
    public static let postDeleted = "post_deleted"
    public static let postUnread = "post_unread"
    public static let reactionAdded = "reaction_added"
    public static let reactionRemoved = "reaction_removed"
    public static let typing = "typing"
    public static let channelViewed = "channel_viewed"
    public static let multipleChannelsViewed = "multiple_channels_viewed"
    public static let channelCreated = "channel_created"
    public static let channelUpdated = "channel_updated"
    public static let channelDeleted = "channel_deleted"
    public static let channelRestored = "channel_restored"
    public static let channelMemberUpdated = "channel_member_updated"
    public static let directAdded = "direct_added"
    public static let groupAdded = "group_added"
    public static let userAdded = "user_added"
    public static let userRemoved = "user_removed"
    public static let userUpdated = "user_updated"
    public static let statusChange = "status_change"
    public static let addedToTeam = "added_to_team"
    public static let leaveTeam = "leave_team"
    public static let updateTeam = "update_team"
    public static let preferencesChanged = "preferences_changed"
    public static let preferencesDeleted = "preferences_deleted"
    public static let sidebarCategoryCreated = "sidebar_category_created"
    public static let sidebarCategoryUpdated = "sidebar_category_updated"
    public static let sidebarCategoryDeleted = "sidebar_category_deleted"
    public static let sidebarCategoryOrderUpdated = "sidebar_category_order_updated"
    public static let emojiAdded = "emoji_added"
    public static let threadFollowChanged = "thread_follow_changed"
}
