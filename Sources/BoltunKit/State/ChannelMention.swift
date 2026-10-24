import Foundation

public enum ChannelMention {
    public static let keys = ["@all", "@channel", "@here"]

    public static func isPresent(in message: String) -> Bool {
        keys.contains { matches(message, key: $0) }
    }

    public static func userKeys(_ user: User) -> [String] {
        var result = ["@" + user.username]
        result += (user.notifyProps["mention_keys"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if user.notifyProps["first_name"] == "true" { result.append(user.firstName) }
        return result.filter { !$0.isEmpty && $0 != "@" }
    }

    public static func mentionsUser(_ message: String, user: User) -> Bool {
        userKeys(user).contains { matches(message, key: $0) }
    }

    public static func isChannelWideOnly(message: String, user: User) -> Bool {
        isPresent(in: message) && !mentionsUser(message, user: user)
    }

    static func matches(_ message: String, key: String) -> Bool {
        guard !key.isEmpty, !message.isEmpty else { return false }
        let pattern = "(?<![\\w@])\(NSRegularExpression.escapedPattern(for: key))\\b"
        return message.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
