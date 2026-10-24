import Foundation

struct TextDecorator {
    struct Token {
        var text: String
        var link: URL?
        var highlight = false
        var end: Int
    }

    private let context: MarkupContext
    private let highlightedNames: Set<String>
    private let wordKeys: [[Character]]

    init(context: MarkupContext) {
        self.context = context
        var names: Set<String> = []
        var keys: [[Character]] = []
        let me = context.myUsername.lowercased()
        if !me.isEmpty {
            names.insert(me)
        }
        for key in context.mentionKeys {
            let lowered = key.lowercased().trimmingCharacters(in: .whitespaces)
            if lowered.hasPrefix("@") {
                let name = String(lowered.dropFirst())
                if !name.isEmpty {
                    names.insert(name)
                }
            } else if !lowered.isEmpty {
                keys.append(Array(lowered))
            }
        }
        self.highlightedNames = names
        self.wordKeys = keys
    }

    func decorate(_ text: String, attributes: AttributeContainer) -> AttributedString {
        guard needsScan(text) else { return AttributedString(text, attributes: attributes) }
        let chars = Array(text)
        var result = AttributedString()
        var plainStart = 0
        var index = 0
        while index < chars.count {
            guard let token = token(in: chars, at: index) else {
                index += 1
                continue
            }
            if plainStart < index {
                result.append(AttributedString(String(chars[plainStart..<index]), attributes: attributes))
            }
            result.append(styled(token, attributes: attributes))
            index = token.end
            plainStart = index
        }
        if plainStart < chars.count {
            result.append(AttributedString(String(chars[plainStart...]), attributes: attributes))
        }
        return result
    }

    private func needsScan(_ text: String) -> Bool {
        if !wordKeys.isEmpty {
            return true
        }
        let hasTrigger = text.utf8.contains { byte in
            byte == UInt8(ascii: "@") || byte == UInt8(ascii: "~") || byte == UInt8(ascii: "#")
                || byte == UInt8(ascii: ":") || byte == UInt8(ascii: ";") || byte == UInt8(ascii: "<")
        }
        return hasTrigger || text.range(of: "www.", options: .caseInsensitive) != nil
    }

    private func styled(_ token: Token, attributes: AttributeContainer) -> AttributedString {
        var container = attributes
        if let link = token.link {
            container.link = link
        }
        var string = AttributedString(token.text, attributes: container)
        if token.highlight {
            string.mentionHighlight = true
        }
        return string
    }

    private func token(in chars: [Character], at index: Int) -> Token? {
        switch chars[index] {
        case "@":
            return mention(in: chars, at: index)
        case "~":
            return channel(in: chars, at: index)
        case "#":
            return hashtag(in: chars, at: index)
        case ":":
            return emoji(in: chars, at: index) ?? emoticon(in: chars, at: index)
        case ";", "<":
            return emoticon(in: chars, at: index)
        default:
            return autolink(in: chars, at: index) ?? email(in: chars, at: index) ?? mentionKey(in: chars, at: index)
        }
    }

    private static let urlPrefixes: [(prefix: [Character], addsScheme: Bool)] = [
        ("https://", false), ("http://", false), ("ftp://", false), ("mailto:", false), ("www.", true),
    ].map { (Array($0.0), $0.1) }

    private static let trailingURLPunctuation: Set<Character> = ["?", "!", ".", ",", ":", ";", "*", "_", "~", "'", "\""]

    private func autolink(in chars: [Character], at index: Int) -> Token? {
        guard isWordBoundary(before: index, in: chars) else { return nil }
        for (prefix, addsScheme) in Self.urlPrefixes where matches(prefix, in: chars, at: index) {
            let bodyStart = index + prefix.count
            let end = trimmedURLEnd(in: chars, from: index, to: scan(chars, from: bodyStart) { !$0.isWhitespace && $0 != "<" })
            guard end > bodyStart else { return nil }
            let text = String(chars[index..<end])
            guard let url = URL(string: addsScheme ? "http://\(text)" : text) else { return nil }
            return Token(text: text, link: url, end: end)
        }
        return nil
    }

    private func trimmedURLEnd(in chars: [Character], from start: Int, to end: Int) -> Int {
        var end = end
        while end > start {
            let last = chars[end - 1]
            if Self.trailingURLPunctuation.contains(last) {
                end -= 1
            } else if last == ")", chars[start..<end].count(where: { $0 == ")" }) > chars[start..<end].count(where: { $0 == "(" }) {
                end -= 1
            } else {
                break
            }
        }
        return end
    }

    private func email(in chars: [Character], at index: Int) -> Token? {
        guard chars[index].isASCII, isWordCharacter(chars[index]), isWordBoundary(before: index, in: chars) else { return nil }
        let at = scan(chars, from: index) { $0.isASCII && (isWordCharacter($0) || $0 == "." || $0 == "+" || $0 == "-") }
        guard at < chars.count, chars[at] == "@" else { return nil }
        var end = scan(chars, from: at + 1) { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
        while end > at + 1, chars[end - 1] == "." || chars[end - 1] == "-" {
            end -= 1
        }
        let domain = chars[(at + 1)..<end]
        guard domain.first?.isLetter == true || domain.first?.isNumber == true, domain.contains(".") else { return nil }
        let text = String(chars[index..<end])
        return Token(text: text, link: URL(string: "mailto:\(text)"), end: end)
    }

    private func mention(in chars: [Character], at index: Int) -> Token? {
        guard isWordBoundary(before: index, in: chars) else { return nil }
        var end = scan(chars, from: index + 1) { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
        while end > index + 1, chars[end - 1] == "." {
            end -= 1
        }
        guard end > index + 1 else { return nil }
        let name = String(chars[(index + 1)..<end])
        let lowered = name.lowercased()
        return Token(text: "@\(name)", link: MarkupLink.mentionURL(lowered), highlight: highlightedNames.contains(lowered), end: end)
    }

    private func channel(in chars: [Character], at index: Int) -> Token? {
        guard isWordBoundary(before: index, in: chars) else { return nil }
        let end = scan(chars, from: index + 1) { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        guard end > index + 1 else { return nil }
        let name = String(chars[(index + 1)..<end]).lowercased()
        let display = context.channelDisplayNames[name] ?? name
        return Token(text: "~\(display)", link: MarkupLink.channelURL(name), end: end)
    }

    private func hashtag(in chars: [Character], at index: Int) -> Token? {
        guard isWordBoundary(before: index, in: chars), index + 1 < chars.count, chars[index + 1].isLetter else { return nil }
        var end = scan(chars, from: index + 1) { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
        while !(chars[end - 1].isLetter || chars[end - 1].isNumber) {
            end -= 1
        }
        guard end - index - 1 >= 3 else { return nil }
        let tag = String(chars[(index + 1)..<end])
        return Token(text: "#\(tag)", link: MarkupLink.hashtagURL(tag), end: end)
    }

    private func emoji(in chars: [Character], at index: Int) -> Token? {
        let end = scan(chars, from: index + 1, while: Emoji.isShortcodeCharacter)
        guard end > index + 1, end < chars.count, chars[end] == ":" else { return nil }
        let name = String(chars[(index + 1)..<end]).lowercased()
        if let glyph = Emoji.unicode(for: name) {
            return Token(text: glyph, end: end + 1)
        }
        if context.customEmojiNames.contains(name) {
            return Token(text: ":\(name):", link: MarkupLink.emojiURL(name), end: end + 1)
        }
        return nil
    }

    private static let emoticons: [(pattern: [Character], name: String)] = [
        (":-)", "slightly_smiling_face"), (":)", "slightly_smiling_face"),
        (";-)", "wink"), (";)", "wink"),
        (":-d", "smile"), (":d", "smile"),
        (":-p", "stuck_out_tongue"), (":p", "stuck_out_tongue"),
        (":'-(", "cry"), (":'(", "cry"),
        (":-(", "slightly_frowning_face"), (":(", "slightly_frowning_face"),
        (":-/", "confused"), (":/", "confused"),
        (":-|", "neutral_face"), (":|", "neutral_face"),
        (":-o", "scream"), (":o", "open_mouth"),
        (":-]", "smirk"), (":]", "smirk"),
        ("</3", "broken_heart"), ("<3", "heart"),
    ].map { (Array($0.0), $0.1) }

    private func emoticon(in chars: [Character], at index: Int) -> Token? {
        guard index == 0 || chars[index - 1].isWhitespace else { return nil }
        for (pattern, name) in Self.emoticons where matches(pattern, in: chars, at: index) {
            let end = index + pattern.count
            guard end == chars.count || chars[end].isWhitespace, let glyph = Emoji.unicode(for: name) else { continue }
            return Token(text: glyph, end: end)
        }
        return nil
    }

    private func mentionKey(in chars: [Character], at index: Int) -> Token? {
        guard !wordKeys.isEmpty, isWordCharacter(chars[index]), isWordBoundary(before: index, in: chars) else { return nil }
        for key in wordKeys where matches(key, in: chars, at: index) {
            let end = index + key.count
            guard end == chars.count || !isWordCharacter(chars[end]) else { continue }
            return Token(text: String(chars[index..<end]), highlight: true, end: end)
        }
        return nil
    }

    private func matches(_ pattern: [Character], in chars: [Character], at index: Int) -> Bool {
        guard index + pattern.count <= chars.count else { return false }
        for offset in pattern.indices {
            let char = chars[index + offset]
            if char != pattern[offset] && char.lowercased() != String(pattern[offset]) {
                return false
            }
        }
        return true
    }

    private func scan(_ chars: [Character], from start: Int, while predicate: (Character) -> Bool) -> Int {
        var end = start
        while end < chars.count, predicate(chars[end]) {
            end += 1
        }
        return end
    }

    private func isWordBoundary(before index: Int, in chars: [Character]) -> Bool {
        index == 0 || !isWordCharacter(chars[index - 1])
    }

    private func isWordCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_"
    }
}
