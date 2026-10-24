import Foundation

public struct MarkupContext: Sendable, Hashable {
    public var myUsername: String
    public var mentionKeys: [String]
    public var channelDisplayNames: [String: String]
    public var customEmojiNames: Set<String>
    public var serverURL: URL?

    public init(myUsername: String = "", mentionKeys: [String] = [], channelDisplayNames: [String: String] = [:], customEmojiNames: Set<String> = [], serverURL: URL? = nil) {
        self.myUsername = myUsername
        self.mentionKeys = mentionKeys
        self.channelDisplayNames = channelDisplayNames
        self.customEmojiNames = customEmojiNames
        self.serverURL = serverURL
    }
}

public indirect enum MessageBlock: Hashable, Sendable {
    case paragraph(AttributedString)
    case heading(level: Int, AttributedString)
    case code(language: String?, code: String)
    case quote([MessageBlock])
    case list(ordered: Bool, start: Int, items: [[MessageBlock]])
    case table(header: [AttributedString], rows: [[AttributedString]])
    case thematicBreak
    case image(url: URL, alt: String)
}

public enum MarkupLink {
    public static let mentionScheme = "boltun-mention"
    public static let channelScheme = "boltun-channel"
    public static let hashtagScheme = "boltun-hashtag"
    public static let emojiScheme = "boltun-emoji"
}

public enum MessageRenderer {
    public static func render(_ message: String, context: MarkupContext = MarkupContext()) -> [MessageBlock] {
        message.isEmpty ? [] : [.paragraph(AttributedString(message))]
    }

    public static func plainText(_ message: String) -> String {
        message
    }
}

public enum Emoji {
    public static func unicode(for name: String) -> String? {
        nil
    }

    public static func search(_ prefix: String, limit: Int = 20) -> [(name: String, glyph: String)] {
        []
    }
}
