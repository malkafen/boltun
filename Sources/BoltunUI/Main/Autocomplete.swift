import Foundation

enum AutocompleteKind: String, Equatable, Sendable {
    case user
    case channel
    case emoji

    var trigger: Character {
        switch self {
        case .user: return "@"
        case .channel: return "~"
        case .emoji: return ":"
        }
    }

    var minimumPrefix: Int { self == .emoji ? 2 : 0 }
}

struct AutocompleteQuery: Equatable, Sendable {
    var kind: AutocompleteKind
    var prefix: String
    var location: Int
    var length: Int
}

struct AutocompleteSuggestion: Identifiable, Equatable, Sendable {
    var id: String
    var kind: AutocompleteKind
    var title: String
    var subtitle: String
    var replacement: String
    var glyph: String?
    var userId: String?
    var customEmojiId: String?
}

enum AutocompleteParser {
    static func query(in text: String, cursor: Int) -> AutocompleteQuery? {
        let utf16 = Array(text.utf16)
        guard cursor >= 0, cursor <= utf16.count else { return nil }
        var start = cursor
        while start > 0 {
            let unit = utf16[start - 1]
            guard let scalar = Unicode.Scalar(unit), isTokenScalar(scalar) else { break }
            start -= 1
        }
        guard start > 0, let triggerScalar = Unicode.Scalar(utf16[start - 1]) else { return nil }
        let trigger = Character(triggerScalar)
        guard let kind = [AutocompleteKind.user, .channel, .emoji].first(where: { $0.trigger == trigger }) else { return nil }
        let triggerIndex = start - 1
        if triggerIndex > 0 {
            guard let before = Unicode.Scalar(utf16[triggerIndex - 1]), isBoundary(before) else { return nil }
        }
        let prefix = String(utf16CodeUnits: Array(utf16[start..<cursor]), count: cursor - start)
        guard prefix.count >= kind.minimumPrefix else { return nil }
        return AutocompleteQuery(kind: kind, prefix: prefix, location: triggerIndex, length: cursor - triggerIndex)
    }

    static func apply(_ suggestion: AutocompleteSuggestion, to text: String, query: AutocompleteQuery) -> (text: String, cursor: Int) {
        let ns = text as NSString
        let range = NSRange(location: query.location, length: min(query.length, ns.length - query.location))
        let insertion = suggestion.replacement + " "
        let updated = ns.replacingCharacters(in: range, with: insertion)
        return (updated, query.location + (insertion as NSString).length)
    }

    static func isTokenScalar(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-" || scalar == "_" || scalar == "+"
    }

    static func isBoundary(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "(" || scalar == "["
    }
}

enum ComposerKey: Equatable, Sendable {
    case enter
    case up
    case down
    case tab
    case escape
}

struct ComposerKeyModifiers: OptionSet, Sendable {
    let rawValue: Int
    static let shift = ComposerKeyModifiers(rawValue: 1)
    static let option = ComposerKeyModifiers(rawValue: 2)
    static let command = ComposerKeyModifiers(rawValue: 4)
    static let control = ComposerKeyModifiers(rawValue: 8)
}

struct ComposerKeyContext: Equatable, Sendable {
    var isEmpty: Bool
    var hasSuggestions: Bool
    var isEditing: Bool
    var cursorOnFirstLine = true
}

enum ComposerCommand: Equatable, Sendable {
    case send
    case insertNewline
    case editLastPost
    case selectPreviousSuggestion
    case selectNextSuggestion
    case acceptSuggestion
    case dismissSuggestions
    case cancelEdit
    case passThrough
}

enum ComposerKeyRouter {
    static func command(for key: ComposerKey, modifiers: ComposerKeyModifiers, context: ComposerKeyContext) -> ComposerCommand {
        switch key {
        case .enter:
            if context.hasSuggestions && modifiers.isEmpty { return .acceptSuggestion }
            if modifiers.contains(.shift) || modifiers.contains(.option) || modifiers.contains(.control) { return .insertNewline }
            return .send
        case .tab:
            return context.hasSuggestions ? .acceptSuggestion : .passThrough
        case .up:
            if context.hasSuggestions { return .selectPreviousSuggestion }
            if context.isEmpty && !context.isEditing && modifiers.isEmpty { return .editLastPost }
            return .passThrough
        case .down:
            return context.hasSuggestions ? .selectNextSuggestion : .passThrough
        case .escape:
            if context.hasSuggestions { return .dismissSuggestions }
            if context.isEditing { return .cancelEdit }
            return .passThrough
        }
    }
}
