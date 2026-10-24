import Foundation

public enum UnreadScrollPosition: String, Sendable {
    case startFromLeftOff = "start_from_left_off"
    case startFromNewest = "start_from_newest"
}

public enum NewMessagesMarker {
    public static func starts(at post: Post, lastViewedAt: Int64, myId: String) -> Bool {
        lastViewedAt > 0
            && post.createAt > lastViewedAt
            && (post.userId != myId || post.isFromWebhook)
            && !post.isSilentNotification
    }

    public static func firstIndex(in posts: [Post], lastViewedAt: Int64, myId: String) -> Int? {
        posts.firstIndex { starts(at: $0, lastViewedAt: lastViewedAt, myId: myId) }
    }

    public static func unreadCount(posts: [Post], lastViewedAt: Int64, myId: String, collapsedThreads: Bool) -> Int {
        guard let index = firstIndex(in: posts, lastViewedAt: lastViewedAt, myId: myId) else { return 0 }
        return posts[index...].filter { !collapsedThreads || (!$0.isReply && !$0.isDeleted) }.count
    }
}

extension Post {
    public var isFromWebhook: Bool { props["from_webhook"]?.boolValue == true }

    public var isSilentNotification: Bool {
        props["silent_notification"]?.boolValue == true && props["force_notification"]?.boolValue != true
    }
}
