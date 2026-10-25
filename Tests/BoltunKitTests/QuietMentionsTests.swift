import Foundation
import Testing
@testable import BoltunKit

@MainActor
@Suite struct QuietMentionsTests {
    func server(mutedChannels: Set<String> = [], devMentions: Int = 2) -> MockServer {
        let server = MockServer()
        func markUnread(_ id: String) -> String { mutedChannels.contains(id) ? "mention" : "all" }
        server.transport.on("GET", "users/me/teams/t1/channels/members", object: [
            Fixtures.member("c-town", user: "me1", msgCount: 5, lastViewedAt: 500, markUnread: markUnread("c-town")),
            Fixtures.member("c-dev", user: "me1", msgCount: 1, mentions: devMentions, lastViewedAt: 100, markUnread: markUnread("c-dev")),
            Fixtures.member("c-dm", user: "me1", msgCount: 2, lastViewedAt: 900, markUnread: markUnread("c-dm")),
            Fixtures.member("c-gm", user: "me1", msgCount: 1, lastViewedAt: 800, markUnread: markUnread("c-gm")),
        ])
        server.setPosts("c-dev", [
            Fixtures.post("old", channel: "c-dev", user: "u2", message: "@alice before you looked", createAt: 50),
            Fixtures.post("wide", channel: "c-dev", user: "u2", message: "@channel deploy at 5", createAt: 150),
            Fixtures.post("direct", channel: "c-dev", user: "u2", message: "@alice can you check?", createAt: 160),
        ])
        return server
    }

    func post(_ id: String, channel: String = "c-dev", message: String, at: Int64 = 1000) -> [String: Any] {
        Fixtures.post(id, channel: channel, user: "u2", message: message, createAt: at)
    }

    @Test func mutedChannelCountsOnlyPersonalMentions() async {
        let server = server(mutedChannels: ["c-dev"])
        let session = await server.startedSession()
        #expect(await eventually { session.quietMentions["c-dev"] == 1 })
        #expect(session.isQuiet(channelId: "c-dev"))
        #expect(session.unread(channelId: "c-dev") == ChannelUnread(unread: false, mentions: 1))
        #expect(session.teamUnread(teamId: "t1") == ChannelUnread(unread: false, mentions: 1))
        session.apply(Fixtures.posted(post("n1", message: "@here standup"), mentions: ["me1"]))
        #expect(session.members["c-dev"]?.mentionCount == 3)
        #expect(session.unread(channelId: "c-dev").mentions == 1)
        session.apply(Fixtures.posted(post("n2", message: "thanks @alice!"), mentions: ["me1"]))
        #expect(session.unread(channelId: "c-dev").mentions == 2)
        session.apply(Fixtures.wsEvent("channel_viewed", data: ["channel_id": "c-dev"], user: "me1"))
        #expect(session.quietMentions["c-dev"] == nil)
        #expect(session.unread(channelId: "c-dev") == .none)
        session.stop()
    }

    @Test func mutedTeamHidesUnreadAndChannelWideMentions() async {
        let server = server(devMentions: 1)
        server.setPosts("c-dev", [Fixtures.post("wide", channel: "c-dev", user: "u2", message: "@all release is out", createAt: 150)])
        let session = await server.startedSession()
        #expect(session.teamUnread(teamId: "t1") == ChannelUnread(unread: true, mentions: 1))
        session.setMuted(teamId: "t1", true)
        #expect(await eventually { session.quietMentions["c-dev"] == 0 })
        #expect(session.teamUnread(teamId: "t1") == ChannelUnread(unread: false, mentions: 0))
        #expect(!session.isQuiet(channelId: "c-dm"))
        session.apply(Fixtures.posted(post("n1", message: "@alice please review"), mentions: ["me1"]))
        #expect(session.teamUnread(teamId: "t1") == ChannelUnread(unread: false, mentions: 1))
        session.apply(Fixtures.posted(post("n2", message: "@channel lunch"), mentions: ["me1"]))
        #expect(session.teamUnread(teamId: "t1").mentions == 1)
        session.setMuted(teamId: "t1", false)
        #expect(session.teamUnread(teamId: "t1") == ChannelUnread(unread: true, mentions: 3))
        session.stop()
    }

    @Test func mutedUnloadedTeamIsSilentUntilLoadedForPersonalMentions() async {
        let server = server()
        server.setPosts("c-beta", [
            Fixtures.post("b1", channel: "c-beta", user: "u2", message: "@alice the build is yours", createAt: 10),
            Fixtures.post("b2", channel: "c-beta", user: "u2", message: "@all heads up", createAt: 20),
        ])
        let session = await server.startedSession()
        #expect(session.teamUnread(teamId: "t2") == ChannelUnread(unread: true, mentions: 2))
        let directMentions = session.directUnread.mentions
        session.teamLayout.setMuted("t2", true, in: session.teams)
        #expect(session.teamUnread(teamId: "t2") == .none)
        #expect(session.totalUnread.mentions == session.teamUnread(teamId: "t1").mentions + directMentions)
        session.teamLayout.setMuted("t2", false, in: session.teams)
        session.setMuted(teamId: "t2", true)
        #expect(await eventually { session.quietMentions["c-beta"] == 1 })
        #expect(server.transport.count("GET", "users/me/teams/t2/channels") == 1)
        #expect(session.teamUnread(teamId: "t2") == ChannelUnread(unread: false, mentions: 1))
        session.setMuted(teamId: "t2", true)
        #expect(server.transport.count("GET", "users/me/teams/t2/channels") == 1)
        session.stop()
    }

    @Test func personalMentionInUnloadedMutedTeamLoadsIt() async {
        let server = server()
        server.transport.on("GET", "users/me/teams/unread", object: [
            ["team_id": "t1", "msg_count": 0, "mention_count": 0, "msg_count_root": 0, "mention_count_root": 0, "thread_count": 0, "thread_mention_count": 0],
            ["team_id": "t2", "msg_count": 0, "mention_count": 0, "msg_count_root": 0, "mention_count_root": 0, "thread_count": 0, "thread_mention_count": 0],
        ])
        let session = await server.startedSession()
        session.setMuted(teamId: "t2", true)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(server.transport.count("GET", "users/me/teams/t2/channels") == 0)
        session.apply(Fixtures.posted(post("n1", channel: "c-beta", message: "@channel hi"), team: "t2", mentions: ["me1"]))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(server.transport.count("GET", "users/me/teams/t2/channels") == 0)
        server.setPosts("c-beta", [post("n2", channel: "c-beta", message: "@alice ping", at: 1001)])
        session.apply(Fixtures.posted(post("n2", channel: "c-beta", message: "@alice ping", at: 1001), team: "t2", mentions: ["me1"]))
        #expect(await eventually { server.transport.count("GET", "users/me/teams/t2/channels") == 1 })
        #expect(await eventually { session.quietMentions["c-beta"] == 1 })
        #expect(session.teamUnread(teamId: "t2") == ChannelUnread(unread: false, mentions: 1))
        session.stop()
    }

    @Test func preloadedTeamsBadgeMutedChannelsOnlyForPersonalMentions() async {
        let server = server()
        server.transport.on("GET", "users/me/teams/t2/channels/members", object: [
            Fixtures.member("c-beta", user: "me1", msgCount: 0, mentions: 2, lastViewedAt: 5, markUnread: "mention"),
        ])
        server.setPosts("c-beta", [
            Fixtures.post("b1", channel: "c-beta", user: "u2", message: "@alice the build is yours", createAt: 10),
            Fixtures.post("b2", channel: "c-beta", user: "u2", message: "@all heads up", createAt: 20),
        ])
        let session = await server.startedSession(preloadsTeams: true)
        #expect(await eventually { session.quietMentions["c-beta"] == 1 })
        #expect(session.teamUnread(teamId: "t2") == ChannelUnread(unread: false, mentions: 1))
        #expect(server.transport.count("GET", "users/me/teams/t2/channels") == 1)
        #expect(server.transport.count("GET", "users/me/teams/t1/channels") == 1)
        session.apply(Fixtures.posted(post("n1", channel: "c-beta", message: "@here standup"), team: "t2", mentions: ["me1"]))
        #expect(session.teamUnread(teamId: "t2").mentions == 1)
        session.apply(Fixtures.posted(post("n2", channel: "c-beta", message: "@alice ping", at: 1001), team: "t2", mentions: ["me1"]))
        #expect(session.teamUnread(teamId: "t2").mentions == 2)
        session.stop()
    }

    @Test func failedPreloadFallsBackToServerCountsWithoutRetrying() async {
        let server = server()
        server.transport.on("GET", "users/me/teams/t2/channels", .error(500))
        let session = await server.startedSession(preloadsTeams: true)
        #expect(await eventually { server.transport.count("GET", "users/me/teams/t2/channels") == 1 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(server.transport.count("GET", "users/me/teams/t2/channels") == 1)
        #expect(session.teamUnread(teamId: "t2") == ChannelUnread(unread: true, mentions: 2))
        #expect(session.lastError == nil)
        session.stop()
    }

    @Test func newTeamsArePreloaded() async {
        let server = server()
        server.transport.on("GET", "users/me/teams", object: [Fixtures.team("t1", "alpha", display: "Alpha")])
        let session = await server.startedSession(preloadsTeams: true)
        #expect(server.transport.count("GET", "users/me/teams/t2/channels") == 0)
        server.transport.on("GET", "users/me/teams", object: [Fixtures.team("t1", "alpha", display: "Alpha"), Fixtures.team("t2", "beta", display: "beta")])
        session.apply(Fixtures.wsEvent("added_to_team", data: ["team_id": "t2", "user_id": "me1"], user: "me1"))
        #expect(await eventually { server.transport.count("GET", "users/me/teams/t2/channels") == 1 })
        #expect(await eventually { session.members["c-beta"] != nil })
        session.stop()
    }

    @Test func mutedDirectMessageCountsOnlyWhenTagged() async {
        let server = server(mutedChannels: ["c-dm"])
        let session = await server.startedSession()
        let dm = post("d1", channel: "c-dm", message: "hi there")
        session.apply(Fixtures.posted(dm, channelType: "D", team: ""))
        #expect(session.members["c-dm"]?.mentionCount == 1)
        #expect(session.unread(channelId: "c-dm") == ChannelUnread(unread: false, mentions: 0))
        session.apply(Fixtures.posted(post("d2", channel: "c-dm", message: "@alice look", at: 1001), channelType: "D", team: ""))
        #expect(session.unread(channelId: "c-dm") == ChannelUnread(unread: false, mentions: 1))
        #expect(session.directUnread == ChannelUnread(unread: false, mentions: 1))
        session.stop()
    }

    @Test func mutingAndUnreadEventsRecount() async {
        let server = server()
        server.transport.on("PUT", "channels/c-dev/members/me1/notify_props", .ok)
        let session = await server.startedSession()
        #expect(session.unread(channelId: "c-dev") == ChannelUnread(unread: true, mentions: 2))
        #expect(await session.setMuted(channelId: "c-dev", true))
        #expect(await eventually { session.quietMentions["c-dev"] == 1 })
        session.apply(Fixtures.wsEvent("post_unread", data: ["msg_count": 0, "mention_count": 2, "last_viewed_at": 155], channel: "c-dev"))
        #expect(await eventually { session.quietMentions["c-dev"] == 1 })
        session.apply(Fixtures.wsEvent("post_unread", data: ["mention_count": 1, "last_viewed_at": 170], channel: "c-dev"))
        #expect(await eventually { session.quietMentions["c-dev"] == 0 })
        let member = Fixtures.member("c-dev", user: "me1", msgCount: 1, mentions: 1, lastViewedAt: 170, markUnread: "all")
        session.apply(Fixtures.wsEvent("channel_member_updated", data: ["channelMember": Fixtures.json(member)], channel: "c-dev"))
        #expect(!session.isQuiet(channelId: "c-dev"))
        #expect(session.unread(channelId: "c-dev").mentions == 1)
        session.stop()
    }

    @Test func personalMentionIgnoresOwnSystemAndDeletedPosts() async {
        let session = await server().startedSession()
        func make(user: String = "u2", type: String = "", deleteAt: Int64 = 0) -> Post {
            Post(id: "x", createAt: 1, deleteAt: deleteAt, userId: user, channelId: "c-dev", message: "@alice", type: type)
        }
        #expect(session.isPersonalMention(make()))
        #expect(!session.isPersonalMention(make(user: "me1")))
        #expect(!session.isPersonalMention(make(type: "system_join_channel")))
        #expect(!session.isPersonalMention(make(deleteAt: 5)))
        #expect(!session.isQuiet(channelId: "unknown"))
        session.stop()
    }
}
