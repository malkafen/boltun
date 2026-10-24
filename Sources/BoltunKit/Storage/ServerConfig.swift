import Foundation

public struct ServerConfig: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var url: URL
    public var lastTeamId: String?
    public var lastChannelByTeam: [String: String]
    public var teamLayout: TeamLayout

    public init(id: UUID = UUID(), name: String, url: URL, lastTeamId: String? = nil, lastChannelByTeam: [String: String] = [:], teamLayout: TeamLayout = TeamLayout()) {
        self.id = id
        self.name = name
        self.url = url
        self.lastTeamId = lastTeamId
        self.lastChannelByTeam = lastChannelByTeam
        self.teamLayout = teamLayout
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(URL.self, forKey: .url)
        lastTeamId = c.optional(.lastTeamId)
        lastChannelByTeam = c.value(.lastChannelByTeam, default: [:])
        teamLayout = c.value(.teamLayout, default: TeamLayout())
    }

    public var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" || $0 == "." })
        let letters = words.prefix(2).compactMap(\.first)
        return String(letters.isEmpty ? Array(name.prefix(1)) : letters).uppercased()
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var showUnreadBadge = true
    public var notificationsEnabled = true
    public var notificationSound = true
    public var bounceDockIcon = true
    public var showMenuBarIcon = false
    public var launchAtLogin = false
    public var downloadLocation: String?
    public var spellChecking = true
    public var fontScale: Double = 1.0
    public var collapsedThreads = true
    public var lastServerId: UUID?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        showUnreadBadge = c.value(.showUnreadBadge, default: defaults.showUnreadBadge)
        notificationsEnabled = c.value(.notificationsEnabled, default: defaults.notificationsEnabled)
        notificationSound = c.value(.notificationSound, default: defaults.notificationSound)
        bounceDockIcon = c.value(.bounceDockIcon, default: defaults.bounceDockIcon)
        showMenuBarIcon = c.value(.showMenuBarIcon, default: defaults.showMenuBarIcon)
        launchAtLogin = c.value(.launchAtLogin, default: defaults.launchAtLogin)
        downloadLocation = c.optional(.downloadLocation)
        spellChecking = c.value(.spellChecking, default: defaults.spellChecking)
        fontScale = c.value(.fontScale, default: defaults.fontScale)
        collapsedThreads = c.value(.collapsedThreads, default: defaults.collapsedThreads)
        lastServerId = c.optional(.lastServerId)
    }
}

public struct AppState: Codable, Hashable, Sendable {
    public var version = 1
    public var servers: [ServerConfig] = []
    public var settings = AppSettings()

    public init(servers: [ServerConfig] = [], settings: AppSettings = AppSettings()) {
        self.servers = servers
        self.settings = settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.value(.version, default: 1)
        servers = c.value(.servers, default: [])
        settings = c.value(.settings, default: AppSettings())
    }
}
