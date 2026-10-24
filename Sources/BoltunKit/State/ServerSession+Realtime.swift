import Foundation

extension ServerSession {
    func startRealtime(token: String) {
        guard realtime == nil else { return }
        let client = realtimeFactory(self.client.webSocketURL, token)
        realtime = client
        realtimeTask = Task { [weak self] in
            await client.start()
            for await event in client.events {
                guard let self else { return }
                await self.handle(realtime: event)
            }
        }
    }

    public func reconnectRealtime() {
        guard let realtime else { return }
        Task { await realtime.reconnectNow() }
    }

    func handle(realtime event: RealtimeEvent) async {
        switch event {
        case .connected(let needsResync):
            guard connection != .unauthorized else { return }
            connection = .connected
            if needsResync {
                await resync()
                await refreshPresence()
            }
        case .disconnected:
            guard connection != .unauthorized else { return }
            connection = .reconnecting
            Task { await self.verifySession() }
        case .event(let event):
            guard connection != .unauthorized else { return }
            apply(event)
        }
    }

    func verifySession() async {
        do {
            _ = try await client.me()
        } catch {
            report(error, silently: true)
        }
    }

    func resync() async {
        for id in timelines.keys where id != currentChannelId {
            timelines[id]?.loaded = false
        }
        do {
            try await loadInitial()
        } catch {
            report(error)
            return
        }
        for rootId in threads.keys {
            await openThread(rootId: rootId)
        }
    }

    public func apply(_ event: WebSocketEvent) {
        switch event.event {
        case WebSocketEventType.posted:
            handlePosted(event)
        case WebSocketEventType.postEdited:
            handlePostEdited(event)
        case WebSocketEventType.postDeleted:
            if let post = event.embedded(Post.self, "post") { removePost(post.id, fallback: post) }
        case WebSocketEventType.reactionAdded, WebSocketEventType.reactionRemoved:
            if let reaction = event.embedded(Reaction.self, "reaction") {
                applyReaction(reaction, added: event.event == WebSocketEventType.reactionAdded)
            }
        case WebSocketEventType.typing:
            handleTyping(event)
        case WebSocketEventType.channelViewed:
            if let channelId = event.string("channel_id") { viewedElsewhere([channelId]) }
        case WebSocketEventType.multipleChannelsViewed:
            viewedElsewhere(Array((event.data["channel_times"]?.objectValue ?? [:]).keys))
        case WebSocketEventType.postUnread:
            handlePostUnread(event)
        case WebSocketEventType.channelCreated, WebSocketEventType.directAdded, WebSocketEventType.groupAdded, WebSocketEventType.channelRestored:
            let channelId = event.string("channel_id") ?? event.channelId
            Task { await self.refreshChannel(channelId) }
        case WebSocketEventType.channelUpdated:
            if let channel = event.embedded(Channel.self, "channel") {
                channels[channel.id] = channel
            } else {
                Task { await self.refreshChannel(event.channelId) }
            }
        case WebSocketEventType.channelDeleted:
            let channelId = event.string("channel_id") ?? event.channelId
            if var channel = channels[channelId] {
                channel.deleteAt = event.data["delete_at"]?.doubleValue.map { Int64(clamping: $0) } ?? now().mattermostMillis
                channels[channelId] = channel
            }
        case WebSocketEventType.channelMemberUpdated:
            if let member = event.embedded(ChannelMember.self, "channelMember"), member.userId == myId {
                members[member.channelId] = member
            }
        case WebSocketEventType.userAdded:
            if event.string("user_id") == myId {
                Task { await self.refreshChannel(event.channelId) }
            }
        case WebSocketEventType.userRemoved:
            let channelId = event.string("channel_id") ?? event.channelId
            if event.broadcast.userId == myId || event.string("user_id") == myId {
                removeChannelMembership(channelId)
            }
        case WebSocketEventType.userUpdated:
            if let user = event.embedded(User.self, "user") {
                users[user.id] = user
                if user.id == myId { me = user }
            }
        case WebSocketEventType.statusChange:
            if let userId = event.string("user_id"), let raw = event.string("status"), let status = UserStatusValue(rawValue: raw) {
                statuses[userId] = status
            }
        case WebSocketEventType.addedToTeam:
            Task { await self.refreshTeams() }
        case WebSocketEventType.leaveTeam:
            if event.string("user_id") == myId { Task { await self.refreshTeams() } }
        case WebSocketEventType.updateTeam:
            if let team = event.embedded(Team.self, "team"), let index = teams.firstIndex(where: { $0.id == team.id }) {
                teams[index] = team
                teams = Self.sortedTeams(teams)
            }
        case WebSocketEventType.preferencesChanged:
            if let list = event.embedded([Preference].self, "preferences") { applyPreferences(list) }
        case WebSocketEventType.preferencesDeleted:
            if let list = event.embedded([Preference].self, "preferences") {
                for preference in list {
                    preferences.removeAll { $0.category == preference.category && $0.name == preference.name }
                }
            }
        case WebSocketEventType.sidebarCategoryCreated, WebSocketEventType.sidebarCategoryUpdated,
             WebSocketEventType.sidebarCategoryDeleted, WebSocketEventType.sidebarCategoryOrderUpdated:
            let teamId = event.broadcast.teamId.isEmpty ? (event.string("team_id") ?? "") : event.broadcast.teamId
            if loadedTeams.contains(teamId) {
                Task { _ = await self.quietly { try await self.refreshCategories(teamId: teamId) } }
            }
        case WebSocketEventType.emojiAdded:
            if let emoji = event.embedded(CustomEmoji.self, "emoji") { customEmojis[emoji.name] = emoji }
        case WebSocketEventType.threadFollowChanged:
            applyFollowChange(event)
        case WebSocketEventType.postAcknowledgementAdded, WebSocketEventType.postAcknowledgementRemoved:
            handleAcknowledgementEvent(event, added: event.event == WebSocketEventType.postAcknowledgementAdded)
        case WebSocketEventType.postRevealed:
            handlePostRevealed(event)
        case WebSocketEventType.postBurned:
            handlePostBurned(event)
        case WebSocketEventType.burnOnReadAllRevealed:
            handleBurnOnReadAllRevealed(event)
        default:
            break
        }
    }

    func handlePostEdited(_ event: WebSocketEvent) {
        guard let post = event.embedded(Post.self, "post"), !deletedPostIds.contains(post.id) else { return }
        guard posts[post.id] != nil || timelines[post.channelId]?.loaded == true else { return }
        var merged = post
        if let old = posts[post.id] {
            if old.updateAt > post.updateAt { return }
            if merged.metadata.reactions.isEmpty { merged.metadata.reactions = old.metadata.reactions }
            merged = merged.mergingThreadSummary(from: old).mergingReadInfo(from: old)
        }
        posts[post.id] = merged
        trackBurnOnRead(merged)
    }

    func handleTyping(_ event: WebSocketEvent) {
        let userId = event.string("user_id") ?? ""
        guard !userId.isEmpty, userId != myId else { return }
        let key = typingKey(channelId: event.channelId, parentId: event.string("parent_id") ?? "")
        let stamp = now()
        typing[key, default: [:]][userId] = stamp
        let timeout = typingTimeout
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.expireTyping(key: key, userId: userId, stamp: stamp)
        }
        if users[userId] == nil { Task { await self.ensureUsers([userId]) } }
    }

    func expireTyping(key: String, userId: String, stamp: Date) {
        guard typing[key]?[userId] == stamp else { return }
        typing[key]?[userId] = nil
        if typing[key]?.isEmpty == true { typing[key] = nil }
    }

    func clearTyping(channelId: String, parentId: String, userId: String) {
        let key = typingKey(channelId: channelId, parentId: parentId)
        guard typing[key]?[userId] != nil else { return }
        typing[key]?[userId] = nil
        if typing[key]?.isEmpty == true { typing[key] = nil }
    }

    func handlePosted(_ event: WebSocketEvent) {
        guard let post = event.embedded(Post.self, "post") else { return }
        if !post.pendingPostId.isEmpty { discardPending(post.pendingPostId) }
        let isNew = posts[post.id] == nil && !deletedPostIds.contains(post.id)
        clearTyping(channelId: post.channelId, parentId: post.rootId, userId: post.userId)
        let mentions = event.embedded([String].self, "mentions") ?? []
        let mentioned = !myId.isEmpty && mentions.contains(myId)
        let eventTeamId = event.string("team_id").flatMap(\.nonEmpty) ?? event.broadcast.teamId.nonEmpty ?? ""
        let channel = channels[post.channelId]
        let teamId = channel.flatMap { $0.teamId.nonEmpty } ?? eventTeamId
        let fromOthers = isNew && post.userId != myId
        if fromOthers, !teamId.isEmpty, !loadedTeams.contains(teamId) {
            var unread = teamUnreads[teamId] ?? TeamUnread(teamId: teamId)
            unread.msgCount += 1
            if post.rootId.isEmpty { unread.msgCountRoot += 1 }
            if mentioned { unread.mentionCount += 1 }
            teamUnreads[teamId] = unread
        }
        receive(post: post)
        applyFollowers(event, post: post, mentioned: mentioned)
        if event.data["set_online"]?.boolValue == true { markActive(userId: post.userId) }
        if channel == nil, teamId.isEmpty || loadedTeams.contains(teamId) {
            Task { await self.refreshChannel(post.channelId) }
        }
        guard fromOthers else { return }
        let channelType = channel?.type ?? ChannelType(rawValue: event.string("channel_type") ?? "") ?? .open
        let viewing = currentChannelId == post.channelId && isAppActive()
        if viewing {
            if !manuallyUnread.contains(post.channelId) {
                Task { await self.markViewed(channelId: post.channelId) }
            }
        } else if channel != nil, var member = members[post.channelId], mentioned || channelType.isDirectOrGroup {
            member.mentionCount += 1
            if post.rootId.isEmpty { member.mentionCountRoot += 1 }
            members[post.channelId] = member
        }
        guard let me else { return }
        let shouldNotify = NotificationPolicy.shouldNotify(
            post: post,
            channelType: channelType,
            mentioned: mentioned,
            me: me,
            member: members[post.channelId],
            myStatus: statuses[myId],
            isViewingChannel: viewing
        )
        guard shouldNotify else { return }
        let sender = event.string("sender_name").flatMap(\.nonEmpty).map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 } ?? displayName(for: post)
        let channelTitle = channel.map { displayName(channel: $0) } ?? event.string("channel_display_name") ?? ""
        let title = channelType == .direct ? sender : channelTitle
        let preview = NotificationPolicy.preview(post.message)
        let body = channelType == .direct ? preview : "\(sender): \(preview)"
        onNotification?(MentionNotification(
            serverId: serverId,
            teamId: teamId.isEmpty ? (currentTeamId ?? "") : teamId,
            channelId: post.channelId,
            postId: post.id,
            rootId: post.rootId,
            title: title,
            body: preview.isEmpty ? "Sent an attachment" : body
        ))
    }

    func handlePostUnread(_ event: WebSocketEvent) {
        let channelId = event.channelId
        guard var member = members[channelId] else { return }
        member.msgCount = event.data["msg_count"]?.intValue ?? member.msgCount
        member.msgCountRoot = event.data["msg_count_root"]?.intValue ?? member.msgCountRoot
        member.mentionCount = event.data["mention_count"]?.intValue ?? member.mentionCount
        member.mentionCountRoot = event.data["mention_count_root"]?.intValue ?? member.mentionCountRoot
        member.urgentMentionCount = event.data["urgent_mention_count"]?.intValue ?? member.urgentMentionCount
        member.lastViewedAt = event.data["last_viewed_at"]?.doubleValue.map { Int64(clamping: $0) } ?? member.lastViewedAt
        members[channelId] = member
    }

    func viewedElsewhere(_ channelIds: [String]) {
        var unknown = false
        for channelId in channelIds {
            if members[channelId] != nil && channels[channelId] != nil {
                markLocallyViewed(channelId)
            } else {
                unknown = true
            }
        }
        if unknown { Task { await self.refreshTeamUnreads() } }
    }

    func markLocallyViewed(_ channelId: String) {
        guard let channel = channels[channelId], var member = members[channelId] else { return }
        member.msgCount = channel.totalMsgCount
        member.msgCountRoot = channel.totalMsgCountRoot
        member.mentionCount = 0
        member.mentionCountRoot = 0
        member.urgentMentionCount = 0
        member.lastViewedAt = max(member.lastViewedAt, channel.lastPostAt)
        members[channelId] = member
    }

    func refreshChannel(_ channelId: String) async {
        guard !channelId.isEmpty else { return }
        do {
            async let channelRequest = client.channel(id: channelId)
            async let memberRequest = client.channelMember(channelId: channelId)
            let (channel, member) = try await (channelRequest, memberRequest)
            channels[channelId] = channel
            members[channelId] = member
            if let partner = channel.directPartnerId(me: myId) { await ensureUsers([partner]) }
            let teamIds = channel.teamId.isEmpty ? Array(loadedTeams) : [channel.teamId]
            for teamId in teamIds where loadedTeams.contains(teamId) {
                _ = await quietly { try await refreshCategories(teamId: teamId) }
            }
        } catch {
            report(error, silently: true)
        }
    }

    func refreshTeams() async {
        guard let list = await quietly({ try await client.myTeams() }) else { return }
        teams = Self.sortedTeams(list)
        await refreshTeamUnreads()
        let remaining = Set(teams.map(\.id))
        loadedTeams = loadedTeams.intersection(remaining)
        if let teamId = currentTeamId, !remaining.contains(teamId) {
            if let first = orderedTeams.first {
                await selectTeam(first.id)
            } else {
                currentTeamId = nil
                currentChannelId = nil
                onSelectionChange?(nil, nil)
            }
        }
    }
}
