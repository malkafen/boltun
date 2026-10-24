import Foundation

public struct MemberReadCount: Codable, Hashable, Sendable {
    public var userId: String
    public var msgCount: Int
    public var msgCountRoot: Int

    public init(userId: String, msgCount: Int = 0, msgCountRoot: Int = 0) {
        self.userId = userId
        self.msgCount = msgCount
        self.msgCountRoot = msgCountRoot
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case msgCount = "msg_count"
        case msgCountRoot = "msg_count_root"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = c.value(.userId, default: "")
        msgCount = c.int(.msgCount)
        msgCountRoot = c.int(.msgCountRoot)
    }

    public func viewedCount(collapsedThreads: Bool) -> Int {
        collapsedThreads ? msgCountRoot : msgCount
    }
}

public enum PostReadState: Hashable, Sendable {
    case sent
    case seen
    case partiallySeen(seenBy: [String], total: Int)
}

public enum ReadStatus {
    public static let uncountedPostTypes: Set<String> = [
        "system_join_leave",
        "system_add_remove",
        "system_join_channel",
        "system_leave_channel",
        "system_join_team",
        "system_leave_team",
        "system_add_to_channel",
        "system_remove_from_channel",
        "system_add_to_team",
        "system_remove_from_team",
        "system_ephemeral",
        PostType.burnOnRead,
    ]

    public static func countsTowardsTotal(_ post: Post) -> Bool {
        !uncountedPostTypes.contains(post.type)
    }

    public static func total(of channel: Channel, collapsedThreads: Bool) -> Int {
        collapsedThreads ? channel.totalMsgCountRoot : channel.totalMsgCount
    }

    public static func states(
        posts: [Post],
        myId: String,
        total: Int,
        members: [MemberReadCount],
        collapsedThreads: Bool,
        pendingPostIds: Set<String> = []
    ) -> [String: PostReadState] {
        let others = members.filter { $0.userId != myId && !$0.userId.isEmpty }
        guard !myId.isEmpty, !others.isEmpty else { return [:] }
        let counted = posts.filter { post in
            !pendingPostIds.contains(post.id) && countsTowardsTotal(post) && (!collapsedThreads || !post.isReply)
        }
        let seenPrefixes = others.map { member in
            let unseen = max(0, total - member.viewedCount(collapsedThreads: collapsedThreads))
            return (userId: member.userId, length: max(0, counted.count - unseen))
        }
        var result: [String: PostReadState] = [:]
        for (index, post) in counted.enumerated() where isOwnMessage(post, myId: myId) {
            let seenBy = seenPrefixes.filter { index < $0.length }.map(\.userId)
            result[post.id] = state(seenBy: seenBy, total: others.count)
        }
        return result
    }

    public static func isOwnMessage(_ post: Post, myId: String) -> Bool {
        post.userId == myId && !post.isSystemMessage && !post.isDeleted
    }

    static func state(seenBy: [String], total: Int) -> PostReadState {
        if seenBy.isEmpty { return .sent }
        if seenBy.count >= total { return .seen }
        return .partiallySeen(seenBy: seenBy, total: total)
    }
}

public enum ReadStatusPolling {
    public static func shouldPoll(enabled: Bool, appActive: Bool, isCurrentChannel: Bool, hasUnseenOwnPost: Bool) -> Bool {
        enabled && appActive && isCurrentChannel && hasUnseenOwnPost
    }

    public static func nextDelay(after delay: Duration, maximum: Duration) -> Duration {
        min(delay * 2, maximum)
    }
}
