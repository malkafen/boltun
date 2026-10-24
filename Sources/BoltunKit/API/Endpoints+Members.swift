import Foundation

public enum ProfilesInChannelSort: String, Sendable {
    case admin
}

public extension APIClient {
    func user(id: String) async throws -> User {
        try await send(User.self, .get, "users/\(id)")
    }

    func teamMember(teamId: String, userId: String) async throws -> TeamMember {
        try await send(TeamMember.self, .get, "teams/\(teamId)/members/\(userId)")
    }

    func channelMember(channelId: String, userId: String) async throws -> ChannelMember {
        try await send(ChannelMember.self, .get, "channels/\(channelId)/members/\(userId)")
    }

    func profilesInChannel(channelId: String, page: Int, perPage: Int, sort: ProfilesInChannelSort = .admin) async throws -> [User] {
        try await send([User].self, .get, "users", query: [
            "in_channel": channelId,
            "page": String(page),
            "per_page": String(perPage),
            "sort": sort.rawValue,
        ])
    }

    func channelMembers(channelId: String, userIds: [String]) async throws -> [ChannelMember] {
        guard !userIds.isEmpty else { return [] }
        return try await send([ChannelMember].self, .post, "channels/\(channelId)/members/ids", json: userIds)
    }

    func searchUsers(term: String, channelId: String) async throws -> [User] {
        try await send([User].self, .post, "users/search", json: ["term": term, "in_channel_id": channelId])
    }
}
