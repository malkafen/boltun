import Foundation
import Testing
@testable import BoltunMarkup

@Suite struct InlineRenderingTests {
    @Test func rendersEmphasisVariants() {
        let rendered = paragraph("**bold** *italic* _under_ ~~gone~~ `code`")
        #expect(String(rendered.characters) == "bold italic under gone code")
        #expect(intent(of: "bold", in: rendered) == .stronglyEmphasized)
        #expect(intent(of: "italic", in: rendered) == .emphasized)
        #expect(intent(of: "under", in: rendered) == .emphasized)
        #expect(intent(of: "gone", in: rendered) == .strikethrough)
        #expect(intent(of: "code", in: rendered) == .code)
        #expect(intent(of: " ", in: rendered) == nil)
    }

    @Test func combinesNestedEmphasis() {
        let rendered = paragraph("***both*** **bold _mixed_**")
        #expect(intent(of: "both", in: rendered) == [.stronglyEmphasized, .emphasized])
        #expect(intent(of: "mixed", in: rendered) == [.stronglyEmphasized, .emphasized])
    }

    @Test func codeInsideBoldKeepsBoth() {
        #expect(intent(of: "x", in: paragraph("**`x`**")) == [.stronglyEmphasized, .code])
    }

    @Test func singleTildeIsNotStrikethrough() {
        let rendered = paragraph("~a b~")
        #expect(String(rendered.characters) == "~a b~")
        #expect(rendered.runs.allSatisfy { $0.inlinePresentationIntent == nil || $0.inlinePresentationIntent?.contains(.strikethrough) == false })
    }

    @Test func singleTildeInsideListAndQuoteIsLiteral() {
        let blocks = MessageRenderer.render("> - x ~a b~ y\n> - ~~real~~")
        guard case .quote(let inner) = blocks.first, case .list(_, _, let items) = inner.first,
              case .paragraph(let first) = items[0].first, case .paragraph(let second) = items[1].first else {
            Issue.record("unexpected \(blocks)")
            return
        }
        #expect(String(first.characters) == "x ~a b~ y")
        #expect(intent(of: "real", in: second) == .strikethrough)
    }

    @Test func singleTildeOnLaterLineIsLiteral() {
        #expect(text("first\nsecond ~a b~ third") == "first\nsecond ~a b~ third")
    }

    @Test func softAndHardBreaksBecomeNewlines() {
        #expect(text("one\ntwo") == "one\ntwo")
        #expect(text("one  \ntwo") == "one\ntwo")
        #expect(text("one\\\ntwo") == "one\ntwo")
    }

    @Test func rendersMarkdownLinks() {
        #expect(linkPairs("[Docs](https://docs.mattermost.com) and [x](<https://x.io/a b>)") == [
            "Docs=https://docs.mattermost.com", "x=https://x.io/a%20b",
        ])
    }

    @Test func linkWithFormattedText() {
        let rendered = paragraph("[**bold** link](https://x.io)")
        #expect(intent(of: "bold", in: rendered) == .stronglyEmphasized)
        #expect(links(in: rendered).map(\.text) == ["bold link"])
    }

    @Test func emptyLinkTextShowsDestination() {
        #expect(linkPairs("[](https://x.io)") == ["https://x.io=https://x.io"])
    }

    @Test func autolinksBareURLs() {
        #expect(linkPairs("see https://mattermost.com/blog?x=1, then") == ["https://mattermost.com/blog?x=1=https://mattermost.com/blog?x=1"])
        #expect(linkPairs("go www.example.com now") == ["www.example.com=http://www.example.com"])
        #expect(linkPairs("http://a.io") == ["http://a.io=http://a.io"])
        #expect(linkPairs("HTTPS://A.IO/x.") == ["HTTPS://A.IO/x=HTTPS://A.IO/x"])
        #expect(linkPairs("ftp://files.io/a mailto:bob@x.io") == ["ftp://files.io/a=ftp://files.io/a", "mailto:bob@x.io=mailto:bob@x.io"])
    }

    @Test func autolinkTrimsTrailingPunctuationAndUnbalancedParens() {
        #expect(linkPairs("(see https://en.wikipedia.org/wiki/Swift_(language))") == [
            "https://en.wikipedia.org/wiki/Swift_(language)=https://en.wikipedia.org/wiki/Swift_(language)",
        ])
        #expect(linkPairs("open https://x.io/a?!\"") == ["https://x.io/a=https://x.io/a"])
        #expect(linkPairs("https://x.io/a<b") == ["https://x.io/a=https://x.io/a"])
    }

    @Test func autolinkNeedsBodyAndBoundary() {
        #expect(linkPairs("https:// www. xhttp://a.io").isEmpty)
        #expect(text("https:// www. xhttp://a.io") == "https:// www. xhttp://a.io")
    }

    @Test func autolinkedURLIsNotDecorated() {
        #expect(linkPairs("https://x.io/@me/~ch/:smile:/x#tag") == ["https://x.io/@me/~ch/:smile:/x#tag=https://x.io/@me/~ch/:smile:/x#tag"])
    }

    @Test func autolinksAngleBracketsAndEmail() {
        #expect(linkPairs("<https://a.io/x>") == ["https://a.io/x=https://a.io/x"])
        #expect(linkPairs("mail bob@example.com now") == ["bob@example.com=mailto:bob@example.com"])
        #expect(linkPairs("<mailto:bob@example.com>") == ["mailto:bob@example.com=mailto:bob@example.com"])
        #expect(linkPairs("a.b+c@mail.example.org.") == ["a.b+c@mail.example.org=mailto:a.b+c@mail.example.org"])
    }

    @Test func rejectsInvalidEmails() {
        #expect(linkPairs("x@y x@.io x@-a.io x@ x.y").isEmpty)
    }

    @Test func relativeLinksResolveAgainstServer() {
        let context = MarkupContext(serverURL: URL(string: "https://chat.example.com/"))
        #expect(linkPairs("[post](/team/pl/abc)", context) == ["post=https://chat.example.com/team/pl/abc"])
        #expect(linkPairs("[post](/team/pl/abc)") == ["post=/team/pl/abc"])
    }

    @Test func unsafeSchemesAreNotLinked() {
        let rendered = paragraph("[click](javascript:alert(1)) [f](file:///etc/passwd)")
        #expect(String(rendered.characters) == "click f")
        #expect(links(in: rendered).isEmpty)
    }

    @Test func unparsableLinkDestinationIsPercentEncoded() {
        #expect(linkPairs("[x](<a|b>)") == ["x=a%7Cb"])
    }

    @Test func inlineHTMLIsLiteral() {
        let rendered = paragraph("a <b>bold</b> c")
        #expect(String(rendered.characters) == "a <b>bold</b> c")
        #expect(rendered.runs.allSatisfy { $0.inlinePresentationIntent == nil })
    }

    @Test func escapesAreRespected() {
        #expect(text("\\*not\\* \\@user") == "*not* @user")
    }

    @Test func smartPunctuationIsDisabled() {
        #expect(text("\"quoted\" -- 'single' ...") == "\"quoted\" -- 'single' ...")
    }

    @Test func inlineAttributesRenderTheirText() {
        #expect(text("say ^[**hi** @bob](rainbow: 'extreme')") == "say hi @bob")
    }

    @Test func entitiesAreDecoded() {
        #expect(text("a &amp; b &copy;") == "a & b ©")
    }
}
