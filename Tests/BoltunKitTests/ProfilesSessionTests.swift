import Foundation
import Testing
@testable import BoltunKit

@Suite struct ProfileModelTests {
    @Test func userDecodesBotDescriptionPropsAndRoles() throws {
        var raw = Fixtures.user("b1", "helper", roles: "system_user system_guest")
        raw["is_bot"] = true
        raw["bot_description"] = "Helps out."
        raw["props"] = ["show_last_active": "false", "customStatus": #"{"emoji":"coffee","text":"Break","duration":"dont_clear"}"#, "nested": ["a": 1]]
        let user = try Fixtures.decode(User.self, raw)
        #expect(user.botDescription == "Helps out.")
        #expect(user.isGuest)
        #expect(!user.isSystemAdmin)
        #expect(!user.showsLastActive)
        #expect(user.props["nested"] == nil)
        #expect(user.customStatus == CustomStatus(emoji: "coffee", text: "Break", duration: "dont_clear"))
        let plain = try Fixtures.decode(User.self, Fixtures.user("u1", "plain"))
        #expect(plain.botDescription.isEmpty)
        #expect(plain.props.isEmpty)
        #expect(plain.showsLastActive)
        #expect(plain.customStatus == nil)
        #expect(!plain.isGuest)
    }

    @Test func currentTimezoneFollowsAutomaticFlag() {
        #expect(User(id: "u", username: "u").currentTimezone == nil)
        let automatic = User(id: "u", username: "u", timezone: ["useAutomaticTimezone": "true", "automaticTimezone": "Asia/Tokyo", "manualTimezone": "Europe/Paris"])
        #expect(automatic.currentTimezone == "Asia/Tokyo")
        let manual = User(id: "u", username: "u", timezone: ["useAutomaticTimezone": "false", "automaticTimezone": "Asia/Tokyo", "manualTimezone": "Europe/Paris"])
        #expect(manual.currentTimezone == "Europe/Paris")
        let blank = User(id: "u", username: "u", timezone: ["useAutomaticTimezone": "true"])
        #expect(blank.currentTimezone == "")
    }

    @Test func customStatusParsesExpiryAndState() throws {
        let fractional = try #require(CustomStatus(json: #"{"emoji":"calendar","text":"Meeting","duration":"one_hour","expires_at":"2026-10-24T15:30:00.000Z"}"#))
        let expiry = try #require(fractional.expiresAt)
        #expect(expiry == Date(timeIntervalSince1970: 1_792_855_800))
        #expect(fractional.isSet)
        #expect(fractional.showsExpiry)
        #expect(!fractional.isExpired(now: expiry.addingTimeInterval(-1)))
        #expect(fractional.isExpired(now: expiry))
        let plain = try #require(CustomStatus(json: #"{"text":"Away","duration":"date_and_time","expires_at":"2026-10-24T15:30:00Z"}"#))
        #expect(plain.expiresAt == expiry)
        let forever = CustomStatus(emoji: "x", duration: CustomStatus.dontClear, expiresAt: expiry)
        #expect(!forever.isExpired(now: expiry.addingTimeInterval(100)))
        #expect(!forever.showsExpiry)
        let noExpiry = try #require(CustomStatus(json: #"{"emoji":"x"}"#))
        #expect(!noExpiry.isExpired(now: Date()))
        #expect(!noExpiry.showsExpiry)
        #expect(CustomStatus(json: #"{"text":"bad","expires_at":"soon"}"#)?.expiresAt == nil)
        #expect(!CustomStatus().isSet)
        #expect(CustomStatus(json: "{broken") == nil)
    }

    @Test func membershipsDecodeSchemeAdmin() throws {
        var member = Fixtures.member("c1", user: "u1")
        #expect(try !Fixtures.decode(ChannelMember.self, member).schemeAdmin)
        member["scheme_admin"] = true
        #expect(try Fixtures.decode(ChannelMember.self, member).schemeAdmin)
        let team = try Fixtures.decode(TeamMember.self, ["team_id": "t1", "user_id": "u1", "roles": "team_user team_admin", "scheme_admin": true])
        #expect(team.schemeAdmin)
        #expect(try !Fixtures.decode(TeamMember.self, ["team_id": "t1", "user_id": "u1"]).schemeAdmin)
    }

    @Test func clientConfigProfileFlags() {
        let enabled = ClientConfig(values: ["EnableCustomUserStatuses": "true", "EnableLastActiveTime": "true"])
        #expect(enabled.enableCustomUserStatuses)
        #expect(enabled.enableLastActiveTime)
        #expect(!ClientConfig(values: [:]).enableCustomUserStatuses)
        #expect(!ClientConfig(values: [:]).enableLastActiveTime)
    }

    @Test func mentionCandidatesTrimTrailingPunctuation() {
        #expect(ServerSession.mentionCandidates("@Bob.") == ["bob.", "bob"])
        #expect(ServerSession.mentionCandidates("carol_-") == ["carol_-", "carol_", "carol"])
        #expect(ServerSession.mentionCandidates("john.smith") == ["john.smith"])
        #expect(ServerSession.mentionCandidates("channel").isEmpty)
        #expect(ServerSession.mentionCandidates("here.") == ["here."])
        #expect(ServerSession.mentionCandidates("@").isEmpty)
    }
}

@Suite struct MembersEndpointTests {
    @Test func endpointsUseWebappRoutes() async throws {
        let transport = FakeTransport()
        transport.on("GET", "users/u2", object: Fixtures.user("u2", "bob"))
        transport.on("GET", "teams/t1/members/u2", object: ["team_id": "t1", "user_id": "u2", "scheme_admin": true])
        transport.on("GET", "channels/c1/members/u2", object: Fixtures.member("c1", user: "u2"))
        transport.on("GET", "users", object: [Fixtures.user("u2", "bob")])
        transport.on("POST", "channels/c1/members/ids", object: [Fixtures.member("c1", user: "u2")])
        transport.on("POST", "users/search", object: [Fixtures.user("u2", "bob")])
        let client = APIClient(baseURL: MockServer.baseURL, token: "t", transport: transport)
        #expect(try await client.user(id: "u2").username == "bob")
        #expect(try await client.teamMember(teamId: "t1", userId: "u2").schemeAdmin)
        #expect(try await client.channelMember(channelId: "c1", userId: "u2").userId == "u2")
        #expect(try await client.profilesInChannel(channelId: "c1", page: 2, perPage: 100).count == 1)
        let query = try #require(transport.last("GET", "users")).query
        #expect(query == ["in_channel": "c1", "page": "2", "per_page": "100", "sort": "admin"])
        #expect(try await client.channelMembers(channelId: "c1", userIds: []).isEmpty)
        #expect(transport.count("POST", "channels/c1/members/ids") == 0)
        #expect(try await client.channelMembers(channelId: "c1", userIds: ["u2", "u3"]).count == 1)
        #expect(try #require(transport.last("POST", "channels/c1/members/ids")).jsonBody as? [String] == ["u2", "u3"])
        #expect(try await client.searchUsers(term: "bo", channelId: "c1").count == 1)
        let body = try #require(transport.last("POST", "users/search")).jsonObject
        #expect(body["term"] as? String == "bo")
        #expect(body["in_channel_id"] as? String == "c1")
        #expect(body.count == 2)
    }
}

@MainActor
@Suite struct ProfileSessionTests {
    func server() -> MockServer {
        let server = MockServer()
        var bob = Fixtures.user("u2", "bob", first: "Bob", last: "Builder")
        bob["position"] = "Engineer"
        server.transport.on("GET", "users/u2", object: bob)
        server.transport.on("GET", "teams/t1/members/u2", object: ["team_id": "t1", "user_id": "u2", "scheme_admin": true])
        var member = Fixtures.member("c-town", user: "u2")
        member["scheme_admin"] = true
        server.transport.on("GET", "channels/c-town/members/u2", object: member)
        return server
    }

    @Test func loadProfileFetchesOnceAndCaches() async {
        let server = server()
        let session = await server.startedSession()
        session.statuses["u2"] = nil
        session.lastActivity["u2"] = nil
        await session.loadProfile(userId: "u2", channelId: "c-town")
        #expect(session.users["u2"]?.position == "Engineer")
        #expect(session.statuses["u2"] == .online)
        #expect(session.lastActivity["u2"] == 1)
        #expect(session.teamMembership(teamId: "t1", userId: "u2")?.schemeAdmin == true)
        #expect(session.channelMembership(channelId: "c-town", userId: "u2")?.schemeAdmin == true)
        let statusRequests = server.transport.count("POST", "users/status/ids")
        await session.loadProfile(userId: "u2", channelId: "c-town")
        #expect(server.transport.count("GET", "users/u2") == 1)
        #expect(server.transport.count("GET", "teams/t1/members/u2") == 1)
        #expect(server.transport.count("GET", "channels/c-town/members/u2") == 1)
        #expect(server.transport.count("POST", "users/status/ids") == statusRequests)
        await session.loadProfile(userId: "", channelId: nil)
        #expect(session.channelMembership(channelId: "c-town", userId: "me1")?.userId == "me1")
        session.stop()
    }

    @Test func failedLookupsAreRetriedButMissingMembershipsAreNot() async {
        let server = MockServer()
        let session = await server.startedSession()
        await session.loadProfile(userId: "u9", channelId: "c-town")
        #expect(session.users["u9"] == nil)
        server.transport.on("GET", "users/u9", object: Fixtures.user("u9", "zed"))
        await session.loadProfile(userId: "u9", channelId: "c-town")
        #expect(session.users["u9"]?.username == "zed")
        #expect(server.transport.count("GET", "users/u9") == 2)
        #expect(server.transport.count("GET", "teams/t1/members/u9") == 1)
        #expect(server.transport.count("GET", "channels/c-town/members/u9") == 1)
        session.stop()
    }

    @Test func statusLookupIsSkippedWhenStatusesAreDisabled() async {
        let server = server()
        var config = Fixtures.clientConfig
        config["EnableUserStatuses"] = "false"
        server.transport.on("GET", "config/client", object: config)
        let session = await server.startedSession()
        server.transport.reset()
        session.statuses["u2"] = nil
        await session.loadProfile(userId: "u2", channelId: nil)
        #expect(server.transport.count("POST", "users/status/ids") == 0)
        #expect(server.transport.count("GET", "channels/c-town/members/u2") == 0)
        session.stop()
    }

    @Test func channelMembersPageStoresUsersRosterAndStatuses() async {
        let server = MockServer()
        server.transport.on("GET", "users", object: [Fixtures.user("u2", "bob"), Fixtures.user("u4", "dave")])
        server.transport.on("POST", "channels/c-town/members/ids") { request in
            let ids = request.jsonBody as? [String] ?? []
            return .object(ids.map { id -> [String: Any] in
                var member = Fixtures.member("c-town", user: id)
                member["scheme_admin"] = id == "u4"
                return member
            })
        }
        let session = await server.startedSession()
        let page = await session.loadChannelMembers(channelId: "c-town", page: 0, perPage: 100)
        #expect(page?.map(\.id) == ["u2", "u4"])
        #expect(session.users["u4"]?.username == "dave")
        #expect(session.channelMembership(channelId: "c-town", userId: "u4")?.schemeAdmin == true)
        #expect(session.channelMembership(channelId: "c-town", userId: "u2")?.schemeAdmin == false)
        #expect(session.statuses["u4"] == .online)
        await session.loadProfile(userId: "u4", channelId: "c-town")
        #expect(server.transport.count("GET", "users/u4") == 0)
        #expect(server.transport.count("GET", "channels/c-town/members/u4") == 0)
        server.transport.on("POST", "users/search", object: [Fixtures.user("u5", "erin")])
        let found = await session.searchChannelMembers(channelId: "c-town", term: "er")
        #expect(found?.map(\.id) == ["u5"])
        #expect(session.channelMembership(channelId: "c-town", userId: "u5") != nil)
        session.stop()
    }

    @Test func failedMemberRequestsReturnNil() async {
        let server = MockServer()
        server.transport.on("GET", "users", .error(500))
        server.transport.on("POST", "users/search", .error(500))
        let session = await server.startedSession()
        #expect(await session.loadChannelMembers(channelId: "c-town", page: 0, perPage: 100) == nil)
        #expect(await session.searchChannelMembers(channelId: "c-town", term: "x") == nil)
        session.stop()
    }

    @Test func realtimeEventsUpdateLoadedRoster() async {
        let server = server()
        let session = await server.startedSession()
        var other = Fixtures.member("c-dev", user: "u2")
        other["scheme_admin"] = true
        session.apply(Fixtures.wsEvent("channel_member_updated", data: ["channelMember": Fixtures.json(other)], user: "u2"))
        #expect(session.channelMembership(channelId: "c-dev", userId: "u2") == nil)
        await session.loadProfile(userId: "u2", channelId: "c-town")
        var demoted = Fixtures.member("c-town", user: "u2")
        demoted["scheme_admin"] = false
        session.apply(Fixtures.wsEvent("channel_member_updated", data: ["channelMember": Fixtures.json(demoted)], user: "u2"))
        #expect(session.channelMembership(channelId: "c-town", userId: "u2")?.schemeAdmin == false)
        session.apply(Fixtures.wsEvent("user_removed", data: ["user_id": "u3", "remover_id": "u2"], channel: "c-town"))
        #expect(session.channelMembership(channelId: "c-town", userId: "u2") != nil)
        session.apply(Fixtures.wsEvent("user_removed", data: ["user_id": "u2", "remover_id": "u3"], channel: "c-town"))
        #expect(session.channelMembership(channelId: "c-town", userId: "u2") == nil)
        #expect(session.members["c-town"] != nil)
        session.stop()
    }

    @Test func mentionNamesResolveFromCacheThenServer() async throws {
        let server = MockServer()
        server.transport.on("POST", "users/usernames") { request in
            let names = request.jsonBody as? [String] ?? []
            return .object(names.contains("zed") ? [Fixtures.user("u9", "zed")] : [])
        }
        let session = await server.startedSession()
        session.users["u2"] = User(id: "u2", username: "bob")
        #expect(await session.user(mentionName: "Bob.")?.id == "u2")
        #expect(server.transport.count("POST", "users/usernames") == 0)
        #expect(await session.user(mentionName: "zed_")?.id == "u9")
        #expect(try #require(server.transport.last("POST", "users/usernames")).jsonBody as? [String] == ["zed_", "zed"])
        #expect(await session.user(mentionName: "nobody") == nil)
        #expect(await session.user(mentionName: "all") == nil)
        session.stop()
    }
}
