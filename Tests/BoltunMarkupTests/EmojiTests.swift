import Foundation
import Testing
@testable import BoltunMarkup

@Suite struct EmojiTests {
    @Test(arguments: [
        ("+1", "👍"), ("thumbsup", "👍"), ("-1", "👎"), ("white_check_mark", "✅"), ("rocket", "🚀"),
        ("pizza", "🍕"), ("smile", "😄"), ("joy", "😂"), ("heart", "❤️"), ("tada", "🎉"),
        ("slightly_smiling_face", "🙂"), ("hash", "#️⃣"), ("skin-tone-2", "🏻"), ("rofl", "🤣"),
    ])
    func knowsMattermostNames(name: String, glyph: String) {
        #expect(Emoji.unicode(for: name) == glyph)
    }

    @Test func lookupNormalizesInput() {
        #expect(Emoji.unicode(for: ":Smile:") == "😄")
        #expect(Emoji.unicode(for: " rocket ") == "🚀")
        #expect(Emoji.unicode(for: "") == nil)
        #expect(Emoji.unicode(for: "definitely_not_emoji") == nil)
    }

    @Test func tableIsLargeAndConsistent() {
        #expect(Emoji.allNames.count > 2_000)
        #expect(Set(Emoji.allNames).count == Emoji.allNames.count)
        #expect(Emoji.allNames.first == "grinning")
        #expect(Emoji.allNames.allSatisfy { Emoji.unicode(for: $0) != nil })
    }

    @Test func frequentlyUsedResolves() {
        #expect(Emoji.frequentlyUsed.count == Emoji.frequentlyUsedNames.count)
        #expect(Emoji.frequentlyUsed.first?.name == "+1")
        #expect(Emoji.frequentlyUsed.first?.glyph == "👍")
    }

    @Test func searchRanksExactThenPrefixThenContains() {
        let names = Emoji.search("smile", limit: 50).map(\.name)
        #expect(names.first == "smile")
        let firstContains = names.firstIndex { !$0.hasPrefix("smile") && !$0.contains("_smile") }
        let lastPrefix = names.lastIndex { $0.hasPrefix("smile") }
        #expect(names.contains("smiley"))
        #expect(names.contains("smile_cat"))
        if let firstContains, let lastPrefix {
            #expect(lastPrefix < firstContains)
        }
    }

    @Test func searchPrefersPopularWithinTier() {
        #expect(Emoji.search("thu", limit: 3).map(\.name).first == "thumbsup")
        #expect(Emoji.search("+", limit: 1).map(\.name) == ["+1"])
    }

    @Test func searchFindsWordSegments() {
        let names = Emoji.search("check", limit: 10).map(\.name)
        #expect(names.contains("white_check_mark"))
        #expect(names.allSatisfy { $0.contains("check") })
    }

    @Test func searchRespectsLimitAndEmptyQuery() {
        #expect(Emoji.search("a", limit: 5).count == 5)
        #expect(Emoji.search("a", limit: 0).isEmpty)
        #expect(Emoji.search("", limit: 3).map(\.name) == ["+1", "-1", "smile"])
        #expect(Emoji.search(":", limit: 3).map(\.name) == ["+1", "-1", "smile"])
        #expect(Emoji.search("zzzzqqq").isEmpty)
    }

    @Test func searchAcceptsColonPrefix() {
        #expect(Emoji.search(":rock", limit: 1).map(\.name) == ["rock"])
        #expect(Emoji.search(":rocket:", limit: 1).first?.glyph == "🚀")
    }

    @Test func rankWorksForCustomNames() {
        #expect(Emoji.rank("par", names: ["sparkle_party", "party_parrot", "par", "Parrot"]) == ["par", "Parrot", "party_parrot", "sparkle_party"])
        #expect(Emoji.rank("", names: ["a"]).isEmpty)
        #expect(Emoji.rank("a", names: ["a"], limit: 0).isEmpty)
        #expect(Emoji.rank("dog", names: ["hot-dog", "dogs", "cat"]) == ["dogs", "hot-dog"])
    }

    @Test func replacesShortcodesInPlainStrings() {
        #expect(Emoji.replacingShortcodes(in: "ship it :rocket::rocket: now") == "ship it 🚀🚀 now")
        #expect(Emoji.replacingShortcodes(in: "time 10:30: : b : :nope: end:") == "time 10:30: : b : :nope: end:")
        #expect(Emoji.replacingShortcodes(in: "no colons") == "no colons")
        #expect(Emoji.replacingShortcodes(in: "::smile:") == ":😄")
    }

    @Test func packedTableParsingSkipsMalformedLines() {
        let table = EmojiTable(packed: "😀 grinning\nbroken\n\n😃 smiley grinning\n🎉 tada", popular: ["missing", "smiley", "grinning", "tada"])
        #expect(table.glyphs == ["grinning": "😃", "smiley": "😃", "tada": "🎉"])
        #expect(table.orderedNames == ["grinning", "smiley", "tada"])
        #expect(table.popularity == ["grinning": 1, "smiley": 1, "tada": 3])
    }
}
