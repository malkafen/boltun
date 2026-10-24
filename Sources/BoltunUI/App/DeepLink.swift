import BoltunKit
import Foundation

public enum DeepLinkRoute: Equatable, Sendable {
    case server
    case team(String)
    case channel(team: String, name: String)
    case permalink(team: String, postId: String)
    case thread(team: String, rootId: String)
    case direct(team: String, username: String)
    case groupMessage(team: String, name: String)

    public init(components: [String]) {
        guard let team = components.first else {
            self = .server
            return
        }
        guard components.count >= 3 else {
            self = .team(team)
            return
        }
        let value = components[2]
        switch components[1] {
        case "channels":
            self = .channel(team: team, name: value)
        case "pl":
            self = .permalink(team: team, postId: value)
        case "threads":
            self = .thread(team: team, rootId: value)
        case "messages":
            self = value.hasPrefix("@") ? .direct(team: team, username: String(value.dropFirst())) : .groupMessage(team: team, name: value)
        default:
            self = .team(team)
        }
    }
}

public struct DeepLinkMatch: Equatable, Sendable {
    public var server: ServerConfig
    public var route: DeepLinkRoute
}

public struct DeepLink: Equatable, Sendable {
    public static let appSchemes: Set<String> = ["mattermost", "boltun"]
    public static let webSchemes: Set<String> = ["http", "https"]

    public var scheme: String
    public var host: String
    public var port: Int?
    public var path: [String]

    public init(scheme: String, host: String, port: Int? = nil, path: [String] = []) {
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = path
    }

    public init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              Self.appSchemes.contains(scheme) || Self.webSchemes.contains(scheme),
              let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty
        else { return nil }
        if scheme == "boltun", host == DebugCommand.host { return nil }
        self.init(scheme: scheme, host: host, port: url.port, path: Self.components(of: url))
    }

    public var isWeb: Bool { Self.webSchemes.contains(scheme) }

    static func components(of url: URL) -> [String] {
        url.path(percentEncoded: false).split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    public func match(in servers: [ServerConfig]) -> DeepLinkMatch? {
        var best: (score: Int, match: DeepLinkMatch)?
        for server in servers {
            guard let score = score(for: server.url) else { continue }
            if best == nil || score > best!.score {
                let prefix = Self.components(of: server.url).count
                best = (score, DeepLinkMatch(server: server, route: DeepLinkRoute(components: Array(path.dropFirst(prefix)))))
            }
        }
        return best?.match
    }

    func score(for serverURL: URL) -> Int? {
        guard serverURL.host(percentEncoded: false)?.lowercased() == host else { return nil }
        let serverPath = Self.components(of: serverURL)
        guard path.starts(with: serverPath) else { return nil }
        var score = serverPath.count * 2
        if let port {
            guard port == effectivePort(serverURL) else { return nil }
            score += 1
        } else if isWeb, serverURL.port != nil, serverURL.port != Self.defaultPort(scheme) {
            return nil
        }
        return score
    }

    func effectivePort(_ url: URL) -> Int? {
        url.port ?? url.scheme.flatMap { Self.defaultPort($0) }
    }

    static func defaultPort(_ scheme: String) -> Int? {
        switch scheme.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }
}
