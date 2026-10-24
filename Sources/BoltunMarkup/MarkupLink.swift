import Foundation

public enum MarkupLink {
    public static let mentionScheme = "boltun-mention"
    public static let channelScheme = "boltun-channel"
    public static let hashtagScheme = "boltun-hashtag"
    public static let emojiScheme = "boltun-emoji"

    public enum Target: Hashable, Sendable {
        case mention(String)
        case channel(String)
        case hashtag(String)
        case emoji(String)
        case external(URL)
    }

    public static func mentionURL(_ username: String) -> URL? {
        url(scheme: mentionScheme, value: username)
    }

    public static func channelURL(_ name: String) -> URL? {
        url(scheme: channelScheme, value: name)
    }

    public static func hashtagURL(_ tag: String) -> URL? {
        url(scheme: hashtagScheme, value: tag)
    }

    public static func emojiURL(_ name: String) -> URL? {
        url(scheme: emojiScheme, value: name)
    }

    public static func target(for url: URL) -> Target {
        let prefix = "\(url.scheme ?? ""):"
        let payload = String(url.absoluteString.dropFirst(prefix.count)).trimmingPrefix("//")
        let value = String(payload).removingPercentEncoding ?? String(payload)
        switch url.scheme?.lowercased() {
        case mentionScheme: return .mention(value)
        case channelScheme: return .channel(value)
        case hashtagScheme: return .hashtag(value)
        case emojiScheme: return .emoji(value)
        default: return .external(url)
        }
    }

    private static let valueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127)))
        set.insert(charactersIn: "-._~+")
        return set
    }()

    private static func url(scheme: String, value: String) -> URL? {
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: valueAllowed) else { return nil }
        return URL(string: "\(scheme)://\(encoded)")
    }
}
