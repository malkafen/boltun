import Foundation

public enum NotificationLevel: String, Codable, Sendable, CaseIterable {
    case `default`
    case all
    case mention
    case none

    public init(prop: String?) {
        self = prop.flatMap(NotificationLevel.init(rawValue:)) ?? .default
    }
}

public enum IgnoreChannelMentions: String, Codable, Sendable, CaseIterable {
    case `default`
    case on
    case off

    public init(prop: String?) {
        self = prop.flatMap(IgnoreChannelMentions.init(rawValue:)) ?? .default
    }
}

public enum ChannelNotifyKey {
    public static let markUnread = "mark_unread"
    public static let desktop = "desktop"
    public static let desktopThreads = "desktop_threads"
    public static let ignoreChannelMentions = "ignore_channel_mentions"
    public static let userChannelMentions = "channel"
}

public struct ChannelNotifySettings: Equatable, Sendable {
    public var muted: Bool
    public var desktop: NotificationLevel
    public var desktopThreads: NotificationLevel
    public var ignoreChannelMentions: IgnoreChannelMentions

    public init(
        muted: Bool = false,
        desktop: NotificationLevel = .default,
        desktopThreads: NotificationLevel = .default,
        ignoreChannelMentions: IgnoreChannelMentions = .default
    ) {
        self.muted = muted
        self.desktop = desktop
        self.desktopThreads = desktopThreads
        self.ignoreChannelMentions = ignoreChannelMentions
    }

    public init(member: ChannelMember?, user: User?) {
        let props = member?.notifyProps ?? [:]
        self.init(
            muted: props[ChannelNotifyKey.markUnread] == NotificationLevel.mention.rawValue,
            desktop: NotificationLevel(prop: props[ChannelNotifyKey.desktop]),
            desktopThreads: NotificationLevel(prop: props[ChannelNotifyKey.desktopThreads]),
            ignoreChannelMentions: IgnoreChannelMentions(prop: props[ChannelNotifyKey.ignoreChannelMentions])
        )
    }

    public func ignoresChannelMentions(user: User?) -> Bool {
        switch ignoreChannelMentions {
        case .on: return true
        case .off: return false
        case .default: return muted || user?.notifyProps[ChannelNotifyKey.userChannelMentions] == "false"
        }
    }

    public func desktopLevel(user: User?) -> NotificationLevel {
        Self.resolve(desktop, user: user, key: ChannelNotifyKey.desktop, fallback: .mention)
    }

    public func desktopThreadsLevel(user: User?) -> NotificationLevel {
        Self.resolve(desktopThreads, user: user, key: ChannelNotifyKey.desktopThreads, fallback: .all)
    }

    static func resolve(_ level: NotificationLevel, user: User?, key: String, fallback: NotificationLevel) -> NotificationLevel {
        guard level == .default else { return level }
        let userLevel = NotificationLevel(prop: user?.notifyProps[key])
        return userLevel == .default ? fallback : userLevel
    }

    public func changes(from previous: ChannelNotifySettings) -> [String: String] {
        var props: [String: String] = [:]
        if muted != previous.muted {
            props[ChannelNotifyKey.markUnread] = Self.markUnread(muted: muted)
        }
        if desktop != previous.desktop {
            props[ChannelNotifyKey.desktop] = desktop.rawValue
        }
        if desktopThreads != previous.desktopThreads {
            props[ChannelNotifyKey.desktopThreads] = desktopThreads.rawValue
        }
        if ignoreChannelMentions != previous.ignoreChannelMentions {
            props[ChannelNotifyKey.ignoreChannelMentions] = ignoreChannelMentions.rawValue
        }
        return props
    }

    public static func markUnread(muted: Bool) -> String {
        (muted ? NotificationLevel.mention : .all).rawValue
    }

    public static func muteProps(_ muted: Bool) -> [String: String] {
        [ChannelNotifyKey.markUnread: markUnread(muted: muted)]
    }
}
