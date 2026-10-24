import Foundation

public struct LoginResult: Sendable {
    public var user: User
    public var token: String
}

public enum PostPage: Sendable, Equatable {
    case latest(perPage: Int)
    case before(postId: String, perPage: Int)
    case after(postId: String, perPage: Int)
    case since(Int64)
}

public extension APIClient {
    func ping() async throws -> Bool {
        let result = try await send(StatusOK.self, .get, "system/ping")
        return result.status == "OK"
    }

    func clientConfig() async throws -> ClientConfig {
        let raw = try await send(JSONObject.self, .get, "config/client", query: ["format": "old"])
        return ClientConfig(values: raw.compactMapValues(\.stringValue))
    }

    func login(loginId: String, password: String, mfaToken: String? = nil) async throws -> LoginResult {
        var body = ["login_id": loginId, "password": password, "device_id": ""]
        if let mfaToken, !mfaToken.isEmpty { body["token"] = mfaToken }
        let (data, response) = try await perform(request(.post, "users/login", body: try encode(body)))
        guard let token = response.value(forHTTPHeaderField: "Token"), !token.isEmpty else {
            throw APIError.invalidResponse
        }
        do {
            return LoginResult(user: try MattermostJSON.decoder.decode(User.self, from: data), token: token)
        } catch {
            throw APIError.wrap(error)
        }
    }

    func logout() async throws {
        try await sendVoid(.post, "users/logout")
    }

    func me() async throws -> User {
        try await send(User.self, .get, "users/me")
    }

    func myTeams() async throws -> [Team] {
        try await send([Team].self, .get, "users/me/teams")
    }

    func myTeamMembers() async throws -> [TeamMember] {
        try await send([TeamMember].self, .get, "users/me/teams/members")
    }

    func myTeamUnreads() async throws -> [TeamUnread] {
        try await send([TeamUnread].self, .get, "users/me/teams/unread")
    }

    func myChannels(teamId: String) async throws -> [Channel] {
        try await send([Channel].self, .get, "users/me/teams/\(teamId)/channels")
    }

    func myChannelMembers(teamId: String) async throws -> [ChannelMember] {
        try await send([ChannelMember].self, .get, "users/me/teams/\(teamId)/channels/members")
    }

    func myCategories(teamId: String) async throws -> OrderedChannelCategories {
        try await send(OrderedChannelCategories.self, .get, "users/me/teams/\(teamId)/channels/categories")
    }

    func updateCategory(_ category: ChannelCategory) async throws -> ChannelCategory {
        try await send(ChannelCategory.self, .put, "users/me/teams/\(category.teamId)/channels/categories/\(category.id)", json: category)
    }

    func channel(id: String) async throws -> Channel {
        try await send(Channel.self, .get, "channels/\(id)")
    }

    func channelMember(channelId: String) async throws -> ChannelMember {
        try await send(ChannelMember.self, .get, "channels/\(channelId)/members/me")
    }

    func channelStats(channelId: String) async throws -> ChannelStats {
        try await send(ChannelStats.self, .get, "channels/\(channelId)/stats")
    }

    func viewChannel(channelId: String, previousChannelId: String = "") async throws {
        try await sendVoid(.post, "channels/members/me/view", json: ["channel_id": channelId, "prev_channel_id": previousChannelId])
    }

    func createDirectChannel(userIds: [String]) async throws -> Channel {
        try await send(Channel.self, .post, "channels/direct", json: userIds)
    }

    func createGroupChannel(userIds: [String]) async throws -> Channel {
        try await send(Channel.self, .post, "channels/group", json: userIds)
    }

    func autocompleteChannels(teamId: String, name: String) async throws -> [Channel] {
        try await send([Channel].self, .get, "teams/\(teamId)/channels/autocomplete", query: ["name": name])
    }

    func publicChannels(teamId: String, page: Int = 0, perPage: Int = 100) async throws -> [Channel] {
        try await send([Channel].self, .get, "teams/\(teamId)/channels", query: ["page": String(page), "per_page": String(perPage)])
    }

    func joinChannel(channelId: String, userId: String) async throws -> ChannelMember {
        try await send(ChannelMember.self, .post, "channels/\(channelId)/members", json: ["user_id": userId])
    }

    func leaveChannel(channelId: String, userId: String) async throws {
        try await sendVoid(.delete, "channels/\(channelId)/members/\(userId)")
    }

    func posts(channelId: String, page: PostPage, collapsedThreads: Bool = false) async throws -> PostList {
        var query: [String: String] = [:]
        switch page {
        case .latest(let perPage):
            query = ["page": "0", "per_page": String(perPage)]
        case .before(let postId, let perPage):
            query = ["before": postId, "per_page": String(perPage)]
        case .after(let postId, let perPage):
            query = ["after": postId, "per_page": String(perPage)]
        case .since(let time):
            query = ["since": String(time)]
        }
        if collapsedThreads {
            query["collapsedThreads"] = "true"
            query["collapsedThreadsExtended"] = "false"
        }
        return try await send(PostList.self, .get, "channels/\(channelId)/posts", query: query)
    }

    func postThread(postId: String, collapsedThreads: Bool = false) async throws -> PostList {
        let query = collapsedThreads ? ["collapsedThreads": "true", "collapsedThreadsExtended": "false"] : [:]
        return try await send(PostList.self, .get, "posts/\(postId)/thread", query: query)
    }

    func setThreadFollowing(userId: String, teamId: String, threadId: String, following: Bool) async throws {
        try await sendVoid(following ? .put : .delete, "users/\(userId)/teams/\(teamId)/threads/\(threadId)/following")
    }

    func post(id: String) async throws -> Post {
        try await send(Post.self, .get, "posts/\(id)")
    }

    func createPost(channelId: String, message: String, rootId: String = "", fileIds: [String] = [], pendingPostId: String = "") async throws -> Post {
        let body = NewPost(channelId: channelId, message: message, rootId: rootId, fileIds: fileIds, pendingPostId: pendingPostId)
        return try await send(Post.self, .post, "posts", json: body)
    }

    func patchPost(id: String, message: String) async throws -> Post {
        try await send(Post.self, .put, "posts/\(id)/patch", json: ["message": message])
    }

    func deletePost(id: String) async throws {
        try await sendVoid(.delete, "posts/\(id)")
    }

    func pinPost(id: String, pinned: Bool) async throws {
        try await sendVoid(.post, "posts/\(id)/\(pinned ? "pin" : "unpin")")
    }

    @discardableResult
    func markPostUnread(userId: String, postId: String) async throws -> ChannelMember {
        try await send(ChannelMember.self, .post, "users/\(userId)/posts/\(postId)/set_unread", json: ["collapsed_threads_supported": false])
    }

    func addReaction(userId: String, postId: String, emojiName: String) async throws -> Reaction {
        try await send(Reaction.self, .post, "reactions", json: ["user_id": userId, "post_id": postId, "emoji_name": emojiName])
    }

    func removeReaction(userId: String, postId: String, emojiName: String) async throws {
        try await sendVoid(.delete, "users/\(userId)/posts/\(postId)/reactions/\(emojiName)")
    }

    func users(ids: [String]) async throws -> [User] {
        guard !ids.isEmpty else { return [] }
        return try await send([User].self, .post, "users/ids", json: ids)
    }

    func usersByUsernames(_ usernames: [String]) async throws -> [User] {
        guard !usernames.isEmpty else { return [] }
        return try await send([User].self, .post, "users/usernames", json: usernames)
    }

    func autocompleteUsers(name: String, teamId: String? = nil, channelId: String? = nil, limit: Int = 25) async throws -> [User] {
        var query = ["name": name, "limit": String(limit)]
        if let teamId { query["in_team"] = teamId }
        if let channelId { query["in_channel"] = channelId }
        let result = try await send(UserAutocomplete.self, .get, "users/autocomplete", query: query)
        return result.users + result.outOfChannel
    }

    func statuses(userIds: [String]) async throws -> [UserStatus] {
        guard !userIds.isEmpty else { return [] }
        return try await send([UserStatus].self, .post, "users/status/ids", json: userIds)
    }

    func setStatus(userId: String, status: UserStatusValue) async throws {
        try await sendVoid(.put, "users/\(userId)/status", json: ["user_id": userId, "status": status.rawValue])
    }

    func preferences() async throws -> [Preference] {
        try await send([Preference].self, .get, "users/me/preferences")
    }

    func savePreferences(userId: String, _ preferences: [Preference]) async throws {
        try await sendVoid(.put, "users/\(userId)/preferences", json: preferences)
    }

    func searchPosts(teamId: String, terms: String, page: Int = 0, perPage: Int = 40) async throws -> PostSearchResults {
        let body = SearchRequest(terms: terms, isOrSearch: false, timeZoneOffset: TimeZone.current.secondsFromGMT(), page: page, perPage: perPage)
        return try await send(PostSearchResults.self, .post, "teams/\(teamId)/posts/search", json: body)
    }

    func flaggedPosts(userId: String, page: Int = 0, perPage: Int = 60) async throws -> PostList {
        try await send(PostList.self, .get, "users/\(userId)/posts/flagged", query: ["page": String(page), "per_page": String(perPage)])
    }

    func pinnedPosts(channelId: String) async throws -> PostList {
        try await send(PostList.self, .get, "channels/\(channelId)/pinned")
    }

    func customEmoji(name: String) async throws -> CustomEmoji {
        try await send(CustomEmoji.self, .get, "emoji/name/\(name)")
    }

    func customEmojis(page: Int = 0, perPage: Int = 200) async throws -> [CustomEmoji] {
        try await send([CustomEmoji].self, .get, "emoji", query: ["page": String(page), "per_page": String(perPage), "sort": "name"])
    }

    func uploadFile(channelId: String, filename: String, data: Data, mimeType: String = "application/octet-stream") async throws -> FileInfo {
        let boundary = "boltun-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"channel_id\"\r\n\r\n\(channelId)\r\n")
        let safeName = filename.replacingOccurrences(of: "\"", with: "_")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(safeName)\"\r\nContent-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        let request = request(.post, "files", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
        let result = try await decode(FileUploadResponse.self, request)
        guard let info = result.fileInfos.first else { throw APIError.invalidResponse }
        return info
    }

    func fileURL(id: String) -> URL { url("files/\(id)") }

    func fileThumbnailURL(id: String) -> URL { url("files/\(id)/thumbnail") }

    func filePreviewURL(id: String) -> URL { url("files/\(id)/preview") }

    func profileImageURL(userId: String, lastPictureUpdate: Int64 = 0) -> URL {
        url("users/\(userId)/image", query: lastPictureUpdate > 0 ? ["_": String(lastPictureUpdate)] : [:])
    }

    func customEmojiImageURL(id: String) -> URL { url("emoji/\(id)/image") }

    func teamIconURL(teamId: String, lastIconUpdate: Int64 = 0) -> URL {
        url("teams/\(teamId)/image", query: lastIconUpdate > 0 ? ["_": String(lastIconUpdate)] : [:])
    }
}

struct NewPost: Encodable {
    var channelId: String
    var message: String
    var rootId: String
    var fileIds: [String]
    var pendingPostId: String

    enum CodingKeys: String, CodingKey {
        case message
        case channelId = "channel_id"
        case rootId = "root_id"
        case fileIds = "file_ids"
        case pendingPostId = "pending_post_id"
    }
}

struct SearchRequest: Encodable {
    var terms: String
    var isOrSearch: Bool
    var timeZoneOffset: Int
    var page: Int
    var perPage: Int

    enum CodingKeys: String, CodingKey {
        case terms, page
        case isOrSearch = "is_or_search"
        case timeZoneOffset = "time_zone_offset"
        case perPage = "per_page"
    }
}

struct UserAutocomplete: Decodable {
    var users: [User]
    var outOfChannel: [User]

    enum CodingKeys: String, CodingKey {
        case users
        case outOfChannel = "out_of_channel"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        users = c.value(.users, default: [])
        outOfChannel = c.value(.outOfChannel, default: [])
    }
}

struct FileUploadResponse: Decodable {
    var fileInfos: [FileInfo]

    enum CodingKeys: String, CodingKey {
        case fileInfos = "file_infos"
    }
}
