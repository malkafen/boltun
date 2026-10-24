import Foundation

extension ServerSession {
    public func team(named name: String) -> Team? {
        teams.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            ?? teams.first { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func channel(named name: String, teamId: String) -> Channel? {
        let candidates = channels.values.filter { $0.teamId == teamId || $0.type.isDirectOrGroup }
        return candidates.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            ?? candidates.first { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }
    }

    @discardableResult
    public func open(teamName: String, channelName: String? = nil) async -> Bool {
        guard let team = team(named: teamName) else { return false }
        guard let channelName, !channelName.isEmpty else {
            await selectTeam(team.id, channelId: currentTeamId == team.id ? currentChannelId : nil)
            return currentTeamId == team.id
        }
        guard await ensureTeamLoaded(team.id), let channel = channel(named: channelName, teamId: team.id) else { return false }
        await selectTeam(team.id, channelId: channel.id)
        return currentChannelId == channel.id
    }

    public func openPermalink(postId: String) async -> Post? {
        do {
            let post: Post
            if let cached = posts[postId] {
                post = cached
            } else {
                post = try await client.post(id: postId)
                posts[post.id] = post
            }
            let channel: Channel
            if let cached = channels[post.channelId] {
                channel = cached
            } else {
                channel = try await client.channel(id: post.channelId)
                channels[channel.id] = channel
            }
            if !channel.teamId.isEmpty, channel.teamId != currentTeamId, await ensureTeamLoaded(channel.teamId) {
                await selectTeam(channel.teamId, channelId: channel.id)
            } else {
                await selectChannel(channel.id)
            }
            return post
        } catch {
            report(error)
            return nil
        }
    }

    @discardableResult
    public func openDirect(username: String, teamName: String? = nil) async -> Bool {
        let name = username.hasPrefix("@") ? String(username.dropFirst()) : username
        if let teamName, let team = team(named: teamName), team.id != currentTeamId, await ensureTeamLoaded(team.id) {
            currentTeamId = team.id
        }
        var found = users.values.first { $0.username.caseInsensitiveCompare(name) == .orderedSame }
        if found == nil { found = try? await client.usersByUsernames([name]).first }
        guard let user = found else { return false }
        users[user.id] = user
        await openDirect(userId: user.id)
        return currentChannel?.directPartnerId(me: myId) == user.id
    }

    func ensureTeamLoaded(_ teamId: String) async -> Bool {
        guard teams.contains(where: { $0.id == teamId }) else { return false }
        if loadedTeams.contains(teamId) { return true }
        do {
            try await loadTeam(teamId)
            return true
        } catch {
            report(error)
            return false
        }
    }
}
