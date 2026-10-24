import Foundation

public enum MentionHighlightAttribute: CodableAttributedStringKey {
    public typealias Value = Bool
    public static let name = "BoltunMentionHighlight"
}

extension AttributeScopes {
    public struct BoltunMarkupAttributes: AttributeScope {
        public let mentionHighlight: MentionHighlightAttribute
        public let foundation: FoundationAttributes
    }

    public var boltunMarkup: BoltunMarkupAttributes.Type { BoltunMarkupAttributes.self }
}

extension AttributeDynamicLookup {
    public subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.BoltunMarkupAttributes, T>) -> T {
        self[T.self]
    }
}

extension AttributedString {
    public var highlightedMentionRanges: [Range<AttributedString.Index>] {
        runs[\.mentionHighlight].compactMap { value, range in value == true ? range : nil }
    }

    public var containsMentionHighlight: Bool {
        runs[\.mentionHighlight].contains { value, _ in value == true }
    }
}

extension MessageBlock {
    public var containsMentionHighlight: Bool {
        switch self {
        case .paragraph(let text), .heading(_, let text):
            return text.containsMentionHighlight
        case .quote(let blocks):
            return blocks.contains { $0.containsMentionHighlight }
        case .list(_, _, let items):
            return items.contains { $0.contains { $0.containsMentionHighlight } }
        case .table(let header, let rows):
            return header.contains { $0.containsMentionHighlight } || rows.contains { $0.contains { $0.containsMentionHighlight } }
        case .code, .thematicBreak, .image:
            return false
        }
    }
}
