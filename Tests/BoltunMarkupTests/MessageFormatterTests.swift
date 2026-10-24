import Testing
@testable import BoltunMarkup

@Test func plainTextRoundTrips() {
    #expect(MessageFormatter.plainText("hello").contains("hello"))
}
