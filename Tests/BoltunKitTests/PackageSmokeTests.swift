import Testing
@testable import BoltunKit

@Test func normalizesServerURL() throws {
    #expect(try APIClient.normalize("chat.example.com/").absoluteString == "https://chat.example.com")
}
