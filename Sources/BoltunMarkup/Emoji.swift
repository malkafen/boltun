import Foundation

public enum Emoji {
    public static let frequentlyUsedNames: [String] = [
        "+1", "-1", "smile", "joy", "heart", "white_check_mark", "tada", "pray",
        "fire", "eyes", "rocket", "thinking_face", "100", "raised_hands", "clap", "ok_hand",
        "wave", "slightly_smiling_face", "laughing", "sob", "heart_eyes", "wink", "muscle", "x",
    ]

    public static var frequentlyUsed: [(name: String, glyph: String)] {
        frequentlyUsedNames.compactMap { name in unicode(for: name).map { (name, $0) } }
    }

    public static var allNames: [String] {
        EmojiTable.shared.orderedNames
    }

    public static func unicode(for name: String) -> String? {
        EmojiTable.shared.glyphs[normalized(name)]
    }

    public static func search(_ prefix: String, limit: Int = 20) -> [(name: String, glyph: String)] {
        guard limit > 0 else { return [] }
        let query = normalized(prefix)
        if query.isEmpty {
            return Array(frequentlyUsed.prefix(limit))
        }
        return rank(query, names: EmojiTable.shared.orderedNames, limit: limit).compactMap { name in
            unicode(for: name).map { (name, $0) }
        }
    }

    public static func rank(_ query: String, names: some Sequence<String>, limit: Int = 20) -> [String] {
        let query = normalized(query)
        guard !query.isEmpty, limit > 0 else { return [] }
        let scored = names.compactMap { name -> (tier: Int, popularity: Int, name: String)? in
            let lowered = name.lowercased()
            guard let tier = matchTier(of: lowered, for: query) else { return nil }
            return (tier, EmojiTable.shared.popularity[lowered] ?? Int.max, name)
        }
        let sorted = scored.sorted { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.popularity != rhs.popularity { return lhs.popularity < rhs.popularity }
            if lhs.name.count != rhs.name.count { return lhs.name.count < rhs.name.count }
            return lhs.name < rhs.name
        }
        return sorted.prefix(limit).map(\.name)
    }

    public static func replacingShortcodes(in text: String) -> String {
        guard text.contains(":") else { return text }
        var result = ""
        var remainder = Substring(text)
        while let open = remainder.firstIndex(of: ":") {
            result += remainder[..<open]
            let afterOpen = remainder.index(after: open)
            if let close = remainder[afterOpen...].firstIndex(of: ":"),
               remainder[afterOpen..<close].allSatisfy(isShortcodeCharacter),
               let glyph = EmojiTable.shared.glyphs[remainder[afterOpen..<close].lowercased()] {
                result += glyph
                remainder = remainder[remainder.index(after: close)...]
            } else {
                result.append(":")
                remainder = remainder[afterOpen...]
            }
        }
        return result + remainder
    }

    static func isShortcodeCharacter(_ char: Character) -> Bool {
        char.isASCII && (char.isLetter || char.isNumber || char == "_" || char == "-" || char == "+")
    }

    private static func matchTier(of name: String, for query: String) -> Int? {
        if name == query { return 0 }
        if name.hasPrefix(query) { return 1 }
        if name.contains("_\(query)") || name.contains("-\(query)") { return 2 }
        if name.contains(query) { return 3 }
        return nil
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":"))).lowercased()
    }
}

struct EmojiTable: Sendable {
    static let shared = EmojiTable(packed: EmojiData.packed, popular: Emoji.frequentlyUsedNames)

    let glyphs: [String: String]
    let orderedNames: [String]
    let popularity: [String: Int]

    init(packed: String, popular: [String]) {
        var glyphs: [String: String] = [:]
        var names: [String] = []
        for line in packed.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count >= 2 else { continue }
            let glyph = String(parts[0])
            for name in parts.dropFirst() {
                let key = String(name)
                if glyphs.updateValue(glyph, forKey: key) == nil {
                    names.append(key)
                }
            }
        }
        self.glyphs = glyphs
        self.orderedNames = names
        var glyphRank: [String: Int] = [:]
        for (rank, name) in popular.enumerated() {
            if let glyph = glyphs[name], glyphRank[glyph] == nil {
                glyphRank[glyph] = rank
            }
        }
        self.popularity = glyphs.compactMapValues { glyphRank[$0] }
    }
}
