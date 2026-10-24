import Foundation
import Testing
@testable import BoltunMarkup

@Suite struct BlockRenderingTests {
    @Test func separatesParagraphs() {
        #expect(MessageRenderer.render("one\n\ntwo") == [.paragraph("one"), .paragraph("two")])
    }

    @Test func rendersAllHeadingLevels() {
        for level in 1...6 {
            let marks = String(repeating: "#", count: level)
            #expect(MessageRenderer.render("\(marks) Title") == [.heading(level: level, "Title")])
        }
    }

    @Test func rendersSetextHeading() {
        #expect(MessageRenderer.render("Title\n===") == [.heading(level: 1, "Title")])
    }

    @Test func headingKeepsInlineFormatting() {
        let blocks = MessageRenderer.render("## Hello **world**")
        #expect(blocks == [.heading(level: 2, AttributedString("Hello ") + attributed("world", .stronglyEmphasized))])
    }

    @Test func rendersFencedCodeWithLanguage() {
        let blocks = MessageRenderer.render("```swift\nlet a = 1\nprint(a)\n```")
        #expect(blocks == [.code(language: "swift", code: "let a = 1\nprint(a)")])
    }

    @Test func fencedCodeUsesFirstWordOfInfoString() {
        #expect(MessageRenderer.render("~~~python title=x\npass\n~~~") == [.code(language: "python", code: "pass")])
    }

    @Test func rendersFencedCodeWithoutLanguage() {
        #expect(MessageRenderer.render("```\n@user :smile: #tag\n```") == [.code(language: nil, code: "@user :smile: #tag")])
    }

    @Test func rendersIndentedCode() {
        #expect(MessageRenderer.render("text\n\n    indented\n    code") == [.paragraph("text"), .code(language: nil, code: "indented\ncode")])
    }

    @Test func rendersEmptyCodeBlock() {
        #expect(MessageRenderer.render("```\n```") == [.code(language: nil, code: "")])
    }

    @Test func rendersNestedQuotes() {
        let blocks = MessageRenderer.render("> outer\n>\n> > inner")
        #expect(blocks == [.quote([.paragraph("outer"), .quote([.paragraph("inner")])])])
    }

    @Test func quoteContainsCode() {
        let blocks = MessageRenderer.render("> ```js\n> x()\n> ```")
        #expect(blocks == [.quote([.code(language: "js", code: "x()")])])
    }

    @Test func rendersUnorderedList() {
        let blocks = MessageRenderer.render("- one\n- two\n* three")
        #expect(blocks == [
            .list(ordered: false, start: 1, items: [[.paragraph("one")], [.paragraph("two")]]),
            .list(ordered: false, start: 1, items: [[.paragraph("three")]]),
        ])
    }

    @Test func rendersOrderedListWithStart() {
        let blocks = MessageRenderer.render("3. three\n4. four")
        #expect(blocks == [.list(ordered: true, start: 3, items: [[.paragraph("three")], [.paragraph("four")]])])
    }

    @Test func rendersNestedLists() {
        let blocks = MessageRenderer.render("1. parent\n   - child\n     - grandchild\n2. next")
        let grandchild = MessageBlock.list(ordered: false, start: 1, items: [[.paragraph("grandchild")]])
        let child = MessageBlock.list(ordered: false, start: 1, items: [[.paragraph("child"), grandchild]])
        #expect(blocks == [.list(ordered: true, start: 1, items: [[.paragraph("parent"), child], [.paragraph("next")]])])
    }

    @Test func rendersTaskListCheckboxes() {
        let blocks = MessageRenderer.render("- [ ] todo\n- [x] done **now**")
        #expect(blocks == [.list(ordered: false, start: 1, items: [
            [.paragraph("☐ todo")],
            [.paragraph(AttributedString("☑ done ") + attributed("now", .stronglyEmphasized))],
        ])])
    }

    @Test func rendersEmptyListItem() {
        #expect(MessageRenderer.render("-\n- b") == [.list(ordered: false, start: 1, items: [[], [.paragraph("b")]])])
    }

    @Test func rendersTable() {
        let blocks = MessageRenderer.render("| Name | Role |\n| --- | :-: |\n| **Ann** | dev |\n| Bob | `ops` |")
        #expect(blocks == [.table(
            header: ["Name", "Role"],
            rows: [
                [attributed("Ann", .stronglyEmphasized), "dev"],
                ["Bob", attributed("ops", .code)],
            ]
        )])
    }

    @Test func rendersTableWithoutBody() {
        #expect(MessageRenderer.render("| a | b |\n|---|---|") == [.table(header: ["a", "b"], rows: [])])
    }

    @Test func rendersThematicBreaks() {
        #expect(MessageRenderer.render("a\n\n---\n\n***\n\nb") == [.paragraph("a"), .thematicBreak, .thematicBreak, .paragraph("b")])
    }

    @Test func rendersStandaloneImage() {
        let blocks = MessageRenderer.render("![a cat](https://example.com/cat.png)")
        #expect(blocks == [.image(url: URL(string: "https://example.com/cat.png")!, alt: "a cat")])
    }

    @Test func rendersSeveralStandaloneImages() {
        let blocks = MessageRenderer.render("![a](https://x.io/a.png)\n![b](https://x.io/b.png)")
        #expect(blocks == [
            .image(url: URL(string: "https://x.io/a.png")!, alt: "a"),
            .image(url: URL(string: "https://x.io/b.png")!, alt: "b"),
        ])
    }

    @Test func imagesSeparatedBySpacesStayStandalone() {
        #expect(MessageRenderer.render("![a](https://x.io/a.png) ![b](https://x.io/b.png)").count == 2)
    }

    @Test func imageNextToTextStaysInline() {
        #expect(text("![a](https://x.io/a.png) caption") == "a caption")
    }

    @Test func resolvesRelativeImageAgainstServer() {
        let context = MarkupContext(serverURL: URL(string: "https://chat.example.com"))
        let blocks = MessageRenderer.render("![logo](/static/logo.png)", context: context)
        #expect(blocks == [.image(url: URL(string: "https://chat.example.com/static/logo.png")!, alt: "logo")])
    }

    @Test func imageWithoutUsableURLFallsBackToParagraph() {
        #expect(MessageRenderer.render("![alt]()") == [.paragraph("alt")])
    }

    @Test func inlineImageBecomesLink() {
        let text = paragraph("see ![chart](https://x.io/c.png) here")
        #expect(String(text.characters) == "see chart here")
        #expect(links(in: text).map(\.url) == ["https://x.io/c.png"])
    }

    @Test func inlineImageWithoutAltShowsSource() {
        #expect(text("x ![](https://x.io/c.png)") == "x https://x.io/c.png")
    }

    @Test func htmlBlockIsShownAsText() {
        #expect(MessageRenderer.render("<div>\nhi\n</div>") == [.paragraph("<div>\nhi\n</div>")])
    }

    @Test func whitespaceOnlyProducesNothing() {
        #expect(MessageRenderer.render("   \n\n  ").isEmpty)
    }
}
