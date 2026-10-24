import Foundation
import Testing
@testable import BoltunKit

struct StallingTransport: HTTPTransport {
    let base: HTTPTransport
    let stalledHost: String

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.host() == stalledHost {
            try await Task.sleep(for: .seconds(30))
        }
        return try await base.send(request)
    }
}

@MainActor
@Suite struct AppModelStartupTests {
    @Test func selectedServerRestoresWhileAnotherServerStalls() async throws {
        let harness = AppHarness(lastTeam: "t1", lastChannels: ["t1": "c-dev"])
        let transport = StallingTransport(base: harness.server.transport, stalledHost: "two.example.com")
        let app = AppModel(store: harness.store, credentials: harness.credentials, transport: transport, realtimeFactory: harness.server.realtimeFactory())
        let startup = Task { await app.startAll() }
        let restored = await eventually(timeout: .seconds(5)) { app.selectedSession?.currentChannelId == "c-dev" }
        #expect(restored)
        #expect(app.session(for: harness.second.id)?.connection == .connecting)
        startup.cancel()
        app.stopAll()
    }
}
