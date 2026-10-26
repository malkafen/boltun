public enum SettingsTab: String, CaseIterable, Hashable, Sendable {
    case servers
    case general
    case notifications
    case about

    public var title: String {
        switch self {
        case .servers: return "Servers"
        case .general: return "General"
        case .notifications: return "Notifications"
        case .about: return "About"
        }
    }

    public var systemImage: String {
        switch self {
        case .servers: return "server.rack"
        case .general: return "gearshape"
        case .notifications: return "bell.badge"
        case .about: return "info.circle"
        }
    }
}
