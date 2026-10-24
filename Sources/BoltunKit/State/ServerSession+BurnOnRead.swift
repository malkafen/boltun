import Foundation

public struct BurnOnReadReceipt: Equatable, Sendable {
    public var revealedCount: Int
    public var totalRecipients: Int

    public init(revealedCount: Int, totalRecipients: Int) {
        self.revealedCount = revealedCount
        self.totalRecipients = totalRecipients
    }
}

extension ServerSession {
    public var burnOnReadEnabled: Bool { config.enableBurnOnRead && license.isMinimumEnterpriseAdvanced }

    public var burnOnReadDurationMinutes: Int { config.burnOnReadDurationMinutes }

    public func canSendBurnOnRead(channelId: String) -> Bool {
        guard burnOnReadEnabled, let channel = channels[channelId], !channel.isArchived else { return false }
        guard let partner = channel.directPartnerId(me: myId) else { return true }
        return partner != myId && users[partner]?.isBot != true
    }

    public func isConcealed(postId: String) -> Bool {
        posts[postId]?.isBurnOnReadConcealed(for: myId) ?? false
    }

    public func isRevealing(postId: String) -> Bool { revealingPostIds.contains(postId) }

    public func burnOnReadReceipt(postId: String) -> BurnOnReadReceipt? {
        guard let post = posts[postId], post.isBurnOnRead, post.userId == myId, !myId.isEmpty else { return nil }
        guard let memberCount = channelMemberCounts[post.channelId] else { return nil }
        return BurnOnReadReceipt(revealedCount: post.burnOnReadRevealedBy.count, totalRecipients: max(0, memberCount - 1))
    }

    public func revealBurnOnRead(postId: String) async {
        guard let post = posts[postId], post.isBurnOnRead, post.userId != myId, !pendingPostIds.contains(postId) else { return }
        guard !post.isBurnOnReadRevealed(by: myId), !revealingPostIds.contains(postId) else { return }
        revealingPostIds.insert(postId)
        defer { revealingPostIds.remove(postId) }
        do {
            receive(post: try await client.revealPost(id: postId))
            scheduleBurnOnReadExpiry()
        } catch {
            report(error)
        }
    }

    public func burn(postId: String) async {
        guard let post = posts[postId], post.isBurnOnRead, !pendingPostIds.contains(postId) else { return }
        do {
            try await client.burnPost(id: postId)
            removePost(postId)
        } catch {
            report(error)
        }
    }

    func refreshChannelStats(channelId: String) async {
        guard !channelId.isEmpty, !requestedStatsChannelIds.contains(channelId) else { return }
        requestedStatsChannelIds.insert(channelId)
        guard let stats = await quietly({ try await client.channelStats(channelId: channelId) }) else {
            requestedStatsChannelIds.remove(channelId)
            return
        }
        channelMemberCounts[channelId] = stats.memberCount
    }

    func trackBurnOnRead(_ post: Post) {
        guard post.isBurnOnRead else { return }
        if post.userId == myId, channelMemberCounts[post.channelId] == nil {
            let channelId = post.channelId
            Task { await self.refreshChannelStats(channelId: channelId) }
        }
        for userId in post.burnOnReadRevealedBy where users[userId] == nil {
            Task { await self.ensureUsers([userId]) }
        }
        scheduleBurnOnReadExpiry()
    }

    var nextBurnOnReadExpiry: Int64? {
        posts.values.filter { $0.isBurnOnRead && $0.burnOnReadExpireAt > 0 }.map(\.burnOnReadExpireAt).min()
    }

    func removeExpiredBurnOnReadPosts() {
        let current = now().mattermostMillis
        for post in posts.values where post.isBurnOnRead && BurnOnRead.isExpired(expireAt: post.burnOnReadExpireAt, now: current) {
            removePost(post.id)
        }
    }

    func scheduleBurnOnReadExpiry() {
        removeExpiredBurnOnReadPosts()
        burnOnReadTask?.cancel()
        burnOnReadTask = nil
        guard let next = nextBurnOnReadExpiry else { return }
        let delay = max(0, next - now().mattermostMillis)
        burnOnReadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay + 50))
            guard !Task.isCancelled, let self else { return }
            self.burnOnReadTask = nil
            self.scheduleBurnOnReadExpiry()
        }
    }

    func stopBurnOnReadExpiry() {
        burnOnReadTask?.cancel()
        burnOnReadTask = nil
    }

    func handlePostRevealed(_ event: WebSocketEvent) {
        guard let revealed = event.embedded(Post.self, "post"), let existing = posts[revealed.id] else { return }
        if existing.userId == myId {
            let added = event.embedded([String].self, "recipients") ?? []
            var post = existing
            for userId in added where !post.metadata.recipients.contains(userId) && !userId.isEmpty {
                post.metadata.recipients.append(userId)
            }
            if revealed.metadata.expireAt > 0 { post.metadata.expireAt = revealed.metadata.expireAt }
            posts[revealed.id] = post
            trackBurnOnRead(post)
        } else if !revealed.message.isEmpty {
            receive(post: revealed)
            scheduleBurnOnReadExpiry()
        }
    }

    func handlePostBurned(_ event: WebSocketEvent) {
        guard let postId = event.string("post_id"), posts[postId] != nil else { return }
        removePost(postId)
    }

    func handleBurnOnReadAllRevealed(_ event: WebSocketEvent) {
        guard let postId = event.string("post_id"),
              let expireAt = event.data["sender_expire_at"]?.doubleValue.map({ Int64(clamping: $0) }), expireAt > 0,
              posts[postId] != nil
        else { return }
        posts[postId]?.metadata.expireAt = expireAt
        scheduleBurnOnReadExpiry()
    }
}
