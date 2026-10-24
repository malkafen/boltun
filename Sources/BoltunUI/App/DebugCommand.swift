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
    case removeServer(server: Int)
    case setting(name: String, value: String)
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
    case send(text: String, thread: Bool)
    case type(text: String, thread: Bool)
    case key(name: String, modifiers: String, thread: Bool)
    case openThread(index: Int, postId: String?)
    case closePane
    case react(index: Int, emoji: String)
    case editLast(text: String)
    case deleteLast
    case scroll(to: String)
    case quickSwitch(query: String, choose: Bool, close: Bool)
    case search(query: String)
    case jump(index: Int)
    case command(name: String, number: Int?)
    case upload(path: String, thread: Bool)
    case join(channel: String)
    case leave
    case favorite(on: Bool)
    case collapse(category: String, collapsed: Bool)
    case teamFavorite(team: String, on: Bool)
    case teamMove(team: String, target: TeamMoveTarget)
    case link(url: URL)
    case notificationClick(server: Int, team: String, channel: String, root: String)

    public enum TeamMoveTarget: Equatable, Sendable {
        case team(String)
        case endOfFavorites
        case endOfOthers
    }

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
        case "remove-server":
            guard let server = index(query["server"]) else { return nil }
            return .removeServer(server: server)
        case "setting":
            guard let name = nonEmpty(query["name"]), let value = query["value"] else { return nil }
            return .setting(name: name, value: value)
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
            return makeInteraction(action: action, query: query)
        }
    }

    static func makeInteraction(action: String, query: [String: String]) -> DebugCommand? {
        let thread = flag(query["thread"])
        switch action {
        case "send":
            guard let text = nonEmpty(query["text"]) else { return nil }
            return .send(text: text, thread: thread)
        case "type":
            return .type(text: query["text"] ?? "", thread: thread)
        case "key":
            guard let name = nonEmpty(query["name"]), ["enter", "up", "down", "tab", "escape"].contains(name) else { return nil }
            return .key(name: name, modifiers: query["mods"] ?? "", thread: thread)
        case "open-thread":
            return .openThread(index: index(query["index"]) ?? 0, postId: nonEmpty(query["post"]))
        case "close-pane":
            return .closePane
        case "react":
            guard let emoji = nonEmpty(query["emoji"]) else { return nil }
            return .react(index: index(query["index"]) ?? 0, emoji: emoji)
        case "edit-last":
            guard let text = nonEmpty(query["text"]) else { return nil }
            return .editLast(text: text)
        case "delete-last":
            return .deleteLast
        case "scroll":
            guard let target = nonEmpty(query["to"]) else { return nil }
            return .scroll(to: target)
        case "quickswitch":
            return .quickSwitch(query: query["query"] ?? "", choose: flag(query["choose"]), close: flag(query["close"]))
        case "search":
            guard let terms = nonEmpty(query["q"]) else { return nil }
            return .search(query: terms)
        case "jump":
            return .jump(index: index(query["index"]) ?? 0)
        case "command":
            guard let name = nonEmpty(query["name"]) else { return nil }
            return .command(name: name, number: index(query["number"]))
        case "upload":
            guard let path = query["path"].flatMap(allowedPath) else { return nil }
            return .upload(path: path, thread: thread)
        case "join":
            guard let channel = nonEmpty(query["channel"]) else { return nil }
            return .join(channel: channel)
        case "leave":
            return .leave
        case "favorite":
            return .favorite(on: query["on"].map(flag) ?? true)
        case "collapse":
            guard let category = nonEmpty(query["category"]) else { return nil }
            return .collapse(category: category, collapsed: (query["collapsed"] ?? query["on"]).map(flag) ?? true)
        case "team-favorite":
            guard let team = nonEmpty(query["team"]) else { return nil }
            return .teamFavorite(team: team, on: query["on"].map(flag) ?? true)
        case "team-move":
            guard let team = nonEmpty(query["team"]) else { return nil }
            if let target = nonEmpty(query["to"]) { return .teamMove(team: team, target: .team(target)) }
            switch query["end"] {
            case "favorites": return .teamMove(team: team, target: .endOfFavorites)
            case "others": return .teamMove(team: team, target: .endOfOthers)
            default: return nil
            }
        case "notification-click":
            guard let channel = nonEmpty(query["channel"]) else { return nil }
            return .notificationClick(server: index(query["server"]) ?? 0, team: query["team"] ?? "", channel: channel, root: query["root"] ?? "")
        case "link":
            guard let url = query["url"].flatMap(URL.init(string:)), url.scheme != nil else { return nil }
            return .link(url: url)
        default:
            return nil
        }
    }

    static func flag(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "yes", "on"].contains(value.lowercased())
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
