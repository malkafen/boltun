import Foundation

extension ServerSession {
    nonisolated static let specialMentions: Set<String> = ["channel", "all", "here"]

    public func channelMembership(channelId: String, userId: String) -> ChannelMember? {
        if userId == myId, let member = members[channelId] { return member }
        return channelRoster[channelId]?[userId]
    }

    public func teamMembership(teamId: String, userId: String) -> TeamMember? {
        teamRoster[teamId]?[userId]
    }

    public func loadProfile(userId: String, channelId: String?) async {
        guard !userId.isEmpty else { return }
        async let profile: Void = refreshProfile(userId)
        async let status: Void = refreshProfileStatus(userId)
        async let team: Void = loadTeamMembership(userId: userId)
        async let channel: Void = loadChannelMembership(channelId: channelId, userId: userId)
        _ = await (profile, status, team, channel)
    }

    func refreshProfile(_ userId: String) async {
        guard refreshedProfileIds.insert(userId).inserted else { return }
        guard let user = await quietly({ try await client.user(id: userId) }) else {
            refreshedProfileIds.remove(userId)
            return
        }
        users[user.id] = user
    }

    func refreshProfileStatus(_ userId: String) async {
        guard config.enableUserStatuses, statuses[userId] == nil || lastActivity[userId] == nil,
              requestedStatusIds.insert(userId).inserted
        else { return }
        await refreshStatuses([userId])
        requestedStatusIds.remove(userId)
    }

    func loadTeamMembership(userId: String) async {
        guard let teamId = currentTeamId, teamMembership(teamId: teamId, userId: userId) == nil,
              requestedMemberships.insert("team:\(teamId):\(userId)").inserted
        else { return }
        guard let member = await quietly({ try await client.teamMember(teamId: teamId, userId: userId) }) else { return }
        teamRoster[teamId, default: [:]][userId] = member
    }

    func loadChannelMembership(channelId: String?, userId: String) async {
        guard let channelId, !channelId.isEmpty, channelMembership(channelId: channelId, userId: userId) == nil,
              requestedMemberships.insert("channel:\(channelId):\(userId)").inserted
        else { return }
        guard let member = await quietly({ try await client.channelMember(channelId: channelId, userId: userId) }) else { return }
        channelRoster[channelId, default: [:]][userId] = member
    }

    public func loadChannelMembers(channelId: String, page: Int, perPage: Int) async -> [User]? {
        guard let profiles = await quietly({ try await client.profilesInChannel(channelId: channelId, page: page, perPage: perPage) }) else { return nil }
        await storeChannelProfiles(profiles, channelId: channelId)
        return profiles
    }

    public func searchChannelMembers(channelId: String, term: String) async -> [User]? {
        guard let found = await quietly({ try await client.searchUsers(term: term, channelId: channelId) }) else { return nil }
        await storeChannelProfiles(found, channelId: channelId)
        return found
    }

    func storeChannelProfiles(_ profiles: [User], channelId: String) async {
        for user in profiles where users[user.id] != user { users[user.id] = user }
        refreshedProfileIds.formUnion(profiles.map(\.id))
        let ids = profiles.map(\.id)
        async let roster: Void = loadRoster(channelId: channelId, userIds: ids)
        async let presence: Void = config.enableUserStatuses ? refreshStatuses(ids) : ()
        _ = await (roster, presence)
    }

    func loadRoster(channelId: String, userIds: [String]) async {
        guard !userIds.isEmpty, let list = await quietly({ try await client.channelMembers(channelId: channelId, userIds: userIds) }) else { return }
        var roster = channelRoster[channelId] ?? [:]
        for member in list { roster[member.userId] = member }
        channelRoster[channelId] = roster
    }

    func applyRosterChange(_ member: ChannelMember) {
        guard channelRoster[member.channelId] != nil else { return }
        channelRoster[member.channelId]?[member.userId] = member
    }

    func removeFromRoster(channelId: String, userId: String) {
        guard channelRoster[channelId]?[userId] != nil else { return }
        channelRoster[channelId]?[userId] = nil
    }

    public func user(mentionName: String) async -> User? {
        let candidates = Self.mentionCandidates(mentionName)
        guard !candidates.isEmpty else { return nil }
        if let cached = cachedUser(usernames: candidates) { return cached }
        guard let fetched = await quietly({ try await client.usersByUsernames(candidates) }) else { return nil }
        for user in fetched { users[user.id] = user }
        return cachedUser(usernames: candidates)
    }

    func cachedUser(usernames: [String]) -> User? {
        let all = Array(users.values)
        for name in usernames {
            if let user = all.first(where: { $0.username.lowercased() == name }) { return user }
        }
        return nil
    }

    nonisolated static func mentionCandidates(_ name: String) -> [String] {
        var current = name.lowercased()
        if current.hasPrefix("@") { current.removeFirst() }
        var result: [String] = []
        while !current.isEmpty {
            if specialMentions.contains(current) { return result }
            result.append(current)
            guard let last = current.last, ".-_".contains(last) else { break }
            current.removeLast()
        }
        return result
    }
}
