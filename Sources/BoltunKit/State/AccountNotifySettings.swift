import Foundation

public enum AccountNotifyKey {
    public static let desktop = "desktop"
    public static let desktopThreads = "desktop_threads"
    public static let mentionKeys = "mention_keys"
    public static let firstName = "first_name"
    public static let channelWide = "channel"
}

public struct AccountNotifySettings: Equatable, Sendable {
    public static let levels: [NotificationLevel] = [.all, .mention, .none]

    public var desktop: NotificationLevel
    public var threadReplies: Bool
    public var firstName: Bool
    public var username: Bool
    public var channelWide: Bool
    public var keywords: [String]

    public init(
        desktop: NotificationLevel = .mention,
        threadReplies: Bool = true,
        firstName: Bool = false,
        username: Bool = false,
        channelWide: Bool = true,
        keywords: [String] = []
    ) {
        self.desktop = desktop
        self.threadReplies = threadReplies
        self.firstName = firstName
        self.username = username
        self.channelWide = channelWide
        self.keywords = keywords
    }

    public init(user: User) {
        let props = user.notifyProps
        let level = NotificationLevel(prop: props[AccountNotifyKey.desktop])
        let keys = Self.parseKeywords(props[AccountNotifyKey.mentionKeys] ?? "")
        self.init(
            desktop: level == .default ? .mention : level,
            threadReplies: [.all, .default].contains(NotificationLevel(prop: props[AccountNotifyKey.desktopThreads])),
            firstName: props[AccountNotifyKey.firstName] == "true",
            username: keys.contains { Self.isUsername($0, of: user) },
            channelWide: props[AccountNotifyKey.channelWide] != "false",
            keywords: keys.filter { !Self.isUsername($0, of: user) }
        )
    }

    public func notifyProps(for user: User) -> [String: String] {
        var props = user.notifyProps
        props[AccountNotifyKey.desktop] = desktop.rawValue
        props[AccountNotifyKey.desktopThreads] = (threadReplies ? NotificationLevel.all : .mention).rawValue
        props[AccountNotifyKey.firstName] = Self.flag(firstName)
        props[AccountNotifyKey.channelWide] = Self.flag(channelWide)
        props[AccountNotifyKey.mentionKeys] = mentionKeys(for: user).joined(separator: ",")
        return props
    }

    public func mentionKeys(for user: User) -> [String] {
        let custom = Self.unique(keywords.filter { !Self.isUsername($0, of: user) })
        return username && !user.username.isEmpty ? custom + [user.username] : custom
    }

    public static func parseKeywords(_ text: String) -> [String] {
        unique(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    static func unique(_ keys: [String]) -> [String] {
        var seen: Set<String> = []
        return keys.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    static func isUsername(_ key: String, of user: User) -> Bool {
        let lowered = key.lowercased()
        let name = user.username.lowercased()
        return !name.isEmpty && (lowered == name || lowered == "@" + name)
    }

    static func flag(_ value: Bool) -> String {
        value ? "true" : "false"
    }
}
