import Foundation
import Testing
@testable import BoltunKit

@MainActor
@Suite struct OpenChannelReadTests {
    static func mention(_ id: String, at createAt: Int64) -> WebSocketEvent {
        Fixtures.posted(Fixtures.post(id, channel: "c-dev", user: "u2", message: "hey @alice", createAt: createAt), mentions: ["me1"])
    }

    @Test func mentionsInTheOpenChannelClearOnceTheUserIsBack() async {
        let server = MockServer()
        let session = await server.startedSession()
        await session.selectChannel("c-dev")
        session.isAppActive = { false }
        session.apply(Self.mention("m1", at: 1000))
        #expect(session.unread(channelId: "c-dev") == ChannelUnread(unread: true, mentions: 1))
        let viewed = server.viewedChannels.count
        session.isAppActive = { true }
        await session.markCurrentChannelViewedIfUnread()
        #expect(session.unread(channelId: "c-dev") == .none)
        #expect(server.viewedChannels.count == viewed + 1)
        #expect(server.viewedChannels.last == "c-dev")
        await session.markCurrentChannelViewedIfUnread()
        #expect(server.viewedChannels.count == viewed + 1)
        session.stop()
    }

    @Test func readOrManuallyUnreadChannelsAreLeftAlone() async {
        let server = MockServer()
        let session = server.session()
        await session.markCurrentChannelViewedIfUnread()
        #expect(server.viewedChannels.isEmpty)
        await session.start()
        await session.selectTeam("t1")
        let viewed = server.viewedChannels.count
        await session.markCurrentChannelViewedIfUnread()
        #expect(server.viewedChannels.count == viewed)
        session.manuallyUnread.insert("c-town")
        session.members["c-town"]?.mentionCount = 1
        await session.markCurrentChannelViewedIfUnread()
        #expect(server.viewedChannels.count == viewed)
        #expect(session.unread(channelId: "c-town").mentions == 1)
        session.stop()
    }

    @Test func unreadStateCoversCountsMentionsAndQuietMentions() async {
        let server = MockServer()
        let session = await server.startedSession()
        #expect(!session.hasUnreadState(channelId: "c-town"))
        #expect(!session.hasUnreadState(channelId: "c-missing"))
        session.members["c-town"]?.urgentMentionCount = 1
        #expect(session.hasUnreadState(channelId: "c-town"))
        session.members["c-town"]?.urgentMentionCount = 0
        session.quietMentions["c-town"] = 0
        #expect(session.hasUnreadState(channelId: "c-town"))
        session.quietMentions["c-town"] = nil
        session.members["c-town"]?.msgCountRoot = -1
        #expect(session.hasUnreadState(channelId: "c-town"))
        session.members["c-town"]?.msgCountRoot = session.channels["c-town"]?.totalMsgCountRoot ?? 0
        session.members["c-town"]?.msgCount = 4
        #expect(session.hasUnreadState(channelId: "c-town"))
        session.stop()
    }

    @Test func appActivationAndServerSwitchClearTheOpenChannel() async {
        let harness = AppHarness()
        let app = harness.model()
        var active = false
        app.isAppActive = { active }
        let session = app.makeSession(for: app.servers[0])
        await session.start()
        await session.selectTeam("t1")
        await session.selectChannel("c-dev")
        session.apply(Self.mention("m1", at: 1000))
        #expect(app.totalMentions >= 1)
        #expect(session.unread(channelId: "c-dev").mentions == 1)
        await app.markSelectedChannelViewed()
        #expect(session.unread(channelId: "c-dev").mentions == 1)
        active = true
        await app.markSelectedChannelViewed()
        #expect(session.unread(channelId: "c-dev") == .none)
        await app.select(serverId: app.servers[1].id)
        session.apply(Self.mention("m2", at: 1100))
        #expect(session.unread(channelId: "c-dev").mentions == 1)
        await app.select(serverId: app.servers[0].id)
        #expect(session.unread(channelId: "c-dev") == .none)
        session.stop()
    }
}
