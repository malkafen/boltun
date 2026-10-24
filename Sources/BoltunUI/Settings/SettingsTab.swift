public enum SettingsTab: String, CaseIterable, Hashable, Sendable {
    case servers
    case general
    case about

    public var title: String {
        switch self {
        case .servers: return "Servers"
        case .general: return "General"
        case .about: return "About"
        }
    }

    public var systemImage: String {
        switch self {
        case .servers: return "server.rack"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }
}
