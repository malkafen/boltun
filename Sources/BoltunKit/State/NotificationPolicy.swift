import Foundation

public struct MentionNotification: Hashable, Sendable {
    public var serverId: UUID
    public var teamId: String
    public var channelId: String
    public var postId: String
    public var rootId: String
    public var title: String
    public var body: String

    public init(serverId: UUID, teamId: String, channelId: String, postId: String, rootId: String, title: String, body: String) {
        self.serverId = serverId
        self.teamId = teamId
        self.channelId = channelId
        self.postId = postId
        self.rootId = rootId
        self.title = title
        self.body = body
    }
}

public enum NotificationPolicy {
    public static func shouldNotify(
        post: Post,
        channelType: ChannelType,
        mentioned: Bool,
        me: User,
        member: ChannelMember?,
        myStatus: UserStatusValue?,
        isViewingChannel: Bool
    ) -> Bool {
        guard post.userId != me.id, !post.isSystemMessage, !post.isDeleted else { return false }
        guard post.props["from_webhook"]?.boolValue != true || mentioned || channelType.isDirectOrGroup else { return false }
        if myStatus == .dnd || isViewingChannel { return false }
        let channelLevel = member?.desktopNotifyLevel ?? "default"
        let level = channelLevel == "default" ? (me.notifyProps["desktop"] ?? "mention") : channelLevel
        switch level {
        case "all":
            return true
        case "none":
            return false
        default:
            if member?.isMuted == true && !mentioned { return false }
            return mentioned || channelType.isDirectOrGroup
        }
    }

    public static func preview(_ message: String, limit: Int = 200) -> String {
        let collapsed = message
            .replacingOccurrences(of: "\r", with: "")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .joined(separator: " ")
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit - 1)) + "…"
    }
}
