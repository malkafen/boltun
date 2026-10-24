import Foundation

public struct Team: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var displayName: String
    public var description: String
    public var type: String
    public var deleteAt: Int64
    public var lastTeamIconUpdate: Int64

    public init(id: String, name: String, displayName: String, description: String = "", type: String = "O", deleteAt: Int64 = 0, lastTeamIconUpdate: Int64 = 0) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.type = type
        self.deleteAt = deleteAt
        self.lastTeamIconUpdate = lastTeamIconUpdate
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, type
        case displayName = "display_name"
        case deleteAt = "delete_at"
        case lastTeamIconUpdate = "last_team_icon_update"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.value(.name, default: "")
        displayName = c.value(.displayName, default: "")
        description = c.value(.description, default: "")
        type = c.value(.type, default: "O")
        deleteAt = c.int64(.deleteAt)
        lastTeamIconUpdate = c.int64(.lastTeamIconUpdate)
    }

    public var initials: String {
        let source = displayName.isEmpty ? name : displayName
        let words = source.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
        let letters = words.prefix(2).compactMap(\.first)
        return String(letters.isEmpty ? Array(source.prefix(2)) : letters).uppercased()
    }
}

public struct TeamMember: Codable, Hashable, Sendable {
    public var teamId: String
    public var userId: String
    public var roles: String
    public var deleteAt: Int64

    public init(teamId: String, userId: String, roles: String = "team_user", deleteAt: Int64 = 0) {
        self.teamId = teamId
        self.userId = userId
        self.roles = roles
        self.deleteAt = deleteAt
    }

    enum CodingKeys: String, CodingKey {
        case roles
        case teamId = "team_id"
        case userId = "user_id"
        case deleteAt = "delete_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        teamId = c.value(.teamId, default: "")
        userId = c.value(.userId, default: "")
        roles = c.value(.roles, default: "")
        deleteAt = c.int64(.deleteAt)
    }
}

public struct TeamUnread: Codable, Hashable, Sendable {
    public var teamId: String
    public var msgCount: Int
    public var mentionCount: Int
    public var threadCount: Int
    public var threadMentionCount: Int

    public init(teamId: String, msgCount: Int = 0, mentionCount: Int = 0, threadCount: Int = 0, threadMentionCount: Int = 0) {
        self.teamId = teamId
        self.msgCount = msgCount
        self.mentionCount = mentionCount
        self.threadCount = threadCount
        self.threadMentionCount = threadMentionCount
    }

    enum CodingKeys: String, CodingKey {
        case teamId = "team_id"
        case msgCount = "msg_count"
        case mentionCount = "mention_count"
        case threadCount = "thread_count"
        case threadMentionCount = "thread_mention_count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        teamId = c.value(.teamId, default: "")
        msgCount = c.int(.msgCount)
        mentionCount = c.int(.mentionCount)
        threadCount = c.int(.threadCount)
        threadMentionCount = c.int(.threadMentionCount)
    }
}
