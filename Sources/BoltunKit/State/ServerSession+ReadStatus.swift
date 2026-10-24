import Foundation

extension ServerSession {
    public var isPollingReadStatus: Bool { readStatusPollTask != nil }

    public func tracksReadStatus(channelId: String) -> Bool {
        guard readStatusEnabled, !myId.isEmpty, let channel = channels[channelId] else { return false }
        switch channel.type {
        case .group:
            return true
        case .direct:
            guard let partner = channel.directPartnerId(me: myId), partner != myId else { return false }
            return users[partner]?.isBot != true
        case .open, .private:
            return false
        }
    }

    public func readStates(channelId: String) -> [String: PostReadState] {
        guard tracksReadStatus(channelId: channelId), let members = readCounts[channelId], let channel = channels[channelId] else { return [:] }
        return ReadStatus.states(
            posts: timelinePosts(channelId: channelId),
            myId: myId,
            total: ReadStatus.total(of: channel, collapsedThreads: collapsedThreads),
            members: members,
            collapsedThreads: collapsedThreads,
            pendingPostIds: pendingPostIds
        )
    }

    public func hasUnseenOwnPost(channelId: String) -> Bool {
        let states = readStates(channelId: channelId)
        guard let latest = timelinePosts(channelId: channelId).last(where: { states[$0.id] != nil }) else { return false }
        return states[latest.id] != .seen
    }

    public func setReadStatusEnabled(_ enabled: Bool) async {
        guard readStatusEnabled != enabled else { return }
        readStatusEnabled = enabled
        guard enabled else {
            stopReadStatusPolling()
            readCounts = [:]
            return
        }
        await refreshVisibleReadStatus(restartPolling: true)
    }

    public func refreshVisibleReadStatus(restartPolling: Bool = false) async {
        guard let channelId = currentChannelId else { return }
        await refreshReadStatus(channelId: channelId, restartPolling: restartPolling)
    }

    public func refreshReadStatus(channelId: String, restartPolling: Bool = false) async {
        guard isVisibleReadStatusChannel(channelId) else { return }
        if restartPolling { readStatusRestartPending = true }
        guard !readStatusRefreshing.contains(channelId) else {
            readStatusQueued.insert(channelId)
            return
        }
        readStatusRefreshing.insert(channelId)
        repeat {
            readStatusQueued.remove(channelId)
            await fetchReadCounts(channelId: channelId)
        } while readStatusQueued.contains(channelId) && isVisibleReadStatusChannel(channelId)
        readStatusQueued.remove(channelId)
        readStatusRefreshing.remove(channelId)
        let restart = readStatusRestartPending
        readStatusRestartPending = false
        updateReadStatusPolling(restart: restart)
    }

    func isVisibleReadStatusChannel(_ channelId: String) -> Bool {
        channelId == currentChannelId && tracksReadStatus(channelId: channelId)
    }

    func fetchReadCounts(channelId: String) async {
        do {
            async let channelRequest = client.channel(id: channelId)
            async let countsRequest = client.channelMemberReadCounts(channelId: channelId)
            let (channel, counts) = try await (channelRequest, countsRequest)
            applyReadCounts(channel: channel, counts: counts)
        } catch {
            report(error, silently: true)
        }
    }

    func applyReadCounts(channel fetched: Channel, counts: [MemberReadCount]) {
        guard readStatusEnabled else { return }
        var channel = fetched
        if let local = channels[fetched.id] {
            channel.totalMsgCount = max(local.totalMsgCount, fetched.totalMsgCount)
            channel.totalMsgCountRoot = max(local.totalMsgCountRoot, fetched.totalMsgCountRoot)
            channel.lastPostAt = max(local.lastPostAt, fetched.lastPostAt)
            channel.lastRootPostAt = max(local.lastRootPostAt, fetched.lastRootPostAt)
        }
        if channels[channel.id] != channel { channels[channel.id] = channel }
        let others = counts.filter { $0.userId != myId && !$0.userId.isEmpty }.sorted { $0.userId < $1.userId }
        if readCounts[channel.id] != others { readCounts[channel.id] = others }
    }

    func readStatusActivity(channelId: String, userId: String) {
        guard !userId.isEmpty, userId != myId, isVisibleReadStatusChannel(channelId) else { return }
        Task { await self.refreshReadStatus(channelId: channelId) }
    }

    func ownPostCreated(channelId: String) {
        guard isVisibleReadStatusChannel(channelId) else { return }
        Task { await self.refreshReadStatus(channelId: channelId, restartPolling: true) }
    }

    func shouldPollReadStatus(channelId: String) -> Bool {
        ReadStatusPolling.shouldPoll(
            enabled: tracksReadStatus(channelId: channelId),
            appActive: isAppActive(),
            isCurrentChannel: channelId == currentChannelId,
            hasUnseenOwnPost: hasUnseenOwnPost(channelId: channelId)
        )
    }

    func updateReadStatusPolling(restart: Bool = false) {
        guard let channelId = currentChannelId, shouldPollReadStatus(channelId: channelId) else {
            stopReadStatusPolling()
            return
        }
        guard restart || readStatusPollTask == nil || readStatusPollChannelId != channelId else { return }
        startReadStatusPolling(channelId: channelId)
    }

    func startReadStatusPolling(channelId: String) {
        readStatusPollTask?.cancel()
        readStatusPollChannelId = channelId
        let first = readStatusPollInterval
        let maximum = readStatusMaxPollInterval
        readStatusPollTask = Task { [weak self] in
            var delay = first
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                guard self.shouldPollReadStatus(channelId: channelId) else {
                    self.stopReadStatusPolling()
                    return
                }
                await self.refreshReadStatus(channelId: channelId)
                delay = ReadStatusPolling.nextDelay(after: delay, maximum: maximum)
            }
        }
    }

    public func stopReadStatusPolling() {
        readStatusPollTask?.cancel()
        readStatusPollTask = nil
        readStatusPollChannelId = nil
    }
}
