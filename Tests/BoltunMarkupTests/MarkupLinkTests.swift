import Foundation
import Testing
@testable import BoltunMarkup

@Suite struct MarkupLinkTests {
    @Test func buildsAndParsesTargets() throws {
        #expect(MarkupLink.target(for: try #require(MarkupLink.mentionURL("john.doe"))) == .mention("john.doe"))
        #expect(MarkupLink.target(for: try #require(MarkupLink.channelURL("town-square"))) == .channel("town-square"))
        #expect(MarkupLink.target(for: try #require(MarkupLink.hashtagURL("über"))) == .hashtag("über"))
        #expect(MarkupLink.target(for: try #require(MarkupLink.emojiURL("+1"))) == .emoji("+1"))
    }

    @Test func externalURLsPassThrough() throws {
        let url = try #require(URL(string: "https://mattermost.com/x"))
        #expect(MarkupLink.target(for: url) == .external(url))
        let relative = try #require(URL(string: "/team/pl/1"))
        #expect(MarkupLink.target(for: relative) == .external(relative))
    }

    @Test func renderedLinksRoundTrip() throws {
        let rendered = paragraph("@Bob ~dev #release :party:", MarkupContext(customEmojiNames: ["party"]))
        let targets = links(in: rendered).compactMap { URL(string: $0.url) }.map(MarkupLink.target(for:))
        #expect(targets == [.mention("bob"), .channel("dev"), .hashtag("release"), .emoji("party")])
    }

    @Test func schemesMatchContract() {
        #expect(MarkupLink.mentionScheme == "boltun-mention")
        #expect(MarkupLink.channelScheme == "boltun-channel")
        #expect(MarkupLink.hashtagScheme == "boltun-hashtag")
        #expect(MarkupLink.emojiScheme == "boltun-emoji")
    }
}
