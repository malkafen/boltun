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
        isViewingChannel: Bool,
        isChannelWideMention: Bool = false,
        isTeamMuted: Bool = false,
        isMembershipUnknown: Bool = false,
        isThreadReply: Bool = false,
        isFollowingThread: Bool = true
    ) -> Bool {
        guard post.userId != me.id, !post.isSystemMessage, !post.isDeleted else { return false }
        guard post.props["from_webhook"]?.boolValue != true || mentioned || channelType.isDirectOrGroup else { return false }
        if myStatus == .dnd || isViewingChannel || isTeamMuted { return false }
        let settings = ChannelNotifySettings(member: member, user: me)
        guard !settings.muted else { return false }
        let level = settings.desktopLevel(user: me)
        guard level != .none else { return false }
        if isMembershipUnknown { return ChannelMention.mentionsUser(post.message, user: me) }
        let counts = mentioned && !(isChannelWideMention && settings.ignoresChannelMentions(user: me))
        if isThreadReply {
            guard isFollowingThread else { return false }
            return counts || level == .all || settings.desktopThreadsLevel(user: me) == .all
        }
        return counts || level == .all || channelType.isDirectOrGroup
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
