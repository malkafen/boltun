import Foundation

public enum UserStatusValue: String, Codable, Sendable {
    case online
    case away
    case dnd
    case offline
}

public struct UserStatus: Codable, Hashable, Sendable {
    public var userId: String
    public var status: UserStatusValue
    public var manual: Bool
    public var lastActivityAt: Int64

    public init(userId: String, status: UserStatusValue, manual: Bool = false, lastActivityAt: Int64 = 0) {
        self.userId = userId
        self.status = status
        self.manual = manual
        self.lastActivityAt = lastActivityAt
    }

    enum CodingKeys: String, CodingKey {
        case status, manual
        case userId = "user_id"
        case lastActivityAt = "last_activity_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = c.value(.userId, default: "")
        status = c.value(.status, default: .offline)
        manual = c.value(.manual, default: false)
        lastActivityAt = c.int64(.lastActivityAt)
    }
}

public struct Preference: Codable, Hashable, Sendable {
    public var userId: String
    public var category: String
    public var name: String
    public var value: String

    public init(userId: String, category: String, name: String, value: String) {
        self.userId = userId
        self.category = category
        self.name = name
        self.value = value
    }

    enum CodingKeys: String, CodingKey {
        case category, name, value
        case userId = "user_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = c.value(.userId, default: "")
        category = c.value(.category, default: "")
        name = c.value(.name, default: "")
        value = c.value(.value, default: "")
    }
}

public enum PreferenceCategory {
    public static let displaySettings = "display_settings"
    public static let directChannelShow = "direct_channel_show"
    public static let groupChannelShow = "group_channel_show"
    public static let favoriteChannel = "favorite_channel"
    public static let flaggedPost = "flagged_post"
    public static let theme = "theme"
    public static let sidebarSettings = "sidebar_settings"
}

public enum PreferenceName {
    public static let nameFormat = "name_format"
    public static let limitVisibleDirectMessages = "limit_visible_dms_gms"
}

public struct ServerErrorBody: Codable, Hashable, Sendable {
    public var id: String
    public var message: String
    public var statusCode: Int
    public var requestId: String

    public init(id: String, message: String, statusCode: Int = 0, requestId: String = "") {
        self.id = id
        self.message = message
        self.statusCode = statusCode
        self.requestId = requestId
    }

    enum CodingKeys: String, CodingKey {
        case id, message
        case statusCode = "status_code"
        case requestId = "request_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: "")
        message = c.value(.message, default: "")
        statusCode = c.int(.statusCode)
        requestId = c.value(.requestId, default: "")
    }
}

public struct ClientConfig: Hashable, Sendable {
    public var values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }

    public subscript(key: String) -> String? { values[key] }

    public var siteName: String { values["SiteName"].flatMap { $0.isEmpty ? nil : $0 } ?? "Mattermost" }
    public var version: String { values["Version"] ?? "" }
    public var maxPostSize: Int { Int(values["MaxPostSize"] ?? "") ?? 16383 }
    public var enableSignInWithUsername: Bool { values["EnableSignInWithUsername"] != "false" }
    public var enableSignInWithEmail: Bool { values["EnableSignInWithEmail"] != "false" }
    public var enableGitLab: Bool { values["EnableSignUpWithGitLab"] == "true" }
    public var enableGoogle: Bool { values["EnableSignUpWithGoogle"] == "true" }
    public var enableOffice365: Bool { values["EnableSignUpWithOffice365"] == "true" }
    public var enableOpenId: Bool { values["EnableSignUpWithOpenId"] == "true" }
    public var enableSaml: Bool { values["EnableSaml"] == "true" }
    public var enableCustomEmoji: Bool { values["EnableCustomEmoji"] == "true" }
    public var collapsedThreads: String { values["CollapsedThreads"] ?? "disabled" }
    public var teammateNameDisplay: String { values["TeammateNameDisplay"] ?? "username" }
}
