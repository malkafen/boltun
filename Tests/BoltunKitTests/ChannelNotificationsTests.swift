import Foundation
import Testing
@testable import BoltunKit

@Suite struct ChannelNotifySettingsTests {
    let user = User(id: "me", username: "alice", notifyProps: ["desktop": "mention", "desktop_threads": "all", "channel": "true"])

    func member(_ props: [String: String]) -> ChannelMember {
        ChannelMember(channelId: "c", userId: "me", notifyProps: props)
    }

    @Test func levelParsesPropsAndFallsBackToDefault() {
        #expect(NotificationLevel(prop: "all") == .all)
        #expect(NotificationLevel(prop: "mention") == .mention)
        #expect(NotificationLevel(prop: "none") == .none)
        #expect(NotificationLevel(prop: "default") == .default)
        #expect(NotificationLevel(prop: nil) == .default)
        #expect(NotificationLevel(prop: "nonsense") == .default)
    }

    @Test func settingsReadRawChannelProps() {
        let settings = ChannelNotifySettings(member: member([
            "mark_unread": "mention",
            "desktop": "all",
            "desktop_threads": "mention",
            "ignore_channel_mentions": "off",
        ]), user: user)
        #expect(settings.muted)
        #expect(settings.desktop == .all)
        #expect(settings.desktopThreads == .mention)
        #expect(settings.ignoreChannelMentions == .off)
        #expect(!settings.ignoresChannelMentions(user: user))
    }

    @Test func missingMemberIsAllDefaults() {
        let settings = ChannelNotifySettings(member: nil, user: user)
        #expect(settings == ChannelNotifySettings())
        #expect(!settings.muted)
        #expect(settings.desktop == .default)
    }

    @Test func ignoreChannelMentionsDefaultsFollowMuteAndUserProp() {
        let ignoringUser = User(id: "me", username: "alice", notifyProps: ["channel": "false"])
        #expect(IgnoreChannelMentions(prop: "on") == .on)
        #expect(IgnoreChannelMentions(prop: "nonsense") == .default)
        #expect(!ChannelNotifySettings().ignoresChannelMentions(user: user))
        #expect(ChannelNotifySettings(muted: true).ignoresChannelMentions(user: user))
        #expect(ChannelNotifySettings().ignoresChannelMentions(user: ignoringUser))
        #expect(ChannelNotifySettings().ignoresChannelMentions(user: nil) == false)
        #expect(ChannelNotifySettings(ignoreChannelMentions: .on).ignoresChannelMentions(user: user))
        #expect(!ChannelNotifySettings(muted: true, ignoreChannelMentions: .off).ignoresChannelMentions(user: ignoringUser))
        #expect(ChannelNotifySettings(member: member(["mark_unread": "mention"]), user: user).ignoresChannelMentions(user: user))
    }

    @Test func defaultLevelsResolveAgainstUserProps() {
        let settings = ChannelNotifySettings()
        #expect(settings.desktopLevel(user: user) == .mention)
        #expect(settings.desktopThreadsLevel(user: user) == .all)
        let quiet = User(id: "me", username: "alice", notifyProps: ["desktop": "none", "desktop_threads": "mention"])
        #expect(settings.desktopLevel(user: quiet) == .none)
        #expect(settings.desktopThreadsLevel(user: quiet) == .mention)
        #expect(settings.desktopLevel(user: User(id: "me", username: "alice")) == .mention)
        #expect(settings.desktopThreadsLevel(user: User(id: "me", username: "alice")) == .all)
        #expect(settings.desktopLevel(user: nil) == .mention)
        var explicit = settings
        explicit.desktop = .all
        explicit.desktopThreads = .mention
        #expect(explicit.desktopLevel(user: quiet) == .all)
        #expect(explicit.desktopThreadsLevel(user: user) == .mention)
    }

    @Test func changesCarryOnlyEditedProps() {
        let original = ChannelNotifySettings(member: member(["desktop": "all"]), user: user)
        #expect(original.changes(from: original).isEmpty)
        var edited = original
        edited.muted = true
        #expect(edited.changes(from: original) == ["mark_unread": "mention"])
        edited.desktop = .none
        edited.desktopThreads = .all
        edited.ignoreChannelMentions = .on
        #expect(edited.changes(from: original) == [
            "mark_unread": "mention",
            "desktop": "none",
            "desktop_threads": "all",
            "ignore_channel_mentions": "on",
        ])
        var unmuted = ChannelNotifySettings(muted: true)
        unmuted.muted = false
        #expect(unmuted.changes(from: ChannelNotifySettings(muted: true)) == ["mark_unread": "all"])
        var relaxed = ChannelNotifySettings(ignoreChannelMentions: .on)
        relaxed.ignoreChannelMentions = .off
        #expect(relaxed.changes(from: ChannelNotifySettings(ignoreChannelMentions: .on)) == ["ignore_channel_mentions": "off"])
    }

    @Test func mutePropsMatchTheWebapp() {
        #expect(ChannelNotifySettings.muteProps(true) == ["mark_unread": "mention"])
        #expect(ChannelNotifySettings.muteProps(false) == ["mark_unread": "all"])
    }
}

@Suite struct ChannelMentionTests {
    let user = User(id: "me", username: "alice", firstName: "Ada", notifyProps: ["mention_keys": "deploy, release", "first_name": "true"])

    @Test func channelWideKeysAreDetectedOnWordBoundaries() {
        #expect(ChannelMention.isPresent(in: "heads up @channel"))
        #expect(ChannelMention.isPresent(in: "@here please"))
        #expect(ChannelMention.isPresent(in: "ping @all, thanks"))
        #expect(!ChannelMention.isPresent(in: "@channels are nice"))
        #expect(!ChannelMention.isPresent(in: "mail me@alleycat.com"))
        #expect(!ChannelMention.isPresent(in: "nothing here"))
        #expect(!ChannelMention.isPresent(in: ""))
    }

    @Test func userKeysCoverUsernameMentionKeysAndFirstName() {
        #expect(ChannelMention.userKeys(user) == ["@alice", "deploy", "release", "Ada"])
        let bare = User(id: "me", username: "bob")
        #expect(ChannelMention.userKeys(bare) == ["@bob"])
        let noFirstName = User(id: "me", username: "bob", notifyProps: ["first_name": "true"])
        #expect(ChannelMention.userKeys(noFirstName) == ["@bob"])
    }

    @Test func personalMentionsAreRecognised() {
        #expect(ChannelMention.mentionsUser("hi @alice", user: user))
        #expect(ChannelMention.mentionsUser("time to DEPLOY now", user: user))
        #expect(ChannelMention.mentionsUser("Ada, look", user: user))
        #expect(!ChannelMention.mentionsUser("hi @alicia", user: user))
        #expect(!ChannelMention.mentionsUser("deployment pipeline", user: user))
    }

    @Test func channelWideOnlyIgnoresPostsThatNameYou() {
        #expect(ChannelMention.isChannelWideOnly(message: "@channel standup", user: user))
        #expect(!ChannelMention.isChannelWideOnly(message: "@channel and @alice", user: user))
        #expect(!ChannelMention.isChannelWideOnly(message: "just @alice", user: user))
        #expect(!ChannelMention.isChannelWideOnly(message: "quiet", user: user))
    }

    @Test func matchesHandlesEmptyKeys() {
        #expect(!ChannelMention.matches("anything", key: ""))
        #expect(!ChannelMention.matches("", key: "@all"))
    }
}

@Suite struct NotificationPolicyMuteTests {
    let me = User(id: "me", username: "alice", notifyProps: ["desktop": "mention", "desktop_threads": "all"])

    func post(message: String = "hi", rootId: String = "") -> Post {
        Post(id: "p", userId: "other", channelId: "c", rootId: rootId, message: message)
    }

    func member(_ props: [String: String]) -> ChannelMember {
        ChannelMember(channelId: "c", userId: "me", notifyProps: props)
    }

    func notify(
        _ post: Post,
        type: ChannelType = .open,
        mentioned: Bool = false,
        me: User? = nil,
        member: ChannelMember? = nil,
        channelWide: Bool = false,
        teamMuted: Bool = false,
        unknown: Bool = false,
        threadReply: Bool = false,
        following: Bool = true
    ) -> Bool {
        NotificationPolicy.shouldNotify(
            post: post,
            channelType: type,
            mentioned: mentioned,
            me: me ?? self.me,
            member: member,
            myStatus: .online,
            isViewingChannel: false,
            isChannelWideMention: channelWide,
            isTeamMuted: teamMuted,
            isMembershipUnknown: unknown,
            isThreadReply: threadReply,
            isFollowingThread: following
        )
    }

    @Test func mutedChannelsNeverNotifyEvenWhenTagged() {
        let muted = member(["mark_unread": "mention", "desktop": "all"])
        #expect(!notify(post(), mentioned: true, member: muted))
        #expect(!notify(post(), type: .direct, member: muted))
        #expect(!notify(post(message: "@channel deploy"), mentioned: true, member: muted, channelWide: true))
        #expect(!notify(post(message: "@alice can you look?"), mentioned: true, member: muted))
        #expect(!notify(post(message: "ping @alice"), type: .direct, member: muted))
        #expect(!notify(post(message: "@alice reply", rootId: "root"), mentioned: true, member: muted, threadReply: true))
        #expect(notify(post(), member: member(["mark_unread": "all", "desktop": "all"])))
    }

    @Test func mutedTeamsNeverNotifyEvenWhenTagged() {
        #expect(!notify(post(message: "hey @alice"), mentioned: true, teamMuted: true))
        #expect(!notify(post(), member: member(["desktop": "all"]), teamMuted: true))
        #expect(notify(post(message: "hey @alice"), mentioned: true, teamMuted: false))
    }

    @Test func unknownMembershipNotifiesOnlyWhenTagged() {
        #expect(!notify(post(), mentioned: true, unknown: true))
        #expect(!notify(post(), member: member(["desktop": "all"]), unknown: true))
        #expect(!notify(post(message: "@all hands"), mentioned: true, unknown: true))
        #expect(notify(post(message: "hey @alice"), mentioned: true, unknown: true))
        #expect(notify(post(), mentioned: true, unknown: false))
    }

    @Test func taggingHonorsMentionKeysAndDnd() {
        let keyed = User(id: "me", username: "alice", notifyProps: ["desktop": "mention", "mention_keys": "deploybot"])
        #expect(notify(post(message: "deploybot is down"), me: keyed, unknown: true))
        #expect(!notify(post(message: "@alicex hi"), unknown: true))
        #expect(!NotificationPolicy.shouldNotify(
            post: post(message: "@alice"), channelType: .open, mentioned: true, me: me, member: nil, myStatus: .dnd, isViewingChannel: false
        ))
    }

    @Test func desktopLevelMatrix() {
        #expect(notify(post(), member: member(["desktop": "all"])))
        #expect(!notify(post(), member: member(["desktop": "mention"])))
        #expect(notify(post(), mentioned: true, member: member(["desktop": "mention"])))
        #expect(!notify(post(), mentioned: true, member: member(["desktop": "none"])))
        #expect(!notify(post(), type: .direct, member: member(["desktop": "none"])))
        #expect(notify(post(), type: .group, member: member(["desktop": "mention"])))
        let loudUser = User(id: "me", username: "alice", notifyProps: ["desktop": "all"])
        #expect(notify(post(), me: loudUser, member: member(["desktop": "default"])))
        #expect(!notify(post(), me: loudUser, member: member(["desktop": "mention"])))
    }

    @Test func ignoringChannelMentionsDropsChannelWideOnlyMentions() {
        let ignoring = member(["ignore_channel_mentions": "on"])
        #expect(!notify(post(message: "@channel ship it"), mentioned: true, member: ignoring, channelWide: true))
        #expect(notify(post(message: "@channel and @alice"), mentioned: true, member: ignoring, channelWide: false))
        #expect(notify(post(message: "@channel ship it"), mentioned: true, member: member(["ignore_channel_mentions": "off"]), channelWide: true))
        #expect(notify(post(message: "@channel ship it"), mentioned: true, channelWide: true))
        #expect(notify(post(message: "@channel ship it"), member: member(["desktop": "all", "ignore_channel_mentions": "on"]), channelWide: true))
    }

    @Test func mutedChannelsIgnoreChannelMentionsByDefault() {
        #expect(!notify(post(message: "@here"), mentioned: true, member: member(["mark_unread": "mention"]), channelWide: true))
        let userIgnoring = User(id: "me", username: "alice", notifyProps: ["desktop": "mention", "channel": "false"])
        #expect(!notify(post(message: "@here"), mentioned: true, me: userIgnoring, channelWide: true))
    }

    @Test func threadRepliesFollowThreadSettings() {
        let reply = post(rootId: "root")
        #expect(notify(reply, member: member(["desktop": "mention"]), threadReply: true))
        #expect(!notify(reply, member: member(["desktop": "mention", "desktop_threads": "mention"]), threadReply: true))
        #expect(notify(reply, mentioned: true, member: member(["desktop": "mention", "desktop_threads": "mention"]), threadReply: true))
        #expect(notify(reply, member: member(["desktop": "all", "desktop_threads": "mention"]), threadReply: true))
        #expect(!notify(reply, mentioned: true, member: member(["desktop": "none"]), threadReply: true))
        #expect(!notify(reply, mentioned: true, threadReply: true, following: false))
        let quietThreads = User(id: "me", username: "alice", notifyProps: ["desktop": "mention", "desktop_threads": "mention"])
        #expect(!notify(reply, me: quietThreads, member: member(["desktop": "mention"]), threadReply: true))
    }
}

@Suite struct TeamMuteLayoutTests {
    let teams = [Team(id: "a", name: "a", displayName: "A"), Team(id: "b", name: "b", displayName: "B")]

    @Test func muteTogglesOnlyKnownTeams() {
        var layout = TeamLayout()
        #expect(!layout.isMuted("a"))
        layout.setMuted("a", true, in: teams)
        #expect(layout.isMuted("a"))
        #expect(layout.muted == ["a"])
        layout.setMuted("a", true, in: teams)
        #expect(layout.muted == ["a"])
        layout.setMuted("gone", true, in: teams)
        #expect(layout.muted == ["a"])
        layout.setMuted("a", false, in: teams)
        #expect(layout.muted.isEmpty)
        #expect(!layout.isMuted("a"))
    }

    @Test func muteSurvivesReorderingAndFavorites() {
        var layout = TeamLayout()
        layout.setMuted("b", true, in: teams)
        layout.move("b", to: "a", in: teams)
        layout.setFavorite("b", true, in: teams)
        layout.moveToEnd("b", favorite: false, in: teams)
        #expect(layout.isMuted("b"))
        #expect(!layout.isMuted("a"))
    }

    @Test func mutedTeamsCountTowardsEmptiness() {
        var layout = TeamLayout()
        #expect(layout.isEmpty)
        layout.setMuted("a", true, in: teams)
        #expect(!layout.isEmpty)
    }

    @Test func legacyLayoutsDecodeWithoutMutedTeams() throws {
        let legacy = try JSONDecoder().decode(TeamLayout.self, from: Data(#"{"order":["b","a"],"favorites":["a"]}"#.utf8))
        #expect(legacy == TeamLayout(order: ["b", "a"], favorites: ["a"]))
        #expect(legacy.muted.isEmpty)
        let layout = TeamLayout(order: ["b", "a"], favorites: ["a"], muted: ["b"])
        let roundTrip = try JSONDecoder().decode(TeamLayout.self, from: JSONEncoder().encode(layout))
        #expect(roundTrip == layout)
    }

    @Test func serverConfigPersistsMutedTeams() throws {
        var config = ServerConfig(name: "Chat", url: URL(string: "https://chat.example.com")!)
        config.teamLayout.setMuted("a", true, in: teams)
        let roundTrip = try MattermostJSON.decoder.decode(ServerConfig.self, from: MattermostJSON.encoder.encode(config))
        #expect(roundTrip.teamLayout.muted == ["a"])
    }
}

@MainActor
@Suite struct ChannelNotifyPropsSessionTests {
    static let townProps = "channels/c-town/members/me1/notify_props"

    func server() -> MockServer {
        let server = MockServer()
        server.transport.on("PUT", Self.townProps, .ok)
        server.transport.on("PUT", "channels/c-dev/members/me1/notify_props", .ok)
        return server
    }

    @Test func endpointSendsOnlyChangedProps() async throws {
        let transport = FakeTransport()
        transport.on("PUT", Self.townProps, .ok)
        let client = APIClient(baseURL: MockServer.baseURL, token: "t", transport: transport)
        try await client.updateChannelNotifyProps(channelId: "c-town", userId: "me1", props: ["mark_unread": "mention"])
        let request = try #require(transport.last("PUT", Self.townProps))
        #expect(request.url?.path == "/api/v4/channels/c-town/members/me1/notify_props")
        #expect(request.jsonObject as? [String: String] == ["mark_unread": "mention"])
    }

    @Test func mutingUpdatesMemberOptimistically() async throws {
        let server = server()
        let session = await server.startedSession()
        #expect(!session.isMuted(channelId: "c-town"))
        #expect(await session.setMuted(channelId: "c-town", true))
        #expect(session.isMuted(channelId: "c-town"))
        #expect(session.notifySettings(channelId: "c-town").muted)
        #expect(session.unread(channelId: "c-town").unread == false)
        let body = try #require(server.transport.last("PUT", Self.townProps)?.jsonObject as? [String: String])
        #expect(body == ["mark_unread": "mention"])
        #expect(await session.toggleMuted(channelId: "c-town"))
        #expect(!session.isMuted(channelId: "c-town"))
        #expect(server.transport.count("PUT", Self.townProps) == 2)
        session.stop()
    }

    @Test func repeatedMuteCallsSkipTheServer() async {
        let server = server()
        let session = await server.startedSession()
        #expect(await session.setMuted(channelId: "c-town", false))
        #expect(server.transport.count("PUT", Self.townProps) == 0)
        #expect(!(await session.setMuted(channelId: "missing", true)))
        session.stop()
    }

    @Test func failedUpdateRollsBackAndReports() async {
        let server = server()
        server.transport.on("PUT", Self.townProps, .error(500, message: "nope"))
        let session = await server.startedSession()
        let before = session.members["c-town"]?.notifyProps
        #expect(!(await session.setMuted(channelId: "c-town", true)))
        #expect(session.members["c-town"]?.notifyProps == before)
        #expect(!session.isMuted(channelId: "c-town"))
        #expect(session.lastError == "nope")
        session.stop()
    }

    @Test func rollbackIsSkippedWhenPropsChangedMeanwhile() async {
        let server = server()
        let gate = Gate()
        server.hold("PUT", Self.townProps, gate: gate) { _ in .error(500) }
        let session = await server.startedSession()
        let task = Task { await session.setMuted(channelId: "c-town", true) }
        #expect(await eventually { server.transport.count("PUT", Self.townProps) == 1 })
        session.members["c-town"]?.notifyProps["desktop"] = "all"
        await gate.open()
        _ = await task.value
        #expect(session.members["c-town"]?.notifyProps["desktop"] == "all")
        #expect(session.members["c-town"]?.notifyProps["mark_unread"] == "mention")
        session.stop()
    }

    @Test func applyingSettingsSendsTheWholePatch() async throws {
        let server = server()
        let session = await server.startedSession()
        var settings = session.notifySettings(channelId: "c-town")
        settings.desktop = .all
        settings.desktopThreads = .mention
        settings.ignoreChannelMentions = .on
        #expect(await session.applyNotifySettings(settings, channelId: "c-town"))
        let body = try #require(server.transport.last("PUT", Self.townProps)?.jsonObject as? [String: String])
        #expect(body == ["desktop": "all", "desktop_threads": "mention", "ignore_channel_mentions": "on"])
        #expect(session.notifySettings(channelId: "c-town") == settings)
        #expect(await session.applyNotifySettings(settings, channelId: "c-town"))
        #expect(server.transport.count("PUT", Self.townProps) == 1)
        session.stop()
    }

    @Test func memberUpdatedEventSyncsOtherClients() async {
        let session = await server().startedSession()
        var member = Fixtures.member("c-town", user: "me1", msgCount: 5, lastViewedAt: 500, markUnread: "mention", desktop: "none")
        session.apply(Fixtures.wsEvent("channel_member_updated", data: ["channelMember": Fixtures.json(member)], user: "me1"))
        #expect(session.isMuted(channelId: "c-town"))
        #expect(session.notifySettings(channelId: "c-town").desktop == .none)
        member["user_id"] = "u2"
        session.apply(Fixtures.wsEvent("channel_member_updated", data: ["channelMember": Fixtures.json(member)], user: "u2"))
        #expect(session.isMuted(channelId: "c-town"))
        session.apply(Fixtures.wsEvent("channel_member_updated", data: ["channelMember": "{broken"], user: "me1"))
        #expect(session.isMuted(channelId: "c-town"))
        session.stop()
    }

    @Test func mutedTeamsOnlyBadgeTagsButStillNotifyDirectMessages() async {
        let session = await server().startedSession()
        let box = NotificationBox()
        session.onNotification = { box.items.append($0) }
        session.isAppActive = { false }
        session.setMuted(teamId: "t1", true)
        #expect(session.isMuted(teamId: "t1"))
        session.apply(Fixtures.posted(Fixtures.post("n0", channel: "c-dev", user: "u2", message: "@channel standup", createAt: 900), mentions: ["me1"]))
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-dev", user: "u2", message: "hey @alice", createAt: 1000), mentions: ["me1"]))
        #expect(box.items.isEmpty)
        #expect(await eventually { session.unread(channelId: "c-dev").mentions == 1 })
        #expect(session.teamUnread(teamId: "t1").mentions == 1)
        session.apply(Fixtures.posted(Fixtures.post("n2", channel: "c-dm", user: "u2", message: "ping", createAt: 1100), channelType: "D", team: ""))
        #expect(box.items.map(\.postId) == ["n2"])
        session.setMuted(teamId: "t1", false)
        session.apply(Fixtures.posted(Fixtures.post("n3", channel: "c-dev", user: "u2", message: "@channel lunch", createAt: 1200), mentions: ["me1"]))
        #expect(box.items.map(\.postId) == ["n2", "n3"])
        session.stop()
    }

    @Test func mutedChannelOnlyBadgesTagsEndToEnd() async {
        let session = await server().startedSession()
        let box = NotificationBox()
        session.onNotification = { box.items.append($0) }
        session.isAppActive = { false }
        session.members["c-dev"]?.notifyProps = ["mark_unread": "mention", "desktop": "all"]
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-dev", user: "u2", message: "release is out", createAt: 1000)))
        session.apply(Fixtures.posted(Fixtures.post("n2", channel: "c-dev", user: "u2", message: "@here standup", createAt: 1100), mentions: ["me1"]))
        #expect(session.unread(channelId: "c-dev").mentions == 0)
        session.apply(Fixtures.posted(Fixtures.post("n3", channel: "c-dev", user: "u2", message: "@alice please review", createAt: 1200), mentions: ["me1"]))
        #expect(box.items.isEmpty)
        #expect(session.unread(channelId: "c-dev") == ChannelUnread(unread: false, mentions: 1))
        #expect(session.totalUnread.mentions >= 1)
        session.stop()
    }

    @Test func unknownMembershipIsResolvedBeforeNotifying() async {
        let server = server()
        server.transport.on("GET", "channels/c-beta", object: Fixtures.channel("c-beta", team: "t2", name: "town-square", display: "Beta Square", total: 4, lastPostAt: 400))
        server.transport.on("GET", "channels/c-beta/members/me", object: Fixtures.member("c-beta", user: "me1", msgCount: 0, mentions: 0, markUnread: "mention"))
        let session = await server.startedSession()
        let box = NotificationBox()
        session.onNotification = { box.items.append($0) }
        session.isAppActive = { false }
        session.members["c-beta"] = nil
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-beta", user: "u2", message: "@alice deploy", createAt: 1000), team: "t2", mentions: ["me1"]))
        #expect(await eventually { session.members["c-beta"] != nil })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(box.items.isEmpty)
        server.transport.on("GET", "channels/c-beta/members/me", object: Fixtures.member("c-beta", user: "me1", msgCount: 0, mentions: 0))
        session.members["c-beta"] = nil
        session.apply(Fixtures.posted(Fixtures.post("n2", channel: "c-beta", user: "u2", message: "@channel deploy", createAt: 1100), team: "t2", mentions: ["me1"]))
        #expect(await eventually { box.items.map(\.postId) == ["n2"] })
        session.stop()
    }

    @Test func unresolvedMembershipNotifiesOnlyWhenTagged() async {
        let server = server()
        server.transport.on("GET", "channels/c-ghost", .error(500))
        let session = await server.startedSession()
        let box = NotificationBox()
        session.onNotification = { box.items.append($0) }
        session.isAppActive = { false }
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-ghost", user: "u2", message: "@channel deploy", createAt: 1000), mentions: ["me1"]))
        session.apply(Fixtures.posted(Fixtures.post("n2", channel: "c-ghost", user: "u2", message: "@alice deploy", createAt: 1100), mentions: ["me1"]))
        #expect(await eventually { box.items.map(\.postId) == ["n2"] })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(box.items.count == 1)
        session.stop()
    }

    @Test func mutedTeamsPersistThroughTheSessionCallback() async {
        let session = await server().startedSession()
        var reported: [TeamLayout] = []
        session.onTeamLayoutChange = { reported.append($0) }
        session.toggleMuted(teamId: "t1")
        session.toggleMuted(teamId: "t1")
        #expect(reported.map(\.muted) == [["t1"], []])
        session.stop()
    }

    @Test func channelWideMentionsAreIgnoredEndToEnd() async {
        let session = await server().startedSession()
        let box = NotificationBox()
        session.onNotification = { box.items.append($0) }
        session.isAppActive = { false }
        session.members["c-dev"]?.notifyProps["ignore_channel_mentions"] = "on"
        session.apply(Fixtures.posted(Fixtures.post("n1", channel: "c-dev", user: "u2", message: "@channel standup", createAt: 1000), mentions: ["me1"]))
        #expect(box.items.isEmpty)
        session.apply(Fixtures.posted(Fixtures.post("n2", channel: "c-dev", user: "u2", message: "@channel and @alice", createAt: 1100), mentions: ["me1"]))
        #expect(box.items.count == 1)
        session.stop()
    }

    @Test func threadRepliesNotifyOnlyForFollowedThreads() async {
        let server = server()
        let root = Fixtures.post("root", channel: "c-dev", user: "u3", message: "root", createAt: 900, replyCount: 1)
        server.setPosts("c-dev", [root])
        let session = await server.startedSession()
        session.collapsedThreads = true
        await session.selectChannel("c-dev")
        let box = NotificationBox()
        session.onNotification = { box.items.append($0) }
        session.isAppActive = { false }
        session.posts["root"]?.isFollowing = false
        session.apply(Fixtures.posted(Fixtures.post("r1", channel: "c-dev", user: "u2", message: "reply", createAt: 1000, rootId: "root")))
        #expect(box.items.isEmpty)
        session.posts["root"]?.isFollowing = true
        session.apply(Fixtures.posted(Fixtures.post("r2", channel: "c-dev", user: "u2", message: "reply", createAt: 1100, rootId: "root")))
        #expect(box.items.count == 1)
        session.stop()
    }

    @Test func repliesToUnknownThreadsStillNotify() async {
        let session = await server().startedSession()
        session.collapsedThreads = true
        let box = NotificationBox()
        session.onNotification = { box.items.append($0) }
        session.isAppActive = { false }
        #expect(session.followsThread(of: Post(id: "x", userId: "u2", channelId: "c-dev", rootId: "ghost", message: "hi")))
        session.apply(Fixtures.posted(Fixtures.post("r1", channel: "c-dev", user: "u2", message: "hey @alice", createAt: 1000, rootId: "ghost"), mentions: ["me1"]))
        #expect(box.items.count == 1)
        session.stop()
    }
}
