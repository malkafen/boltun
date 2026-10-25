import Foundation

extension ServerSession {
    public func isQuiet(channelId: String) -> Bool {
        guard let channel = channels[channelId] else { return false }
        if members[channelId]?.isMuted == true { return true }
        return !channel.type.isDirectOrGroup && !channel.teamId.isEmpty && isMuted(teamId: channel.teamId)
    }

    func isPersonalMention(_ post: Post) -> Bool {
        guard let me, post.userId != me.id, !post.isSystemMessage, !post.isDeleted else { return false }
        return ChannelMention.mentionsUser(post.message, user: me)
    }

    func quietUnread(channelId: String, base: ChannelUnread) -> ChannelUnread {
        guard isQuiet(channelId: channelId) else { return base }
        return ChannelUnread(unread: false, mentions: base.mentions > 0 ? (quietMentions[channelId] ?? 0) : 0)
    }

    func refreshQuietMentions() async {
        let targets = members.keys.filter { id in
            quietMentions[id] == nil && (members[id]?.mentionCount ?? 0) > 0 && isQuiet(channelId: id)
        }
        await withTaskGroup(of: Void.self) { group in
            for channelId in targets {
                group.addTask { await self.refreshQuietMentions(channelId: channelId) }
            }
        }
    }

    func refreshQuietMentions(channelId: String) async {
        guard let member = members[channelId], member.mentionCount > 0, isQuiet(channelId: channelId) else { return }
        guard quietMentionRequests.insert(channelId).inserted else { return }
        defer { quietMentionRequests.remove(channelId) }
        let since = member.lastViewedAt
        guard let list = await quietly({ try await client.posts(channelId: channelId, page: .since(since)) }) else { return }
        guard members[channelId]?.lastViewedAt == since else { return }
        quietMentions[channelId] = list.posts.values.filter { $0.createAt > since && isPersonalMention($0) }.count
    }

    func clearQuietMentions(channelId: String) {
        if quietMentions[channelId] != nil { quietMentions[channelId] = nil }
    }

    func resetQuietMentions(channelId: String) {
        clearQuietMentions(channelId: channelId)
        guard isQuiet(channelId: channelId), (members[channelId]?.mentionCount ?? 0) > 0 else { return }
        Task { await self.refreshQuietMentions(channelId: channelId) }
    }

    func resetQuietMentions(teamId: String) {
        for (id, channel) in channels where channel.teamId == teamId { clearQuietMentions(channelId: id) }
        Task {
            await self.loadRemainingTeams()
            await self.refreshQuietMentions()
        }
    }

    func shouldPreload(teamId: String) -> Bool {
        preloadsTeams || (isMuted(teamId: teamId) && (teamUnreads[teamId]?.mentionCount ?? 0) > 0)
    }

    func loadRemainingTeams() async {
        guard !loadingRemainingTeams else { return }
        loadingRemainingTeams = true
        defer { loadingRemainingTeams = false }
        var failed = Set<String>()
        while let team = teams.first(where: { !loadedTeams.contains($0.id) && !failed.contains($0.id) && shouldPreload(teamId: $0.id) }) {
            do {
                try await loadTeam(team.id)
            } catch {
                failed.insert(team.id)
                report(error, silently: true)
            }
        }
    }

    func trackQuietMention(_ post: Post, teamId: String) {
        guard isPersonalMention(post) else { return }
        guard members[post.channelId] != nil else {
            if !teamId.isEmpty, !loadedTeams.contains(teamId) {
                Task { await self.loadRemainingTeams() }
            }
            return
        }
        guard isQuiet(channelId: post.channelId) else { return }
        quietMentions[post.channelId, default: 0] += 1
    }
}
