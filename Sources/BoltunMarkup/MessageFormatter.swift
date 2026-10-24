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

public enum MessageRenderer {
    public static func render(_ message: String, context: MarkupContext = MarkupContext()) -> [MessageBlock] {
        guard !message.isEmpty else { return [] }
        guard LargeStack.mayNestDeeply(message) else {
            return MarkupRenderer(source: message, context: context).render()
        }
        return LargeStack.run { MarkupRenderer(source: message, context: context).render() }
    }

    public static func cached(_ message: String, context: MarkupContext = MarkupContext()) -> [MessageBlock] {
        MessageRenderCache.shared.blocks(for: message, context: context)
    }

    public static func plainText(_ message: String) -> String {
        plainText(message, context: MarkupContext())
    }

    public static func plainText(_ message: String, context: MarkupContext) -> String {
        plainText(of: render(message, context: context))
    }

    public static func plainText(of blocks: [MessageBlock]) -> String {
        PlainTextWriter.text(of: blocks)
    }
}
