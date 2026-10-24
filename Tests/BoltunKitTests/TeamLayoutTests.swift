import Foundation
import Testing
@testable import BoltunKit

@Suite struct TeamLayoutTests {
    let teams = ["a", "b", "c", "d", "e"].map { Team(id: $0, name: $0, displayName: $0.uppercased()) }

    func ids(_ layout: TeamLayout) -> [String] { layout.ordered(teams).map(\.id) }

    func favoriteIds(_ layout: TeamLayout) -> [String] { layout.sections(teams).favorites.map(\.id) }

    @Test func emptyLayoutKeepsServerOrder() {
        let layout = TeamLayout()
        #expect(layout.isEmpty)
        #expect(ids(layout) == ["a", "b", "c", "d", "e"])
        #expect(layout.sections(teams).favorites.isEmpty)
    }

    @Test func orderedTeamsFollowSavedOrderAndAppendUnknownTeams() {
        let layout = TeamLayout(order: ["d", "gone", "b"])
        #expect(ids(layout) == ["d", "b", "a", "c", "e"])
    }

    @Test func favoritesComeFirstInSavedOrder() {
        let layout = TeamLayout(order: ["e", "c", "a"], favorites: ["a", "e"])
        let sections = layout.sections(teams)
        #expect(sections.favorites.map(\.id) == ["e", "a"])
        #expect(sections.others.map(\.id) == ["c", "b", "d"])
        #expect(sections.all.map(\.id) == ["e", "a", "c", "b", "d"])
        #expect(layout.isFavorite("a"))
        #expect(!layout.isFavorite("c"))
    }

    @Test func movingDownPlacesTeamAfterTarget() {
        var layout = TeamLayout()
        layout.move("a", to: "c", in: teams)
        #expect(ids(layout) == ["b", "c", "a", "d", "e"])
    }

    @Test func movingUpPlacesTeamBeforeTarget() {
        var layout = TeamLayout()
        layout.move("d", to: "b", in: teams)
        #expect(ids(layout) == ["a", "d", "b", "c", "e"])
    }

    @Test func movingOntoItselfOrUnknownTeamDoesNothing() {
        var layout = TeamLayout()
        layout.move("a", to: "a", in: teams)
        layout.move("a", to: "zzz", in: teams)
        layout.move("zzz", to: "a", in: teams)
        #expect(layout.isEmpty)
    }

    @Test func movingOntoFavoriteMakesTeamFavorite() {
        var layout = TeamLayout(favorites: ["a", "b"])
        layout.move("d", to: "b", in: teams)
        #expect(favoriteIds(layout) == ["a", "d", "b"])
        #expect(ids(layout) == ["a", "d", "b", "c", "e"])
    }

    @Test func movingFavoriteOntoOtherTeamRemovesFavoriteAndInsertsBefore() {
        var layout = TeamLayout(favorites: ["a", "b"])
        layout.move("a", to: "c", in: teams)
        #expect(favoriteIds(layout) == ["b"])
        #expect(ids(layout) == ["b", "a", "c", "d", "e"])
    }

    @Test func moveToEndOfFavoritesAndOthers() {
        var layout = TeamLayout(favorites: ["a"])
        layout.moveToEnd("c", favorite: true, in: teams)
        #expect(ids(layout) == ["a", "c", "b", "d", "e"])
        #expect(favoriteIds(layout) == ["a", "c"])
        layout.moveToEnd("a", favorite: false, in: teams)
        #expect(ids(layout) == ["c", "b", "d", "e", "a"])
        #expect(favoriteIds(layout) == ["c"])
        let before = layout
        layout.moveToEnd("zzz", favorite: true, in: teams)
        #expect(layout == before)
    }

    @Test func setFavoriteAppendsToFavoritesAndUnfavoriteReturnsToTopOfOthers() {
        var layout = TeamLayout()
        layout.setFavorite("c", true, in: teams)
        layout.setFavorite("e", true, in: teams)
        #expect(favoriteIds(layout) == ["c", "e"])
        #expect(ids(layout) == ["c", "e", "a", "b", "d"])
        layout.setFavorite("c", false, in: teams)
        #expect(favoriteIds(layout) == ["e"])
        #expect(ids(layout) == ["e", "c", "a", "b", "d"])
        let before = layout
        layout.setFavorite("e", true, in: teams)
        layout.setFavorite("zzz", true, in: teams)
        #expect(layout == before)
    }

    @Test func layoutKeepsOrderOfTeamsThatAreNotLoaded() {
        var layout = TeamLayout(order: ["x", "a"], favorites: ["x"])
        layout.move("b", to: "a", in: teams)
        #expect(layout.order.contains("x"))
        #expect(layout.favorites == ["x"])
    }

    @Test func decodesMissingFieldsAndRoundTrips() throws {
        let empty = try JSONDecoder().decode(TeamLayout.self, from: Data("{}".utf8))
        #expect(empty == TeamLayout())
        let layout = TeamLayout(order: ["b", "a"], favorites: ["a"])
        let decoded = try JSONDecoder().decode(TeamLayout.self, from: JSONEncoder().encode(layout))
        #expect(decoded == layout)
    }

    @Test func serverConfigDecodesLegacyStateWithoutTeamLayout() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"One","url":"https://one.example.com","lastChannelByTeam":{}}"#
        let config = try JSONDecoder().decode(ServerConfig.self, from: Data(json.utf8))
        #expect(config.teamLayout == TeamLayout())
        var updated = config
        updated.teamLayout = TeamLayout(order: ["t2", "t1"], favorites: ["t2"])
        let roundTrip = try JSONDecoder().decode(ServerConfig.self, from: JSONEncoder().encode(updated))
        #expect(roundTrip.teamLayout == updated.teamLayout)
    }
}

@MainActor
@Suite struct ServerSessionTeamLayoutTests {
    @Test func sessionOrdersTeamsAndReportsChanges() async {
        let server = MockServer()
        let session = await server.startedSession()
        var reported: [TeamLayout] = []
        session.onTeamLayoutChange = { reported.append($0) }
        #expect(session.orderedTeams.map(\.id) == ["t1", "t2"])
        session.moveTeam("t2", to: "t1")
        #expect(session.orderedTeams.map(\.id) == ["t2", "t1"])
        session.setFavorite(teamId: "t1", favorite: true)
        #expect(session.isFavorite(teamId: "t1"))
        #expect(session.teamSections.favorites.map(\.id) == ["t1"])
        #expect(session.orderedTeams.map(\.id) == ["t1", "t2"])
        session.moveTeamToEnd("t2", favorite: true)
        #expect(session.teamSections.favorites.map(\.id) == ["t1", "t2"])
        #expect(reported.count == 3)
        session.setFavorite(teamId: "t1", favorite: true)
        #expect(reported.count == 3)
        session.stop()
    }

    @Test func layoutDecidesFallbackTeamWhenCurrentTeamDisappears() async {
        let server = MockServer()
        let session = server.session()
        session.teamLayout = TeamLayout(order: ["t2", "t1"])
        session.currentTeamId = "missing"
        await session.start()
        #expect(session.currentTeamId == "t2")
        session.stop()
    }
}

@MainActor
@Suite struct AppModelTeamLayoutTests {
    @Test func sessionStartsWithSavedLayoutAndPersistsChanges() async throws {
        let harness = AppHarness()
        var state = harness.store.load()
        state.servers[0].teamLayout = TeamLayout(order: ["t2", "t1"])
        try harness.store.save(state)
        let app = harness.model()
        let session = app.makeSession(for: app.servers[0])
        #expect(session.teamLayout.order == ["t2", "t1"])
        await session.start()
        #expect(session.orderedTeams.map(\.id) == ["t2", "t1"])
        session.setFavorite(teamId: "t1", favorite: true)
        #expect(app.servers[0].teamLayout.favorites == ["t1"])
        #expect(harness.store.load().servers[0].teamLayout.favorites == ["t1"])
        #expect(harness.store.load().servers[0].teamLayout.order == ["t1", "t2"])
        app.rememberTeamLayout(serverId: UUID(), layout: TeamLayout(order: ["x"]))
        #expect(harness.store.load().servers.allSatisfy { $0.teamLayout.order != ["x"] })
        session.stop()
    }

    @Test func restoresFirstTeamInSavedOrder() async throws {
        let harness = AppHarness()
        var state = harness.store.load()
        state.servers[0].teamLayout = TeamLayout(order: ["t2", "t1"])
        try harness.store.save(state)
        let app = harness.model()
        let session = app.makeSession(for: app.servers[0])
        await session.start()
        await app.restoreSelection(serverId: app.servers[0].id)
        #expect(session.currentTeamId == "t2")
        session.stop()
    }
}
