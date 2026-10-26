import Foundation
import Testing
@testable import BoltunKit

@Suite struct AccountNotifySettingsTests {
    let server = User(id: "me", username: "alice", firstName: "Ada", notifyProps: [
        "channel": "true",
        "desktop": "mention",
        "desktop_threads": "all",
        "first_name": "false",
        "mention_keys": "",
        "push": "mention",
        "email": "true",
    ])

    func user(_ props: [String: String], username: String = "alice") -> User {
        User(id: "me", username: username, firstName: "Ada", notifyProps: props)
    }

    @Test func serverDefaultsReadAsMentionsWithChannelWideMentions() {
        let settings = AccountNotifySettings(user: server)
        #expect(settings == AccountNotifySettings())
        #expect(settings.desktop == .mention)
        #expect(settings.threadReplies)
        #expect(settings.channelWide)
        #expect(!settings.firstName)
        #expect(!settings.username)
        #expect(settings.keywords.isEmpty)
    }

    @Test func missingOrUnknownPropsFallBackToServerDefaults() {
        #expect(AccountNotifySettings(user: user([:])) == AccountNotifySettings())
        #expect(AccountNotifySettings(user: user(["desktop": "default", "desktop_threads": "default"])) == AccountNotifySettings())
        #expect(AccountNotifySettings(user: user(["desktop": "loud"])).desktop == .mention)
    }

    @Test func readsEveryTrigger() {
        let settings = AccountNotifySettings(user: user([
            "desktop": "all",
            "desktop_threads": "mention",
            "first_name": "true",
            "channel": "false",
            "mention_keys": "deploy, Alice ,release,,@alice, DEPLOY",
        ]))
        #expect(settings.desktop == .all)
        #expect(!settings.threadReplies)
        #expect(settings.firstName)
        #expect(!settings.channelWide)
        #expect(settings.username)
        #expect(settings.keywords == ["deploy", "release"])
        #expect(AccountNotifySettings(user: user(["desktop": "none", "desktop_threads": "none"])).desktop == .none)
        #expect(!AccountNotifySettings(user: user(["desktop_threads": "none"])).threadReplies)
    }

    @Test func writesTheFullPropsMapKeepingUnrelatedProps() {
        var settings = AccountNotifySettings(user: server)
        settings.desktop = .all
        settings.threadReplies = false
        settings.firstName = true
        settings.username = true
        settings.channelWide = false
        settings.keywords = ["deploy", "ALICE", "release", "Deploy", "@alice"]
        let props = settings.notifyProps(for: server)
        #expect(props == [
            "channel": "false",
            "desktop": "all",
            "desktop_threads": "mention",
            "first_name": "true",
            "mention_keys": "deploy,release,alice",
            "push": "mention",
            "email": "true",
        ])
        #expect(AccountNotifySettings(user: user(props)) == AccountNotifySettings(
            desktop: .all, threadReplies: false, firstName: true, username: true, channelWide: false, keywords: ["deploy", "release"]
        ))
    }

    @Test func roundTripLeavesServerDefaultsUntouchedExceptExplicitFlags() {
        let props = AccountNotifySettings(user: server).notifyProps(for: server)
        #expect(props == server.notifyProps)
    }

    @Test func usernameKeywordNeedsAUsername() {
        let anonymous = user([:], username: "")
        let settings = AccountNotifySettings(username: true, keywords: ["deploy"])
        #expect(settings.mentionKeys(for: anonymous) == ["deploy"])
        #expect(!AccountNotifySettings(user: user(["mention_keys": "@"], username: "")).username)
    }

    @Test func keywordParsingTrimsAndDeduplicates() {
        #expect(AccountNotifySettings.parseKeywords("") == [])
        #expect(AccountNotifySettings.parseKeywords(" , ,") == [])
        #expect(AccountNotifySettings.parseKeywords("deploy,\n release train , Deploy") == ["deploy", "release train"])
    }

    @Test func levelsOfferAllMentionAndNothing() {
        #expect(AccountNotifySettings.levels == [.all, .mention, .none])
    }

    @Test func keywordsIncludeFirstNameOnlyWhenEnabled() {
        #expect(ChannelMention.keywords(user(["mention_keys": "deploy"])) == ["deploy"])
        #expect(ChannelMention.keywords(user(["mention_keys": "deploy, alice", "first_name": "true"])) == ["deploy", "alice", "Ada"])
        #expect(ChannelMention.keywords(user(["mention_keys": "@, "])) == [])
    }
}

@MainActor
@Suite struct AccountNotifySessionTests {
    static let patch = "users/me/patch"

    func echoingServer() -> MockServer {
        let server = MockServer()
        server.transport.on("PUT", Self.patch) { request in
            var user = Fixtures.user("me1", "alice", first: "Alice", last: "Liddell")
            user["notify_props"] = request.jsonObject["notify_props"]
            user["update_at"] = 1_800_000_000_000
            return .object(user)
        }
        return server
    }

    @Test func endpointPatchesNotifyPropsOfTheCurrentUser() async throws {
        let transport = FakeTransport()
        transport.on("PUT", Self.patch, object: Fixtures.user("me1", "alice", desktop: "all"))
        let client = APIClient(baseURL: MockServer.baseURL, token: "t", transport: transport)
        let user = try await client.updateMyNotifyProps(["desktop": "all"])
        #expect(user.notifyProps["desktop"] == "all")
        let request = try #require(transport.last("PUT", Self.patch))
        #expect(request.url?.path == "/api/v4/users/me/patch")
        #expect(request.jsonObject["notify_props"] as? [String: String] == ["desktop": "all"])
    }

    @Test func applyingSendsTheMergedPropsAndAdoptsTheServerUser() async throws {
        let server = echoingServer()
        let session = await server.startedSession()
        var settings = try #require(session.accountNotifySettings)
        #expect(settings.desktop == .mention)
        settings.desktop = .all
        settings.keywords = ["deploy"]
        settings.firstName = true
        #expect(await session.applyAccountNotifySettings(settings))
        let sent = try #require(server.transport.last("PUT", Self.patch)?.jsonObject["notify_props"] as? [String: String])
        #expect(sent["desktop"] == "all")
        #expect(sent["mention_keys"] == "deploy")
        #expect(sent["first_name"] == "true")
        #expect(sent["push"] == "mention")
        #expect(sent["email"] == "true")
        #expect(session.me?.updateAt == 1_800_000_000_000)
        #expect(session.users["me1"]?.notifyProps == sent)
        #expect(session.accountNotifySettings == settings)
        #expect(ChannelMention.userKeys(session.me!) == ["@alice", "deploy", "Alice"])
        session.stop()
    }

    @Test func unchangedSettingsSkipTheServer() async throws {
        let server = echoingServer()
        let session = await server.startedSession()
        let settings = try #require(session.accountNotifySettings)
        #expect(await session.applyAccountNotifySettings(settings))
        #expect(server.transport.count("PUT", Self.patch) == 0)
        session.stop()
    }

    @Test func signedOutSessionsCannotApply() async {
        let session = MockServer().session()
        #expect(session.accountNotifySettings == nil)
        #expect(!(await session.applyAccountNotifySettings(AccountNotifySettings(desktop: .all))))
    }

    @Test func failuresRollBackAndReport() async throws {
        let server = MockServer()
        server.transport.on("PUT", Self.patch, .error(403, message: "not allowed"))
        let session = await server.startedSession()
        let before = session.me?.notifyProps
        var settings = try #require(session.accountNotifySettings)
        settings.desktop = .none
        #expect(!(await session.applyAccountNotifySettings(settings)))
        #expect(session.me?.notifyProps == before)
        #expect(session.users["me1"]?.notifyProps == before)
        #expect(session.lastError == "not allowed")
        session.stop()
    }

    @Test func staleResponsesDoNotOverwriteNewerChanges() async throws {
        let server = MockServer()
        let gate = Gate()
        server.hold("PUT", Self.patch, gate: gate) { _ in .error(500) }
        let session = await server.startedSession()
        var settings = try #require(session.accountNotifySettings)
        settings.desktop = .all
        let task = Task { await session.applyAccountNotifySettings(settings) }
        #expect(await eventually { server.transport.count("PUT", Self.patch) == 1 })
        session.me?.notifyProps["desktop"] = "none"
        await gate.open()
        #expect(!(await task.value))
        #expect(session.me?.notifyProps["desktop"] == "none")
        session.stop()
    }

    @Test func successfulResponsesDoNotOverwriteNewerChanges() async throws {
        let server = MockServer()
        let gate = Gate()
        server.hold("PUT", Self.patch, gate: gate) { _ in .object(Fixtures.user("me1", "alice", desktop: "all")) }
        let session = await server.startedSession()
        var settings = try #require(session.accountNotifySettings)
        settings.desktop = .all
        let task = Task { await session.applyAccountNotifySettings(settings) }
        #expect(await eventually { server.transport.count("PUT", Self.patch) == 1 })
        session.me?.notifyProps["desktop"] = "none"
        await gate.open()
        #expect(await task.value)
        #expect(session.me?.notifyProps["desktop"] == "none")
        session.stop()
    }

    @Test func allNewMessagesNotifyUnlessTheChannelIsMuted() async throws {
        let server = echoingServer()
        server.transport.on("PUT", "channels/c-dev/members/me1/notify_props", .ok)
        let session = await server.startedSession()
        let box = NotificationBox()
        session.onNotification = { box.items.append($0) }
        session.isAppActive = { false }
        session.apply(Fixtures.posted(Fixtures.post("n0", channel: "c-dev", user: "u2", message: "lunch?", createAt: 900)))
        #expect(box.items.isEmpty)
        var settings = try #require(session.accountNotifySettings)
        settings.desktop = .all
        #expect(await session.applyAccountNotifySettings(settings))
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-dev", user: "u2", message: "lunch?", createAt: 1000)))
        #expect(box.items.map(\.postId) == ["n1"])
        #expect(await session.setMuted(channelId: "c-dev", true))
        session.apply(Fixtures.posted(Fixtures.post("n2", channel: "c-dev", user: "u2", message: "still lunch?", createAt: 1100)))
        #expect(box.items.map(\.postId) == ["n1"])
        session.apply(Fixtures.posted(Fixtures.post("n3", channel: "c-dev", user: "u2", message: "@alice lunch?", createAt: 1200), mentions: ["me1"]))
        #expect(box.items.map(\.postId) == ["n1"])
        settings.desktop = .none
        #expect(await session.applyAccountNotifySettings(settings))
        session.apply(Fixtures.posted(Fixtures.post("n4", channel: "c-dm", user: "u2", message: "ping", createAt: 1300), channelType: "D", team: ""))
        #expect(box.items.count == 1)
        session.stop()
    }

    @Test func customKeywordsAndChannelWideMentionsFollowTheAccount() async throws {
        let server = echoingServer()
        let session = await server.startedSession()
        let box = NotificationBox()
        session.onNotification = { box.items.append($0) }
        session.isAppActive = { false }
        var settings = try #require(session.accountNotifySettings)
        settings.keywords = ["deploy"]
        settings.channelWide = false
        #expect(await session.applyAccountNotifySettings(settings))
        session.apply(Fixtures.posted(Fixtures.post("k1", channel: "c-dev", user: "u2", message: "Deploy finished", createAt: 1000), mentions: ["me1"]))
        #expect(box.items.map(\.postId) == ["k1"])
        session.apply(Fixtures.posted(Fixtures.post("k2", channel: "c-dev", user: "u2", message: "@here standup", createAt: 1100), mentions: ["me1"]))
        #expect(box.items.map(\.postId) == ["k1"])
        session.members["c-dev"]?.notifyProps["mark_unread"] = "mention"
        session.apply(Fixtures.posted(Fixtures.post("k3", channel: "c-dev", user: "u2", message: "Deploy again", createAt: 1200), mentions: ["me1"]))
        #expect(box.items.map(\.postId) == ["k1"])
        session.stop()
    }

    @Test func userUpdatedEventsRefreshTheAccountSettings() async throws {
        let session = await echoingServer().startedSession()
        var user = Fixtures.user("me1", "alice", first: "Alice", desktop: "all")
        user["notify_props"] = ["desktop": "all", "mention_keys": "deploy,alice", "channel": "false"]
        session.apply(Fixtures.wsEvent("user_updated", data: ["user": Fixtures.json(user)], user: "me1"))
        let settings = try #require(session.accountNotifySettings)
        #expect(settings.desktop == .all)
        #expect(settings.username)
        #expect(settings.keywords == ["deploy"])
        #expect(!settings.channelWide)
        session.stop()
    }
}
