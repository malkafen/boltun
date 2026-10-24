import Foundation
import Testing
@testable import BoltunKit

@MainActor
@Suite struct SidebarOrderSessionTests {
    static let batch = "users/me/teams/t1/channels/categories"
    static let order = "users/me/teams/t1/channels/categories/order"

    func batchBody(_ server: MockServer) -> [[String: Any]] {
        server.transport.last("PUT", Self.batch)?.jsonBody as? [[String: Any]] ?? []
    }

    func channelsCategory(_ ids: [String], sorting: String = "manual") -> [String: Any] {
        Fixtures.category("chan1", user: "me1", team: "t1", type: "channels", display: "Channels", sorting: sorting, channels: ids)
    }

    func updated(_ categories: [[String: Any]]) -> WebSocketEvent {
        Fixtures.wsEvent("sidebar_category_updated", data: ["updatedCategories": Fixtures.json(categories)], team: "t1", user: "me1")
    }

    @Test func reorderInsideCategoryIsOptimisticAndSwitchesToManual() async {
        let server = MockServer()
        server.transport.on("PUT", Self.batch) { .json($0.bodyText) }
        let session = await server.startedSession()
        #expect(session.sidebar[1].channelIds == ["c-dev", "c-town"])
        #expect(await session.moveChannel("c-town", toCategory: "chan1", index: 0))
        #expect(session.sidebar[1].channelIds == ["c-town", "c-dev"])
        #expect(session.sidebar[1].sorting == .manual)
        let body = batchBody(server)
        #expect(body.count == 1)
        #expect(body.first?["id"] as? String == "chan1")
        #expect(body.first?["sorting"] as? String == "manual")
        #expect(body.first?["channel_ids"] as? [String] == ["c-town", "c-dev"])
        #expect(server.transport.count("GET", Self.batch) == 1)
        #expect(!(await session.moveChannel("c-town", toCategory: "chan1", index: 0)))
        #expect(server.transport.count("PUT", Self.batch) == 1)
        session.stop()
    }

    @Test func moveBetweenCategoriesRespectsDirectMessageRules() async {
        let server = MockServer()
        server.transport.on("PUT", Self.batch) { .json($0.bodyText) }
        let session = await server.startedSession()
        #expect(await session.moveChannel("c-dev", toCategory: "fav1", index: nil))
        #expect(session.sidebar.map(\.channelIds) == [["c-dev"], ["c-town"], ["c-dm", "c-gm"]])
        #expect(Set(batchBody(server).compactMap { $0["id"] as? String }) == ["fav1", "chan1"])
        #expect(session.isFavorite(channelId: "c-dev"))
        #expect(!(await session.moveChannel("c-dm", toCategory: "chan1", index: 0)))
        #expect(!(await session.moveChannel("c-town", toCategory: "dm1", index: 0)))
        #expect(!(await session.moveChannel("c-dm", toCategory: "dm1", index: 1)))
        #expect(server.transport.count("PUT", Self.batch) == 1)
        #expect(await session.moveChannel("c-gm", toCategory: "fav1", index: 0))
        #expect(session.sidebar.map(\.channelIds) == [["c-gm", "c-dev"], ["c-town"], ["c-dm"]])
        #expect(await session.moveChannel("c-gm", toCategory: "dm1", index: nil))
        #expect(session.sidebar.map(\.channelIds) == [["c-dev"], ["c-town"], ["c-dm", "c-gm"]])
        #expect(session.categories["t1"]?.first { $0.id == "dm1" }?.sorting == .recent)
        session.stop()
    }

    @Test func failedMoveRollsBackAndReloads() async {
        let server = MockServer()
        server.transport.on("PUT", Self.batch, .error(500, message: "move failed"))
        let session = await server.startedSession()
        let before = session.categories["t1"]
        server.transport.on("GET", Self.batch, .error(500))
        #expect(!(await session.moveChannel("c-town", toCategory: "chan1", index: 0)))
        #expect(session.categories["t1"] == before)
        #expect(session.sidebar[1].channelIds == ["c-dev", "c-town"])
        #expect(session.lastError == "move failed")
        #expect(server.transport.count("GET", Self.batch) == 2)
        #expect(session.categoryWrites.isEmpty && session.staleCategoryTeams.isEmpty)
        session.stop()
    }

    @Test func failureReloadsServerState() async {
        let server = MockServer()
        server.transport.on("PUT", Self.order, .error(500, message: "order failed"))
        let session = await server.startedSession()
        server.transport.on("GET", Self.batch, object: Fixtures.categories([
            Fixtures.category("dm1", user: "me1", team: "t1", type: "direct_messages", display: "Direct Messages", channels: ["c-dm", "c-gm"]),
            channelsCategory(["c-town", "c-dev"]),
        ]))
        #expect(!(await session.moveCategory("dm1", to: 0)))
        #expect(session.sidebar.map(\.id) == ["dm1", "chan1"])
        #expect(session.sidebar[1].channelIds == ["c-town", "c-dev"])
        #expect(session.lastError == "order failed")
        session.stop()
    }

    @Test func reorderCategories() async {
        let server = MockServer()
        server.transport.on("PUT", Self.order) { .json($0.bodyText) }
        let session = await server.startedSession()
        #expect(await session.moveCategory("dm1", to: 0))
        #expect(session.sidebar.map(\.id) == ["dm1", "fav1", "chan1"])
        #expect(server.transport.last("PUT", Self.order)?.jsonBody as? [String] == ["dm1", "fav1", "chan1"])
        #expect(await session.moveCategory("fav1", to: 2))
        #expect(session.sidebar.map(\.id) == ["dm1", "chan1", "fav1"])
        #expect(!(await session.moveCategory("fav1", to: 2)))
        #expect(!(await session.moveCategory("missing", to: 0)))
        #expect(server.transport.count("PUT", Self.order) == 2)
        session.stop()
    }

    @Test func changeCategorySorting() async {
        let server = MockServer()
        server.transport.on("PUT", "users/me/teams/t1/channels/categories/chan1") { .json($0.bodyText) }
        server.transport.on("PUT", "users/me/teams/t1/channels/categories/dm1") { .json($0.bodyText) }
        let session = await server.startedSession()
        #expect(await session.setCategorySorting("chan1", .manual))
        #expect(session.categories["t1"]?[1].channelIds == ["c-dev", "c-town"])
        #expect(session.sidebar[1].effectiveSorting == .manual)
        let body = server.transport.last("PUT", "users/me/teams/t1/channels/categories/chan1")?.jsonObject
        #expect(body?["sorting"] as? String == "manual")
        #expect(body?["channel_ids"] as? [String] == ["c-dev", "c-town"])
        #expect(!(await session.setCategorySorting("chan1", .manual)))
        #expect(!(await session.setCategorySorting("dm1", .manual)))
        #expect(await session.setCategorySorting("dm1", .alphabetical))
        #expect(session.sidebar[2].effectiveSorting == .alphabetical)
        #expect(session.sidebar[2].channelIds == ["c-gm", "c-dm"])
        session.stop()
    }

    @Test func orderingNeedsATeam() async {
        let server = MockServer()
        let session = await server.startedSession(team: nil)
        #expect(!(await session.moveChannel("c-town", toCategory: "chan1", index: 0)))
        #expect(!(await session.moveCategory("dm1", to: 0)))
        #expect(!(await session.setCategorySorting("chan1", .manual)))
        #expect(server.transport.requests.allSatisfy { $0.httpMethod == "GET" || $0.httpMethod == "POST" })
        session.stop()
    }

    @Test func eventsDuringPendingWriteDeferToReload() async {
        let server = MockServer()
        let gate = Gate()
        server.hold("PUT", Self.batch, gate: gate) { .json($0.bodyText) }
        let session = await server.startedSession()
        let move = Task { await session.moveChannel("c-town", toCategory: "chan1", index: 0) }
        #expect(await eventually { server.transport.count("PUT", Self.batch) == 1 })
        session.apply(updated([channelsCategory(["c-dev", "c-town"], sorting: "alpha")]))
        session.apply(Fixtures.wsEvent("sidebar_category_order_updated", data: ["order": ["dm1", "fav1", "chan1"]], team: "t1", user: "me1"))
        session.apply(Fixtures.wsEvent("sidebar_category_deleted", data: ["category_id": "fav1"], team: "t1", user: "me1"))
        #expect(session.sidebar.map(\.id) == ["fav1", "chan1", "dm1"])
        #expect(session.sidebar[1].channelIds == ["c-town", "c-dev"])
        #expect(session.staleCategoryTeams == ["t1"])
        await gate.open()
        #expect(await move.value)
        #expect(server.transport.count("GET", Self.batch) == 2)
        #expect(session.sidebar[1].channelIds == ["c-dev", "c-town"])
        #expect(session.categoryWrites.isEmpty && session.staleCategoryTeams.isEmpty)
        session.stop()
    }

    @Test func ownEchoDuringPendingWriteNeedsNoReload() async {
        let server = MockServer()
        let gate = Gate()
        server.hold("PUT", Self.batch, gate: gate) { .json($0.bodyText) }
        let session = await server.startedSession()
        let move = Task { await session.moveChannel("c-town", toCategory: "chan1", index: 0) }
        #expect(await eventually { server.transport.count("PUT", Self.batch) == 1 })
        session.apply(updated([channelsCategory(["c-town", "c-dev"])]))
        session.apply(Fixtures.wsEvent("sidebar_category_order_updated", data: ["order": ["fav1", "chan1", "dm1"]], team: "t1", user: "me1"))
        #expect(session.staleCategoryTeams.isEmpty)
        await gate.open()
        #expect(await move.value)
        await settle()
        #expect(server.transport.count("GET", Self.batch) == 1)
        session.stop()
    }

    @Test func reloadDuringNewWriteStaysDeferred() async {
        let server = MockServer()
        let gate = Gate()
        server.hold("GET", Self.batch, gate: gate) { _ in .object(Fixtures.categories([])) }
        let session = await server.startedSession(team: nil)
        session.currentTeamId = "t1"
        session.loadedTeams = ["t1"]
        session.categories["t1"] = [ChannelCategory(id: "chan1", teamId: "t1", type: .channels, displayName: "Channels", channelIds: ["c-town"])]
        let reload = Task { await session.reloadCategories(teamId: "t1") }
        #expect(await eventually { server.transport.count("GET", Self.batch) == 1 })
        session.categoryWrites["t1"] = 1
        await gate.open()
        await reload.value
        #expect(session.categories["t1"]?.map(\.id) == ["chan1"])
        #expect(session.staleCategoryTeams == ["t1"])
        session.stop()
    }

    func holdFirstReload(_ server: MockServer, gate: Gate, fresh: [String]) {
        let stale = Fixtures.json(Fixtures.categories([channelsCategory(["c-town", "c-dev"], sorting: "")]))
        let current = Fixtures.json(Fixtures.categories([channelsCategory(fresh)]))
        let transport = server.transport
        let path = Self.batch
        transport.on("GET", path) { _ in
            guard transport.count("GET", path) == 2 else { return .json(current) }
            await gate.wait()
            return .json(stale)
        }
    }

    @Test func eventDuringReloadFetchesAgain() async {
        let server = MockServer()
        let session = await server.startedSession()
        let gate = Gate()
        holdFirstReload(server, gate: gate, fresh: ["c-town", "c-dev"])
        let reload = Task { await session.reloadCategories(teamId: "t1") }
        #expect(await eventually { server.transport.count("GET", Self.batch) == 2 })
        session.apply(updated([channelsCategory(["c-town", "c-dev"])]))
        await gate.open()
        await reload.value
        #expect(server.transport.count("GET", Self.batch) == 3)
        #expect(session.categories["t1"]?.first?.sorting == .manual)
        session.stop()
    }

    @Test func writeDuringReloadFetchesAgain() async {
        let server = MockServer()
        server.transport.on("PUT", Self.batch) { .json($0.bodyText) }
        let session = await server.startedSession()
        let gate = Gate()
        holdFirstReload(server, gate: gate, fresh: ["c-town", "c-dev"])
        let reload = Task { await session.reloadCategories(teamId: "t1") }
        #expect(await eventually { server.transport.count("GET", Self.batch) == 2 })
        #expect(await session.moveChannel("c-town", toCategory: "chan1", index: 0))
        await gate.open()
        await reload.value
        #expect(server.transport.count("GET", Self.batch) == 3)
        #expect(session.categories["t1"]?.first?.channelIds == ["c-town", "c-dev"])
        #expect(session.categories["t1"]?.first?.sorting == .manual)
        session.stop()
    }
}

@MainActor
@Suite struct SidebarCategoryEventTests {
    static let categories = "users/me/teams/t1/channels/categories"

    @Test func updatedCategoriesApplyWithoutRefetch() async {
        let server = MockServer()
        let session = await server.startedSession()
        let channels = Fixtures.category("chan1", user: "me1", team: "t1", type: "channels", display: "Renamed", sorting: "manual", channels: ["c-town", "c-dev"])
        session.apply(Fixtures.wsEvent("sidebar_category_updated", data: ["updatedCategories": Fixtures.json([channels])], team: "t1", user: "me1"))
        #expect(session.sidebar[1].title == "Renamed")
        #expect(session.sidebar[1].channelIds == ["c-town", "c-dev"])
        session.apply(Fixtures.wsEvent("sidebar_category_updated", data: ["updatedCategories": Fixtures.json([channels])], team: "t1", user: "me1"))
        await settle()
        #expect(server.transport.count("GET", Self.categories) == 1)
        let unknown = Fixtures.category("new1", user: "me1", team: "t1", type: "custom", display: "New", channels: [])
        session.apply(Fixtures.wsEvent("sidebar_category_updated", data: ["updatedCategories": Fixtures.json([unknown])], team: "t1", user: "me1"))
        #expect(await eventually { server.transport.count("GET", Self.categories) == 2 })
        session.stop()
    }

    @Test func orderEventsApplyWithoutRefetch() async {
        let server = MockServer()
        let session = await server.startedSession()
        session.apply(Fixtures.wsEvent("sidebar_category_order_updated", data: ["order": ["dm1", "chan1", "fav1"]], team: "t1", user: "me1"))
        #expect(session.sidebar.map(\.id) == ["dm1", "chan1", "fav1"])
        await settle()
        #expect(server.transport.count("GET", Self.categories) == 1)
        session.apply(Fixtures.wsEvent("sidebar_category_order_updated", data: ["order": ["dm1", "ghost"]], team: "t1", user: "me1"))
        #expect(await eventually { server.transport.count("GET", Self.categories) == 2 })
        #expect(await eventually { session.sidebar.map(\.id) == ["fav1", "chan1", "dm1"] })
        session.stop()
    }

    @Test func createdAndDeletedCategoriesReload() async {
        let server = MockServer()
        let session = await server.startedSession()
        session.apply(Fixtures.wsEvent("sidebar_category_deleted", data: ["category_id": "fav1"], team: "t1", user: "me1"))
        #expect(session.categories["t1"]?.map(\.id) == ["chan1", "dm1"])
        #expect(await eventually { server.transport.count("GET", Self.categories) == 2 })
        #expect(await eventually { session.categories["t1"]?.map(\.id) == ["fav1", "chan1", "dm1"] })
        session.apply(Fixtures.wsEvent("sidebar_category_created", data: ["category_id": "x"], team: "t1", user: "me1"))
        #expect(await eventually { server.transport.count("GET", Self.categories) == 3 })
        session.apply(Fixtures.wsEvent("sidebar_category_updated", data: ["updatedCategories": "[]"], team: "t2", user: "me1"))
        await settle()
        #expect(server.transport.count("GET", "users/me/teams/t2/channels/categories") == 0)
        session.stop()
    }

    @Test func eventsForTeamsWithoutCategoriesReload() async {
        let server = MockServer()
        let session = await server.startedSession()
        session.categories["t1"] = nil
        session.apply(Fixtures.wsEvent("sidebar_category_updated", data: ["updatedCategories": Fixtures.json([Fixtures.category("chan1", user: "me1", team: "t1", type: "channels", display: "C", channels: [])])], team: "t1", user: "me1"))
        session.apply(Fixtures.wsEvent("sidebar_category_order_updated", data: ["order": ["chan1"]], team: "t1", user: "me1"))
        #expect(await eventually { server.transport.count("GET", Self.categories) == 3 })
        session.stop()
    }
}
