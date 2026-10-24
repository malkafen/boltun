import Foundation
import Testing
@testable import BoltunMarkup

@Suite struct MentionTests {
    @Test func linksUserMentions() {
        #expect(linkPairs("hi @john.doe, @Ann_B and @x-y.") == [
            "@john.doe=boltun-mention://john.doe",
            "@Ann_B=boltun-mention://ann_b",
            "@x-y=boltun-mention://x-y",
        ])
        #expect(text("ping @x-y.") == "ping @x-y.")
    }

    @Test func linksSpecialMentions() {
        #expect(linkPairs("@channel @all @here") == [
            "@channel=boltun-mention://channel", "@all=boltun-mention://all", "@here=boltun-mention://here",
        ])
    }

    @Test func ignoresAtInsideWordsAndAlone() {
        #expect(linkPairs("a@b @ @. @!").isEmpty)
        #expect(text("a@b @ @. @!") == "a@b @ @. @!")
    }

    @Test func mentionAfterPunctuation() {
        #expect(linkPairs("(@bob)") == ["@bob=boltun-mention://bob"])
    }

    @Test func mentionContainingUnderscoresIsNotSplitByEmphasisParsing() {
        #expect(linkPairs("@john_doe_x hi") == ["@john_doe_x=boltun-mention://john_doe_x"])
    }

    @Test func highlightsCurrentUserCaseInsensitively() {
        let context = MarkupContext(myUsername: "Boltun")
        let rendered = paragraph("hey @boltun and @other", context)
        #expect(highlighted(rendered) == ["@boltun"])
        #expect(rendered.containsMentionHighlight)
        #expect(!paragraph("hey @other", context).containsMentionHighlight)
    }

    @Test func highlightsAtPrefixedMentionKeys() {
        let context = MarkupContext(mentionKeys: ["@channel", " @Here ", "@"])
        #expect(highlighted(paragraph("@channel @all @here", context)) == ["@channel", "@here"])
    }

    @Test func highlightsWordMentionKeys() {
        let context = MarkupContext(mentionKeys: ["Deploy", "release train", ""])
        let rendered = paragraph("deploy now, the Release Train and redeploy deployed", context)
        #expect(highlighted(rendered) == ["deploy", "Release Train"])
        #expect(links(in: rendered).isEmpty)
    }

    @Test func mentionKeyAtEndOfText() {
        #expect(highlighted(paragraph("go deploy", MarkupContext(mentionKeys: ["deploy"]))) == ["deploy"])
    }

    @Test func mentionKeyPartialMatchAtEndIsIgnored() {
        #expect(highlighted(paragraph("dep", MarkupContext(mentionKeys: ["deploy"]))).isEmpty)
    }

    @Test func highlightKeepsSurroundingFormatting() {
        let rendered = paragraph("**hi @me**", MarkupContext(myUsername: "me"))
        guard let range = rendered.range(of: "@me") else {
            Issue.record("missing mention")
            return
        }
        #expect(rendered[range].inlinePresentationIntent == .stronglyEmphasized)
        #expect(rendered[range].mentionHighlight == true)
        #expect(rendered[range].link == URL(string: "boltun-mention://me"))
    }

    @Test func highlightSurvivesNSAttributedStringConversion() throws {
        let rendered = paragraph("hi @me", MarkupContext(myUsername: "me"))
        let converted = try NSAttributedString(rendered, including: \.boltunMarkup)
        let key = NSAttributedString.Key(MentionHighlightAttribute.name)
        #expect(converted.attribute(key, at: 3, effectiveRange: nil) as? Bool == true)
        #expect(converted.attribute(key, at: 0, effectiveRange: nil) == nil)
        #expect(converted.attribute(NSAttributedString.Key("NSLink"), at: 3, effectiveRange: nil) as? URL == URL(string: "boltun-mention://me"))
        let roundTrip = try AttributedString(converted, including: \.boltunMarkup)
        #expect(highlighted(roundTrip) == ["@me"])
    }

    @Test func blockReportsHighlightAnywhere() {
        let context = MarkupContext(myUsername: "me")
        let blocks = MessageRenderer.render("> - @me\n\n| @me |\n|---|\n\n| a |\n|---|\n| @me |\n\n# @me", context: context)
        #expect(blocks.count == 4)
        #expect(blocks.allSatisfy { $0.containsMentionHighlight })
        let quiet = MessageRenderer.render("```\n@me\n```\n\n---\n\n![x](https://a.io/x.png)\n\n- a\n\n| a |\n|---|", context: context)
        #expect(quiet.count == 5)
        #expect(!quiet.contains { $0.containsMentionHighlight })
    }

    @Test func noTransformInsideCodeOrLinks() {
        let context = MarkupContext(myUsername: "me", mentionKeys: ["deploy"], customEmojiNames: ["party"])
        let rendered = paragraph("`@me :smile: #tagged ~town deploy` [@me :smile: deploy](https://x.io) https://x.io/#anchor", context)
        #expect(String(rendered.characters) == "@me :smile: #tagged ~town deploy @me :smile: deploy https://x.io/#anchor")
        #expect(links(in: rendered).map(\.url) == ["https://x.io", "https://x.io/#anchor"])
        #expect(!rendered.containsMentionHighlight)
    }
}

@Suite struct ChannelAndHashtagTests {
    @Test func linksChannelsWithDisplayNames() {
        let context = MarkupContext(channelDisplayNames: ["town-square": "Town Square"])
        let rendered = paragraph("join ~town-square and ~off_topic", context)
        #expect(String(rendered.characters) == "join ~Town Square and ~off_topic")
        #expect(links(in: rendered).map { "\($0.text)=\($0.url)" } == [
            "~Town Square=boltun-channel://town-square", "~off_topic=boltun-channel://off_topic",
        ])
    }

    @Test func channelNamesAreLowercased() {
        #expect(linkPairs("~Dev") == ["~dev=boltun-channel://dev"])
    }

    @Test func ignoresLoneTildes() {
        #expect(linkPairs("~ a~b ~!").isEmpty)
    }

    @Test func linksHashtags() {
        #expect(linkPairs("#release #v2.0. #ab #1abc C#sharp #über-cool_") == [
            "#release=boltun-hashtag://release",
            "#v2.0=boltun-hashtag://v2.0",
            "#über-cool=boltun-hashtag://%C3%BCber-cool",
        ])
    }

    @Test func hashAloneIsText() {
        #expect(text("a # b #") == "a # b #")
    }
}

@Suite struct EmojiRenderingTests {
    @Test func convertsShortcodes() {
        #expect(text(":smile: :+1::skin-tone-3: :white_check_mark: :-1:") == "😄 👍🏼 ✅ 👎")
    }

    @Test func shortcodesAreCaseInsensitive() {
        #expect(text(":ROCKET:") == "🚀")
    }

    @Test func unknownShortcodesStay() {
        #expect(text(":nope: 10:30:45 a:b ::") == ":nope: 10:30:45 a:b ::")
    }

    @Test func adjacentShortcodesAfterText() {
        #expect(text("ok:pizza::pizza:") == "ok🍕🍕")
    }

    @Test func customEmojiBecomesLink() {
        let context = MarkupContext(customEmojiNames: ["party_parrot", "smile"])
        let rendered = paragraph(":party_parrot: :smile:", context)
        #expect(String(rendered.characters) == ":party_parrot: 😄")
        #expect(links(in: rendered).map { "\($0.text)=\($0.url)" } == [":party_parrot:=boltun-emoji://party_parrot"])
    }

    @Test func emojiKeepsFormatting() {
        #expect(intent(of: "🚀", in: paragraph("**:rocket:**")) == .stronglyEmphasized)
    }

    @Test func convertsEmoticonsAtWordBoundaries() {
        #expect(text(":) ;-) :D :p :( :'( :/ :| :o :-o :] <3 </3") == "🙂 😉 😄 😛 🙁 😢 😕 😐 😮 😱 😏 ❤️ 💔")
    }

    @Test func emoticonsNeedWhitespaceAround() {
        #expect(text("a:) :)b x<3 https://a.io") == "a:) :)b x<3 https://a.io")
    }
}
