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

    func handle(realtime event: RealtimeEvent) async {
        switch event {
        case .connected(let needsResync):
            connection = .connected
            if needsResync { await resync() }
        case .disconnected:
            if connection != .unauthorized { connection = .reconnecting }
        case .event(let event):
            apply(event)
        }
    }

    func resync() async {
        do {
            try await loadInitial()
        } catch let error as APIError where error.isUnauthorized {
            connection = .unauthorized
            onUnauthorized?()
        } catch {
            lastError = APIError.wrap(error).localizedDescription
        }
    }

    public func apply(_ event: WebSocketEvent) {
        switch event.event {
        case WebSocketEventType.posted:
            handlePosted(event)
        case WebSocketEventType.postEdited:
            if let post = event.embedded(Post.self, "post") {
                if posts[post.id] != nil || timelines[post.channelId]?.loaded == true {
                    var merged = post
                    if let old = posts[post.id], merged.metadata.reactions.isEmpty { merged.metadata.reactions = old.metadata.reactions }
                    posts[post.id] = merged
                }
            }
        case WebSocketEventType.postDeleted:
            if let post = event.embedded(Post.self, "post") { removePost(post.id) }
        case WebSocketEventType.reactionAdded, WebSocketEventType.reactionRemoved:
            if let reaction = event.embedded(Reaction.self, "reaction") {
                applyReaction(reaction, added: event.event == WebSocketEventType.reactionAdded)
            }
        case WebSocketEventType.typing:
            let userId = event.string("user_id") ?? ""
            guard !userId.isEmpty else { return }
            let key = typingKey(channelId: event.channelId, parentId: event.string("parent_id") ?? "")
            typing[key, default: [:]][userId] = now()
            if users[userId] == nil { Task { await self.ensureUsers([userId]) } }
        case WebSocketEventType.channelViewed:
            if let channelId = event.string("channel_id") { markLocallyViewed(channelId) }
        case WebSocketEventType.multipleChannelsViewed:
            for channelId in (event.data["channel_times"]?.objectValue ?? [:]).keys { markLocallyViewed(channelId) }
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
                channel.deleteAt = Int64(event.data["delete_at"]?.doubleValue ?? Double(now().mattermostMillis))
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
        case WebSocketEventType.addedToTeam, WebSocketEventType.leaveTeam, WebSocketEventType.updateTeam:
            Task { await self.refreshTeams() }
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
                Task { try? await self.refreshCategories(teamId: teamId) }
            }
        case WebSocketEventType.emojiAdded:
            if let emoji = event.embedded(CustomEmoji.self, "emoji") { customEmojis[emoji.name] = emoji }
        default:
            break
        }
    }

    func handlePosted(_ event: WebSocketEvent) {
        guard let post = event.embedded(Post.self, "post") else { return }
        let isNew = posts[post.id] == nil
        typing[typingKey(channelId: post.channelId, parentId: post.rootId)]?[post.userId] = nil
        if channels[post.channelId] == nil {
            receive(post: post)
            Task { await self.refreshChannel(post.channelId) }
            return
        }
        receive(post: post)
        guard isNew, post.userId != myId else { return }
        let mentions = event.embedded([String].self, "mentions") ?? []
        let mentioned = mentions.contains(myId)
        let channelType = channels[post.channelId]?.type ?? ChannelType(rawValue: event.string("channel_type") ?? "O") ?? .open
        let viewing = currentChannelId == post.channelId && isAppActive()
        if viewing {
            Task { await self.markViewed(channelId: post.channelId) }
        } else if var member = members[post.channelId], mentioned || channelType.isDirectOrGroup {
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
        guard shouldNotify, let channel = channels[post.channelId] else { return }
        let sender = event.string("sender_name").map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 } ?? displayName(for: post)
        let title = channelType == .direct ? sender : displayName(channel: channel)
        let body = channelType == .direct ? NotificationPolicy.preview(post.message) : "\(sender): \(NotificationPolicy.preview(post.message))"
        let teamId = channel.teamId.isEmpty ? (event.string("team_id") ?? currentTeamId ?? "") : channel.teamId
        onNotification?(MentionNotification(serverId: serverId, teamId: teamId, channelId: post.channelId, postId: post.id, rootId: post.rootId, title: title, body: body.isEmpty ? "Sent an attachment" : body))
    }

    func handlePostUnread(_ event: WebSocketEvent) {
        let channelId = event.channelId
        guard var member = members[channelId] else { return }
        member.msgCount = event.data["msg_count"]?.intValue ?? member.msgCount
        member.mentionCount = event.data["mention_count"]?.intValue ?? member.mentionCount
        member.lastViewedAt = Int64(event.data["last_viewed_at"]?.doubleValue ?? Double(member.lastViewedAt))
        members[channelId] = member
    }

    func markLocallyViewed(_ channelId: String) {
        guard let channel = channels[channelId], var member = members[channelId] else { return }
        member.msgCount = channel.totalMsgCount
        member.msgCountRoot = channel.totalMsgCountRoot
        member.mentionCount = 0
        member.mentionCountRoot = 0
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
                try? await refreshCategories(teamId: teamId)
            }
        } catch {
            lastError = APIError.wrap(error).localizedDescription
        }
    }

    func refreshTeams() async {
        guard let list = try? await client.myTeams() else { return }
        teams = list.filter { $0.deleteAt == 0 }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        if let unreads = try? await client.myTeamUnreads() {
            teamUnreads = Dictionary(unreads.map { ($0.teamId, $0) }, uniquingKeysWith: { a, _ in a })
        }
        if let teamId = currentTeamId, !teams.contains(where: { $0.id == teamId }) {
            if let first = teams.first { await selectTeam(first.id) } else { currentTeamId = nil; currentChannelId = nil }
        }
    }
}
