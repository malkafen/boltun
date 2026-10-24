import Foundation

public enum DebugCommand: Equatable, Sendable {
    public enum WindowTarget: String, Sendable {
        case main
        case sheet
        case settings
        case key
    }

    case snapshot(path: String, window: WindowTarget)
    case addServer(url: String, name: String?)
    case login(server: Int, user: String, password: String)
    case logout(server: Int)
    case select(server: Int, team: String?, channel: String?)
    case open(url: URL)
    case state(path: String)
    case present(sheet: String, server: Int?)
    case settings(tab: SettingsTab)
    case dismiss
    case show
    case close
    case notify(title: String, body: String)
    case quit

    public static let host = "debug"
    public static let defaultsKey = "BoltunDebugAutomation"
    public static let allowedRoots = ["/tmp/", "/private/tmp/"]

    public static func isDebugURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "boltun" && url.host()?.lowercased() == host
    }

    public init?(url: URL) {
        guard Self.isDebugURL(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let action = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let command = Self.make(action: action, query: query) else { return nil }
        self = command
    }

    static func make(action: String, query: [String: String]) -> DebugCommand? {
        switch action {
        case "snapshot":
            guard let path = query["path"].flatMap(allowedPath) else { return nil }
            return .snapshot(path: path, window: query["window"].flatMap(WindowTarget.init(rawValue:)) ?? .main)
        case "add-server":
            guard let url = query["url"], !url.isEmpty else { return nil }
            return .addServer(url: url, name: query["name"].flatMap { $0.isEmpty ? nil : $0 })
        case "login":
            guard let user = query["user"], let password = query["password"] else { return nil }
            return .login(server: index(query["server"]) ?? 0, user: user, password: password)
        case "logout":
            return .logout(server: index(query["server"]) ?? 0)
        case "select":
            return .select(server: index(query["server"]) ?? 0, team: nonEmpty(query["team"]), channel: nonEmpty(query["channel"]))
        case "open":
            guard let url = query["url"].flatMap(URL.init(string:)), url.scheme != nil else { return nil }
            return .open(url: url)
        case "state":
            guard let path = query["path"].flatMap(allowedPath) else { return nil }
            return .state(path: path)
        case "present":
            guard let sheet = nonEmpty(query["sheet"]) else { return nil }
            return .present(sheet: sheet, server: index(query["server"]))
        case "settings":
            return .settings(tab: query["tab"].flatMap(SettingsTab.init(rawValue:)) ?? .servers)
        case "dismiss":
            return .dismiss
        case "show":
            return .show
        case "close":
            return .close
        case "notify":
            return .notify(title: query["title"] ?? "Boltun", body: query["body"] ?? "Test notification")
        case "quit":
            return .quit
        default:
            return nil
        }
    }

    public static func allowedPath(_ raw: String) -> String? {
        guard raw.hasPrefix("/") else { return nil }
        let standardized = URL(fileURLWithPath: raw).standardizedFileURL.path
        guard !raw.split(separator: "/").contains(".."),
              allowedRoots.contains(where: { standardized.hasPrefix($0) }),
              !allowedRoots.contains(standardized + "/")
        else { return nil }
        return standardized
    }

    static func index(_ value: String?) -> Int? {
        value.flatMap { Int($0) }.flatMap { $0 >= 0 ? $0 : nil }
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
