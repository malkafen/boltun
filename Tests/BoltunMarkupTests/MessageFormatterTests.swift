import Testing
@testable import BoltunMarkup

@Test func rendersPlainParagraph() {
    #expect(MessageRenderer.render("hello") == [.paragraph("hello")])
    #expect(MessageRenderer.render("").isEmpty)
}
