import Foundation

extension ServerSession {
    public var watchedUserIds: [String] {
        var ids = Set<String>()
        if !myId.isEmpty { ids.insert(myId) }
        for channelId in sidebar.flatMap(\.channelIds) {
            if let partner = channels[channelId]?.directPartnerId(me: myId) { ids.insert(partner) }
        }
        if let channelId = currentChannelId {
            for post in timelinePosts(channelId: channelId).suffix(presenceRecentPostLimit) where post.overrideUsername == nil {
                ids.insert(post.userId)
            }
        }
        for rootId in threads.keys {
            for post in threadPosts(rootId: rootId) where post.overrideUsername == nil { ids.insert(post.userId) }
        }
        ids.remove("")
        return Array(ids.sorted().prefix(presenceBatchLimit))
    }

    public func refreshPresence() async {
        guard config.enableUserStatuses else { return }
        await refreshStatuses(watchedUserIds)
    }

    func refreshMissingStatuses(_ ids: some Sequence<String>) async {
        guard config.enableUserStatuses else { return }
        let missing = Set(ids).subtracting(statuses.keys).subtracting(requestedStatusIds).filter { !$0.isEmpty }
        guard !missing.isEmpty else { return }
        requestedStatusIds.formUnion(missing)
        await refreshStatuses(missing.sorted())
        requestedStatusIds.subtract(missing)
    }

    func startPresence() {
        guard presenceTask == nil else { return }
        let interval = presenceInterval
        presenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                if self.isAppActive() { await self.refreshPresence() }
            }
        }
    }

    func stopPresence() {
        presenceTask?.cancel()
        presenceTask = nil
    }

    func markActive(userId: String) {
        guard !userId.isEmpty, userId != myId else { return }
        switch statuses[userId] {
        case .online, .dnd: return
        default: statuses[userId] = .online
        }
    }
}
