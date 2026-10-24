import Foundation

public struct ProfileTarget: Equatable, Sendable {
    public enum Surface: String, Sendable {
        case channel
        case thread
        case search
        case members
    }

    public enum Kind: String, Sendable {
        case avatar
        case name
        case mention
        case member
    }

    public var surface: Surface
    public var kind: Kind
    public var index: Int
    public var postId: String?
    public var username: String?
}

extension DebugCommand {
    static func makeProfile(action: String, query: [String: String]) -> DebugCommand? {
        switch action {
        case "members":
            return .members(on: query["on"].map(flag))
        case "members-search":
            return .membersSearch(query: query["q"] ?? "")
        case "members-more":
            return .membersMore
        case "member-message":
            guard let username = nonEmpty(query["user"]) else { return nil }
            return .memberMessage(username: username)
        case "profile":
            if flag(query["close"]) { return .profile(nil) }
            return profileTarget(query).map { .profile($0) }
        case "profile-message":
            return .profileMessage
        default:
            return nil
        }
    }

    static func profileTarget(_ query: [String: String]) -> ProfileTarget? {
        guard let surface = ProfileTarget.Surface(rawValue: query["in"] ?? "channel") else { return nil }
        let fallback: ProfileTarget.Kind = surface == .members ? .member : .avatar
        let requested: ProfileTarget.Kind?? = query["target"].map(ProfileTarget.Kind.init(rawValue:))
        guard let kind = requested ?? fallback else { return nil }
        let username = nonEmpty(query["user"])
        switch (surface, kind) {
        case (.members, .member), (_, .mention):
            guard username != nil else { return nil }
        case (.members, _), (_, .member):
            return nil
        default:
            break
        }
        return ProfileTarget(surface: surface, kind: kind, index: index(query["index"]) ?? 0, postId: nonEmpty(query["post"]), username: username)
    }
}
