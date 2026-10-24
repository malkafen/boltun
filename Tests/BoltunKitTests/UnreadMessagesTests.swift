import Foundation
import Testing
@testable import BoltunKit

@Suite struct NewMessagesMarkerTests {
    func post(_ id: String, at createAt: Int64, user: String = "u2", rootId: String = "", deleteAt: Int64 = 0, props: JSONObject = [:]) -> Post {
        Post(id: id, createAt: createAt, deleteAt: deleteAt, userId: user, channelId: "c", rootId: rootId, message: id, props: props)
    }

    @Test func startsOnlyAfterLastViewedForOthers() {
        #expect(NewMessagesMarker.starts(at: post("a", at: 200), lastViewedAt: 100, myId: "me"))
        #expect(!NewMessagesMarker.starts(at: post("a", at: 100), lastViewedAt: 100, myId: "me"))
        #expect(!NewMessagesMarker.starts(at: post("a", at: 200), lastViewedAt: 0, myId: "me"))
        #expect(!NewMessagesMarker.starts(at: post("a", at: 200, user: "me"), lastViewedAt: 100, myId: "me"))
    }

    @Test func webhookPostsFromMeCount() {
        let webhook = post("a", at: 200, user: "me", props: ["from_webhook": .string("true")])
        #expect(webhook.isFromWebhook)
        #expect(NewMessagesMarker.starts(at: webhook, lastViewedAt: 100, myId: "me"))
    }

    @Test func silentNotificationsAreSkippedUnlessForced() {
        let silent = post("a", at: 200, props: ["silent_notification": .bool(true)])
        let forced = post("b", at: 200, props: ["silent_notification": .bool(true), "force_notification": .bool(true)])
        #expect(silent.isSilentNotification)
        #expect(!forced.isSilentNotification)
        #expect(!NewMessagesMarker.starts(at: silent, lastViewedAt: 100, myId: "me"))
        #expect(NewMessagesMarker.starts(at: forced, lastViewedAt: 100, myId: "me"))
    }

    @Test func firstIndexAndCount() {
        let posts = [
            post("old", at: 50),
            post("mine", at: 150, user: "me"),
            post("first", at: 200),
            post("reply", at: 210, rootId: "old"),
            post("gone", at: 220, deleteAt: 230),
            post("last", at: 300),
        ]
        #expect(NewMessagesMarker.firstIndex(in: posts, lastViewedAt: 100, myId: "me") == 2)
        #expect(NewMessagesMarker.unreadCount(posts: posts, lastViewedAt: 100, myId: "me", collapsedThreads: false) == 4)
        #expect(NewMessagesMarker.unreadCount(posts: posts, lastViewedAt: 100, myId: "me", collapsedThreads: true) == 2)
        #expect(NewMessagesMarker.unreadCount(posts: posts, lastViewedAt: 400, myId: "me", collapsedThreads: false) == 0)
        #expect(NewMessagesMarker.unreadCount(posts: [], lastViewedAt: 100, myId: "me", collapsedThreads: false) == 0)
    }
}

@MainActor
@Suite struct UnreadSessionTests {
    func unreadServer(count: Int = 12, lastViewedAt: Int64 = 250, msgCount: Int = 2) -> MockServer {
        let server = MockServer()
        server.setPosts("c-town", (1...count).map { index in
            Fixtures.post("q\(index)", channel: "c-town", user: "u2", message: "message \(index)", createAt: Int64(index * 100))
        })
        server.transport.on("GET", "users/me/teams/t1/channels", object: [
            Fixtures.channel("c-town", team: "t1", name: "town-square", display: "Town Square", total: count, totalRoot: count - 1, lastPostAt: Int64(count * 100)),
            Fixtures.channel("c-dev", team: "t1", name: "dev", display: "Development", total: 3, lastPostAt: 300),
        ])
        server.transport.on("GET", "users/me/teams/t1/channels/members", object: [
            Fixtures.member("c-town", user: "me1", msgCount: msgCount, lastViewedAt: lastViewedAt),
            Fixtures.member("c-dev", user: "me1", msgCount: 1, lastViewedAt: 100),
        ])
        return server
    }

    @Test func openingLoadsOlderPagesUntilFirstUnreadIsIncluded() async throws {
        let server = unreadServer()
        let session = await server.startedSession()
        let timeline = try #require(session.timelines["c-town"])
        #expect(timeline.lastViewedAtOnOpen == 250)
        #expect(timeline.unreadCountOnOpen == 10)
        #expect(session.timelinePosts(channelId: "c-town").first?.id == "q1")
        #expect(server.viewedChannels == ["c-town"])
        #expect(!session.needsOlderPostsForUnread(channelId: "c-town"))
        session.stop()
    }

    @Test func unreadPageLoadingIsCapped() async {
        let server = unreadServer(count: 30)
        let session = server.session()
        session.unreadPageLimit = 2
        await session.start()
        await session.selectTeam("t1")
        #expect(session.timelinePosts(channelId: "c-town").count == 9)
        #expect(session.needsOlderPostsForUnread(channelId: "c-town"))
        session.stop()
    }

    @Test func fullyReadChannelLoadsOnlyTheLatestPage() async {
        let server = MockServer()
        let session = await server.startedSession()
        #expect(session.timelinePosts(channelId: "c-town").count == 3)
        #expect(session.timelines["c-town"]?.unreadCountOnOpen == 0)
        #expect(!session.needsOlderPostsForUnread(channelId: "c-town"))
        session.stop()
    }

    @Test func neverViewedChannelDoesNotLoadHistory() async {
        let server = unreadServer(lastViewedAt: 0)
        let session = await server.startedSession()
        #expect(session.timelinePosts(channelId: "c-town").count == 3)
        session.stop()
    }

    @Test func unreadMessageCountFollowsCollapsedThreads() async {
        let server = unreadServer(msgCount: 4)
        let session = await server.startedSession()
        #expect(session.timelines["c-town"]?.unreadCountOnOpen == 8)
        #expect(session.unreadMessageCount(channelId: "c-town") == 0)
        session.members["c-town"]?.msgCount = 4
        session.members["c-town"]?.msgCountRoot = 4
        #expect(session.unreadMessageCount(channelId: "c-town") == 8)
        session.collapsedThreads = true
        #expect(session.unreadMessageCount(channelId: "c-town") == 7)
        session.members["c-town"]?.msgCountRoot = 20
        #expect(session.unreadMessageCount(channelId: "c-town") == 0)
        #expect(session.unreadMessageCount(channelId: "missing") == 0)
        session.stop()
    }

    @Test func updateNewMessagesAtMovesTheMarker() async {
        let server = MockServer()
        let session = await server.startedSession()
        session.updateNewMessagesAt(channelId: "c-town", lastViewedAt: 777)
        #expect(session.timelines["c-town"]?.lastViewedAtOnOpen == 777)
        session.updateNewMessagesAt(channelId: "c-town", lastViewedAt: 777)
        session.updateNewMessagesAt(channelId: "missing", lastViewedAt: 1)
        #expect(session.timelines["missing"] == nil)
        session.stop()
    }

    @Test func unreadScrollPositionPreference() async {
        let server = MockServer()
        let session = await server.startedSession()
        #expect(session.unreadScrollPosition == .startFromLeftOff)
        session.preferences.append(Preference(userId: "me1", category: "advanced_settings", name: "unread_scroll_position", value: "start_from_newest"))
        #expect(session.unreadScrollPosition == .startFromNewest)
        session.preferences.append(Preference(userId: "me1", category: "advanced_settings", name: "unread_scroll_position", value: "bogus"))
        #expect(session.unreadScrollPosition == .startFromLeftOff)
        session.stop()
    }

    @Test func manuallyUnreadIsReported() async {
        let server = MockServer()
        let session = await server.startedSession()
        #expect(!session.isManuallyUnread(channelId: "c-town"))
        session.manuallyUnread.insert("c-town")
        #expect(session.isManuallyUnread(channelId: "c-town"))
        session.stop()
    }
}
