import Foundation

public struct User: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var username: String
    public var firstName: String
    public var lastName: String
    public var nickname: String
    public var email: String
    public var position: String
    public var roles: String
    public var locale: String
    public var isBot: Bool
    public var deleteAt: Int64
    public var updateAt: Int64
    public var lastPictureUpdate: Int64
    public var notifyProps: [String: String]
    public var timezone: [String: String]
    public var botDescription: String
    public var props: [String: String]

    public init(
        id: String,
        username: String,
        firstName: String = "",
        lastName: String = "",
        nickname: String = "",
        email: String = "",
        position: String = "",
        roles: String = "system_user",
        locale: String = "en",
        isBot: Bool = false,
        deleteAt: Int64 = 0,
        updateAt: Int64 = 0,
        lastPictureUpdate: Int64 = 0,
        notifyProps: [String: String] = [:],
        timezone: [String: String] = [:],
        botDescription: String = "",
        props: [String: String] = [:]
    ) {
        self.id = id
        self.username = username
        self.firstName = firstName
        self.lastName = lastName
        self.nickname = nickname
        self.email = email
        self.position = position
        self.roles = roles
        self.locale = locale
        self.isBot = isBot
        self.deleteAt = deleteAt
        self.updateAt = updateAt
        self.lastPictureUpdate = lastPictureUpdate
        self.notifyProps = notifyProps
        self.timezone = timezone
        self.botDescription = botDescription
        self.props = props
    }

    enum CodingKeys: String, CodingKey {
        case id, username, nickname, email, position, roles, locale, timezone, props
        case botDescription = "bot_description"
        case firstName = "first_name"
        case lastName = "last_name"
        case isBot = "is_bot"
        case deleteAt = "delete_at"
        case updateAt = "update_at"
        case lastPictureUpdate = "last_picture_update"
        case notifyProps = "notify_props"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = c.value(.username, default: "")
        firstName = c.value(.firstName, default: "")
        lastName = c.value(.lastName, default: "")
        nickname = c.value(.nickname, default: "")
        email = c.value(.email, default: "")
        position = c.value(.position, default: "")
        roles = c.value(.roles, default: "")
        locale = c.value(.locale, default: "")
        isBot = c.value(.isBot, default: false)
        deleteAt = c.int64(.deleteAt)
        updateAt = c.int64(.updateAt)
        lastPictureUpdate = c.int64(.lastPictureUpdate)
        notifyProps = Self.stringMap(c, .notifyProps)
        timezone = Self.stringMap(c, .timezone)
        botDescription = c.value(.botDescription, default: "")
        props = Self.stringMap(c, .props)
    }

    private static func stringMap(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String: String] {
        guard let raw: JSONObject = c.optional(key) else { return [:] }
        return raw.compactMapValues { $0.stringValue }
    }

    public var fullName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    public var isSystemAdmin: Bool { roles.split(separator: " ").contains("system_admin") }

    public var isGuest: Bool { roles.split(separator: " ").contains("system_guest") }

    public var isDeactivated: Bool { deleteAt > 0 }

    public var showsLastActive: Bool { props["show_last_active"] != "false" }

    public var customStatus: CustomStatus? { props["customStatus"].flatMap(CustomStatus.init(json:)) }

    public var currentTimezone: String? {
        guard !timezone.isEmpty else { return nil }
        let automatic = timezone["useAutomaticTimezone"] == "true"
        return (automatic ? timezone["automaticTimezone"] : timezone["manualTimezone"]) ?? ""
    }

    public func displayName(_ setting: NameDisplaySetting = .username) -> String {
        switch setting {
        case .username:
            return username
        case .nickname:
            if !nickname.isEmpty { return nickname }
            return fullName.isEmpty ? username : fullName
        case .fullName:
            return fullName.isEmpty ? username : fullName
        }
    }
}

public enum NameDisplaySetting: String, Codable, Sendable, CaseIterable {
    case username
    case nickname = "nickname_full_name"
    case fullName = "full_name"

    public init(preference: String?) {
        self = preference.flatMap(NameDisplaySetting.init(rawValue:)) ?? .username
    }
}
