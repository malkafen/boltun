import Foundation

extension ServerSession {
    public func isFollowing(threadId: String) -> Bool {
        guard let root = posts[threadId] else { return false }
        if let value = root.isFollowing { return value }
        return !myId.isEmpty && (root.userId == myId || root.participantIds.contains(myId))
    }

    public func setFollowing(threadId: String, _ following: Bool) async {
        guard let root = posts[threadId], !root.isReply, !myId.isEmpty, !pendingPostIds.contains(threadId),
              let teamId = threadTeamId(root)
        else { return }
        let previous = root.isFollowing
        posts[threadId]?.isFollowing = following
        do {
            try await client.setThreadFollowing(userId: myId, teamId: teamId, threadId: threadId, following: following)
        } catch {
            posts[threadId]?.isFollowing = previous
            report(error)
        }
    }

    func threadTeamId(_ post: Post) -> String? {
        channels[post.channelId]?.teamId.nonEmpty ?? currentTeamId ?? teams.first?.id
    }

    func markFollowing(threadId: String, _ following: Bool) {
        guard let root = posts[threadId], root.isFollowing != following else { return }
        posts[threadId]?.isFollowing = following
    }

    func applyFollowers(_ event: WebSocketEvent, post: Post, mentioned: Bool) {
        guard !myId.isEmpty else { return }
        let followers = event.embedded([String].self, "followers")
        let followed = followers?.contains(myId) ?? mentioned
        if followed || (post.isReply && post.userId == myId) {
            markFollowing(threadId: post.threadId, true)
        }
    }

    func applyFollowChange(_ event: WebSocketEvent) {
        guard let threadId = event.string("thread_id"), let state = event.data["state"]?.boolValue else { return }
        markFollowing(threadId: threadId, state)
    }
}
