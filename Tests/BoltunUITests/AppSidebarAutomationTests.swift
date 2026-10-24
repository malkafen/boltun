import AppKit
import BoltunKit
import Foundation
import Testing
@testable import BoltunUI

@MainActor
struct AppSidebarAutomationTests {
    static let categories = #"""
    {"categories":[
      {"id":"fav","team_id":"t1","type":"favorites","display_name":"Favorites","channel_ids":[]},
      {"id":"chan","team_id":"t1","type":"channels","display_name":"Channels","channel_ids":["c1","c2"]},
      {"id":"work","team_id":"t1","type":"custom","display_name":"Work","channel_ids":[]}
    ],"order":["fav","chan","work"]}
    """#

    func harness() async -> Harness {
        let transport = FakeTransport()
        transport.set("GET users/me/teams/t1/channels/categories", Self.categories)
        transport.set("PUT users/me/teams/t1/channels/categories", "[]")
        transport.set("PUT users/me/teams/t1/channels/categories/order", "[]")
        transport.set("PUT users/me/teams/t1/channels/categories/chan", #"{"id":"chan"}"#)
        let server = Harness.server()
        let harness = Harness(servers: [server], tokens: [server.id: "token"], transport: transport)
        await harness.model.startAll()
        return harness
    }

    @Test func reordersSidebarFromScripts() async throws {
        let harness = await harness()
        let sink = LogSink()
        let automation = DebugAutomation(router: AppRouter(model: harness.model), host: FakeAutomationHost(), isEnabled: { true }) { sink.lines.append($0) }
        func run(_ command: String) async -> String {
            await automation.handle(URL(string: "boltun://debug/\(command)")!)
            return sink.lines.last ?? ""
        }
        #expect(await run("channel-move?channel=town-square&index=0") == "ok /channel-move Town Square,Off-Topic")
        #expect(await run("channel-move?channel=town-square&index=0") == "error /channel-move cannot move town-square to Channels")
        #expect(await run("channel-move?channel=Off-Topic&category=work") == "ok /channel-move Off-Topic")
        #expect(await run("channel-move?channel=c1&category=Work&index=0") == "ok /channel-move Town Square,Off-Topic")
        #expect(await run("channel-move?channel=nope&index=0") == "error /channel-move no channel nope")
        #expect(await run("channel-move?channel=c1&category=ghost") == "error /channel-move no category ghost")
        #expect(await run("category-move?category=work&index=0") == "ok /category-move Work,Favorites,Channels")
        #expect(await run("category-move?category=work&index=0") == "error /category-move cannot move Work to 0")
        #expect(await run("channel-move?channel=c2&category=Channels") == "ok /channel-move Off-Topic")
        #expect(await run("category-sort?category=channels&sorting=recent") == "ok /category-sort recent Off-Topic")
        #expect(await run("category-sort?category=chan&sorting=recent") == "error /category-sort cannot sort Channels by recent activity")
        let path = "/tmp/boltun-tests-\(UUID().uuidString)-sidebar.json"
        _ = await run("state?path=\(path)")
        let state = try JSONDecoder().decode(AutomationState.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        try? FileManager.default.removeItem(atPath: path)
        let sidebar = try #require(state.ui?.sidebar)
        #expect(sidebar.map(\.title) == ["Work", "Favorites", "Channels"])
        #expect(sidebar.map(\.sorting) == ["manual", "alpha", "recent"])
        #expect(sidebar[0] == AutomationUIState.SidebarCategorySummary(id: "work", title: "Work", type: "custom", sorting: "manual", collapsed: false, channels: ["Town Square"]))
        #expect(sidebar[2].channels == ["Off-Topic"])
        let requests = harness.transport.requests(matching: "PUT users/me/teams/t1/channels/categories")
        #expect(requests.count == 4)
    }

    @Test func rejectsSidebarCommandsWithoutSession() async throws {
        let sink = LogSink()
        let automation = DebugAutomation(router: AppRouter(model: Harness().model), host: FakeAutomationHost(), isEnabled: { true }) { sink.lines.append($0) }
        await automation.handle(URL(string: "boltun://debug/category-move?category=work&index=0")!)
        #expect(sink.lines.last == "error /category-move no active session")
        let harness = await harness()
        let other = DebugAutomation(router: AppRouter(model: harness.model), host: FakeAutomationHost(), isEnabled: { true }) { sink.lines.append($0) }
        let session = try #require(harness.model.selectedSession)
        await #expect(throws: AutomationError.self) { try await other.performSidebarOrder(.leave, session: session) }
    }
}
