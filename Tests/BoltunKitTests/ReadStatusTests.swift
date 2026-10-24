import Foundation
import Testing
@testable import BoltunKit

@Suite struct MemberReadCountTests {
    @Test func decodesSanitizedMemberWithoutLastViewedAt() throws {
        let json: [String: Any] = [
            "channel_id": "c1", "user_id": "u2", "roles": "channel_user",
            "msg_count": 12, "msg_count_root": 9, "mention_count": 1, "mention_count_root": 1,
            "urgent_mention_count": 0, "notify_props": ["desktop": "default"], "last_update_at": 1_700_000_000_000,
        ]
        let count = try Fixtures.decode(MemberReadCount.self, json)
        #expect(count == MemberReadCount(userId: "u2", msgCount: 12, msgCountRoot: 9))
        #expect(count.viewedCount(collapsedThreads: false) == 12)
        #expect(count.viewedCount(collapsedThreads: true) == 9)
    }

    @Test func missingFieldsDefaultToZero() throws {
        let count = try Fixtures.decode(MemberReadCount.self, [String: Any]())
        #expect(count == MemberReadCount(userId: ""))
    }

    @Test func roundTripsThroughEncoding() throws {
        let original = MemberReadCount(userId: "u3", msgCount: 4, msgCountRoot: 2)
        let data = try JSONEncoder().encode(original)
        #expect(try MattermostJSON.decoder.decode(MemberReadCount.self, from: data) == original)
    }

    @Test func endpointRequestsAllMembersInOnePage() async throws {
        let transport = FakeTransport()
        transport.on("GET", "channels/c1/members", object: [
            Fixtures.member("c1", user: "me1", msgCount: 5, lastViewedAt: 10),
            ["channel_id": "c1", "user_id": "u2", "msg_count": 3, "msg_count_root": 2],
        ])
        let client = APIClient(baseURL: URL(string: "https://chat.example.com")!, token: "tok", transport: transport)
        let counts = try await client.channelMemberReadCounts(channelId: "c1")
        #expect(counts == [MemberReadCount(userId: "me1", msgCount: 5, msgCountRoot: 5), MemberReadCount(userId: "u2", msgCount: 3, msgCountRoot: 2)])
        let request = try #require(transport.last("GET", "channels/c1/members"))
        #expect(request.query == ["page": "0", "per_page": "200"])
    }
}

@Suite struct ReadStatusStateTests {
    static let me = "me"

    func post(_ id: String, _ user: String, at: Int64, root: String = "", type: String = "", deleted: Bool = false) -> Post {
        Post(id: id, createAt: at, deleteAt: deleted ? at + 1 : 0, userId: user, channelId: "c", rootId: root, message: id, type: type)
    }

    func states(_ posts: [Post], total: Int, members: [MemberReadCount], collapsed: Bool = false, pending: Set<String> = []) -> [String: PostReadState] {
        ReadStatus.states(posts: posts, myId: Self.me, total: total, members: members, collapsedThreads: collapsed, pendingPostIds: pending)
    }

    @Test func directMessageSplitsSeenAndSentAtTheUnseenCount() {
        let posts = [post("a", "me", at: 1), post("b", "u2", at: 2), post("c", "me", at: 3), post("d", "me", at: 4)]
        let result = states(posts, total: 10, members: [MemberReadCount(userId: "u2", msgCount: 8)])
        #expect(result == ["a": .seen, "c": .sent, "d": .sent])
    }

    @Test func directMessageFullyViewedIsSeen() {
        let posts = [post("a", "me", at: 1), post("b", "me", at: 2)]
        #expect(states(posts, total: 2, members: [MemberReadCount(userId: "u2", msgCount: 2)]) == ["a": .seen, "b": .seen])
    }

    @Test func memberThatNeverViewedSeesNothing() {
        let posts = [post("a", "me", at: 1), post("b", "me", at: 2)]
        #expect(states(posts, total: 2, members: [MemberReadCount(userId: "u2")]) == ["a": .sent, "b": .sent])
    }

    @Test func groupMessageReportsWhoHasSeenEachPost() {
        let posts = [post("a", "me", at: 1), post("b", "me", at: 2), post("c", "me", at: 3)]
        let members = [
            MemberReadCount(userId: "me", msgCount: 3),
            MemberReadCount(userId: "u2", msgCount: 3),
            MemberReadCount(userId: "u3", msgCount: 2),
            MemberReadCount(userId: "u4", msgCount: 1),
        ]
        let result = states(posts, total: 3, members: members)
        #expect(result["a"] == .seen)
        #expect(result["b"] == .partiallySeen(seenBy: ["u2", "u3"], total: 3))
        #expect(result["c"] == .partiallySeen(seenBy: ["u2"], total: 3))
    }

    @Test func groupMessageSeenByNobodyIsSent() {
        let posts = [post("a", "me", at: 1)]
        let result = states(posts, total: 1, members: [MemberReadCount(userId: "u2"), MemberReadCount(userId: "u3")])
        #expect(result == ["a": .sent])
    }

    @Test func collapsedThreadsUseRootCountsAndIgnoreReplies() {
        let posts = [post("a", "me", at: 1), post("r1", "u2", at: 2, root: "a"), post("b", "me", at: 3), post("r2", "me", at: 4, root: "a")]
        let members = [MemberReadCount(userId: "u2", msgCount: 1, msgCountRoot: 1)]
        let result = states(posts, total: 2, members: members, collapsed: true)
        #expect(result == ["a": .seen, "b": .sent])
    }

    @Test func expandedThreadsCountRepliesInTimelineOrder() {
        let posts = [post("a", "me", at: 1), post("r1", "me", at: 2, root: "a"), post("b", "me", at: 3)]
        let members = [MemberReadCount(userId: "u2", msgCount: 2, msgCountRoot: 2)]
        let result = states(posts, total: 3, members: members)
        #expect(result == ["a": .seen, "r1": .seen, "b": .sent])
    }

    @Test func systemMessagesCountButJoinLeaveAndBurnOnReadDoNot() {
        let posts = [
            post("a", "me", at: 1),
            post("header", "me", at: 2, type: "system_header_change"),
            post("join", "u3", at: 3, type: "system_join_channel"),
            post("bor", "me", at: 4, type: PostType.burnOnRead),
            post("b", "me", at: 5),
        ]
        let result = states(posts, total: 3, members: [MemberReadCount(userId: "u2", msgCount: 2)])
        #expect(result == ["a": .seen, "b": .sent])
    }

    @Test func pendingPostsKeepTheirOwnStateAndAreNotCounted() {
        let posts = [post("a", "me", at: 1), post("me:2", "me", at: 2)]
        let result = states(posts, total: 1, members: [MemberReadCount(userId: "u2", msgCount: 1)], pending: ["me:2"])
        #expect(result == ["a": .seen])
    }

    @Test func deletedOwnPostsGetNoState() {
        let posts = [post("a", "me", at: 1, deleted: true), post("b", "me", at: 2)]
        #expect(states(posts, total: 2, members: [MemberReadCount(userId: "u2", msgCount: 2)]) == ["b": .seen])
    }

    @Test func unseenCountLargerThanLoadedPostsMarksEverythingSent() {
        let posts = [post("a", "me", at: 1), post("b", "me", at: 2)]
        #expect(states(posts, total: 500, members: [MemberReadCount(userId: "u2", msgCount: 10)]) == ["a": .sent, "b": .sent])
    }

    @Test func viewedCountAboveTotalMarksEverythingSeen() {
        let posts = [post("a", "me", at: 1)]
        #expect(states(posts, total: 3, members: [MemberReadCount(userId: "u2", msgCount: 7)]) == ["a": .seen])
    }

    @Test func olderHistoryOutsideTheLoadedPageDoesNotShiftTheBoundary() {
        let posts = [post("a", "me", at: 100), post("b", "me", at: 101)]
        #expect(states(posts, total: 250, members: [MemberReadCount(userId: "u2", msgCount: 249)]) == ["a": .seen, "b": .sent])
    }

    @Test func withoutOtherMembersThereIsNothingToReport() {
        let posts = [post("a", "me", at: 1)]
        #expect(states(posts, total: 1, members: []).isEmpty)
        #expect(states(posts, total: 1, members: [MemberReadCount(userId: "me", msgCount: 1), MemberReadCount(userId: "")]).isEmpty)
        #expect(ReadStatus.states(posts: posts, myId: "", total: 1, members: [MemberReadCount(userId: "u2")], collapsedThreads: false).isEmpty)
    }

    @Test func countedPostTypesMatchTheServer() {
        #expect(ReadStatus.countsTowardsTotal(post("a", "me", at: 1)))
        #expect(ReadStatus.countsTowardsTotal(post("a", "me", at: 1, type: "system_header_change")))
        #expect(ReadStatus.countsTowardsTotal(post("a", "me", at: 1, type: "system_purpose_change")))
        for type in ["system_join_channel", "system_leave_channel", "system_add_to_channel", "system_remove_from_channel", "system_join_leave", "system_ephemeral", "burn_on_read"] {
            #expect(!ReadStatus.countsTowardsTotal(post("a", "me", at: 1, type: type)), "\(type)")
        }
    }

    @Test func totalFollowsCollapsedThreads() {
        let channel = Channel(id: "c", type: .direct, name: "a__b", totalMsgCount: 9, totalMsgCountRoot: 4)
        #expect(ReadStatus.total(of: channel, collapsedThreads: false) == 9)
        #expect(ReadStatus.total(of: channel, collapsedThreads: true) == 4)
    }

    @Test func ownMessageExcludesSystemDeletedAndOthers() {
        #expect(ReadStatus.isOwnMessage(post("a", "me", at: 1), myId: "me"))
        #expect(!ReadStatus.isOwnMessage(post("a", "u2", at: 1), myId: "me"))
        #expect(!ReadStatus.isOwnMessage(post("a", "me", at: 1, type: "system_header_change"), myId: "me"))
        #expect(!ReadStatus.isOwnMessage(post("a", "me", at: 1, deleted: true), myId: "me"))
    }
}

@Suite struct ReadStatusPollingTests {
    @Test func pollsOnlyWhenEveryConditionHolds() {
        #expect(ReadStatusPolling.shouldPoll(enabled: true, appActive: true, isCurrentChannel: true, hasUnseenOwnPost: true))
        #expect(!ReadStatusPolling.shouldPoll(enabled: false, appActive: true, isCurrentChannel: true, hasUnseenOwnPost: true))
        #expect(!ReadStatusPolling.shouldPoll(enabled: true, appActive: false, isCurrentChannel: true, hasUnseenOwnPost: true))
        #expect(!ReadStatusPolling.shouldPoll(enabled: true, appActive: true, isCurrentChannel: false, hasUnseenOwnPost: true))
        #expect(!ReadStatusPolling.shouldPoll(enabled: true, appActive: true, isCurrentChannel: true, hasUnseenOwnPost: false))
    }

    @Test func backsOffByDoublingUpToTheMaximum() {
        let maximum = Duration.seconds(120)
        #expect(ReadStatusPolling.nextDelay(after: .seconds(30), maximum: maximum) == .seconds(60))
        #expect(ReadStatusPolling.nextDelay(after: .seconds(60), maximum: maximum) == .seconds(120))
        #expect(ReadStatusPolling.nextDelay(after: .seconds(120), maximum: maximum) == .seconds(120))
    }
}
