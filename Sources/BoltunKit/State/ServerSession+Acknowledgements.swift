import Foundation

extension ServerSession {
    public var postPriorityEnabled: Bool { config.postPriority }

    public var acknowledgementsEnabled: Bool { config.postAcknowledgements }

    public var persistentNotificationsEnabled: Bool { config.allowPersistentNotifications && acknowledgementsEnabled }

    public func loadLicense() async {
        guard let loaded = await quietly({ try await client.clientLicense() }) else { return }
        license = loaded
    }

    func effectivePriority(_ priority: PostPriority?, rootId: String) -> PostPriority? {
        guard var priority, rootId.isEmpty, postPriorityEnabled else { return nil }
        if !acknowledgementsEnabled { priority.requestedAck = false }
        if !persistentNotificationsEnabled || priority.priority != .urgent { priority.persistentNotifications = false }
        return priority.isDefault ? nil : priority
    }

    public func acknowledgementPeople(postId: String) -> [(userId: String, acknowledgedAt: Int64)] {
        guard let post = posts[postId] else { return [] }
        return post.acknowledgements.map { ($0.userId, $0.acknowledgedAt) }
    }

    public func canToggleAcknowledgement(postId: String) -> Bool {
        guard acknowledgementsEnabled, !myId.isEmpty, let post = posts[postId] else { return false }
        guard post.requestsAcknowledgement, !post.isDeleted, post.userId != myId, !pendingPostIds.contains(postId) else { return false }
        guard let acknowledgedAt = post.acknowledgedAt(by: myId) else { return true }
        return now().mattermostMillis - acknowledgedAt <= BurnOnRead.acknowledgementWindow
    }

    public func toggleAcknowledgement(postId: String) async {
        guard canToggleAcknowledgement(postId: postId), let post = posts[postId] else { return }
        if post.acknowledgedAt(by: myId) != nil {
            await removeAcknowledgement(postId: postId)
        } else {
            await acknowledge(postId: postId)
        }
    }

    func acknowledge(postId: String) async {
        do {
            applyAcknowledgement(try await client.acknowledgePost(userId: myId, postId: postId), added: true)
        } catch {
            report(error)
        }
    }

    func removeAcknowledgement(postId: String) async {
        do {
            try await client.unacknowledgePost(userId: myId, postId: postId)
            applyAcknowledgement(PostAcknowledgement(userId: myId, postId: postId), added: false)
        } catch {
            report(error)
        }
    }

    func applyAcknowledgement(_ acknowledgement: PostAcknowledgement, added: Bool) {
        guard var post = posts[acknowledgement.postId] else { return }
        post.metadata.acknowledgements.removeAll { $0.userId == acknowledgement.userId }
        if added { post.metadata.acknowledgements.append(acknowledgement) }
        posts[acknowledgement.postId] = post
        if added, users[acknowledgement.userId] == nil {
            let userId = acknowledgement.userId
            Task { await self.ensureUsers([userId]) }
        }
    }

    func handleAcknowledgementEvent(_ event: WebSocketEvent, added: Bool) {
        guard let acknowledgement = event.embedded(PostAcknowledgement.self, "acknowledgement") else { return }
        applyAcknowledgement(acknowledgement, added: added)
    }
}
