import Foundation

public struct Reaction: Codable, Hashable, Sendable {
    public var userId: String
    public var postId: String
    public var emojiName: String
    public var createAt: Int64

    public init(userId: String, postId: String, emojiName: String, createAt: Int64 = 0) {
        self.userId = userId
        self.postId = postId
        self.emojiName = emojiName
        self.createAt = createAt
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case postId = "post_id"
        case emojiName = "emoji_name"
        case createAt = "create_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = c.value(.userId, default: "")
        postId = c.value(.postId, default: "")
        emojiName = c.value(.emojiName, default: "")
        createAt = c.int64(.createAt)
    }
}

public struct FileInfo: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var postId: String
    public var name: String
    public var `extension`: String
    public var size: Int64
    public var mimeType: String
    public var width: Int
    public var height: Int
    public var hasPreviewImage: Bool
    public var userId: String
    public var channelId: String
    public var createAt: Int64

    public init(
        id: String,
        postId: String = "",
        name: String,
        extension: String = "",
        size: Int64 = 0,
        mimeType: String = "",
        width: Int = 0,
        height: Int = 0,
        hasPreviewImage: Bool = false,
        userId: String = "",
        channelId: String = "",
        createAt: Int64 = 0
    ) {
        self.id = id
        self.postId = postId
        self.name = name
        self.extension = `extension`
        self.size = size
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.hasPreviewImage = hasPreviewImage
        self.userId = userId
        self.channelId = channelId
        self.createAt = createAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, `extension`, size, width, height
        case postId = "post_id"
        case mimeType = "mime_type"
        case hasPreviewImage = "has_preview_image"
        case userId = "user_id"
        case channelId = "channel_id"
        case createAt = "create_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        postId = c.value(.postId, default: "")
        name = c.value(.name, default: "")
        `extension` = c.value(.extension, default: "")
        size = c.int64(.size)
        mimeType = c.value(.mimeType, default: "")
        width = c.int(.width)
        height = c.int(.height)
        hasPreviewImage = c.value(.hasPreviewImage, default: false)
        userId = c.value(.userId, default: "")
        channelId = c.value(.channelId, default: "")
        createAt = c.int64(.createAt)
    }

    public var isImage: Bool {
        mimeType.hasPrefix("image/") || ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"].contains(`extension`.lowercased())
    }
}

public struct CustomEmoji: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var creatorId: String

    public init(id: String, name: String, creatorId: String = "") {
        self.id = id
        self.name = name
        self.creatorId = creatorId
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case creatorId = "creator_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.value(.name, default: "")
        creatorId = c.value(.creatorId, default: "")
    }
}

public struct PostEmbed: Codable, Hashable, Sendable {
    public var type: String
    public var url: String

    public init(type: String, url: String) {
        self.type = type
        self.url = url
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = c.value(.type, default: "")
        url = c.value(.url, default: "")
    }
}

public struct PostMetadata: Codable, Hashable, Sendable {
    public var files: [FileInfo]
    public var reactions: [Reaction]
    public var emojis: [CustomEmoji]
    public var embeds: [PostEmbed]
    public var priority: PostPriority?
    public var acknowledgements: [PostAcknowledgement]
    public var recipients: [String]
    public var expireAt: Int64

    public init(
        files: [FileInfo] = [],
        reactions: [Reaction] = [],
        emojis: [CustomEmoji] = [],
        embeds: [PostEmbed] = [],
        priority: PostPriority? = nil,
        acknowledgements: [PostAcknowledgement] = [],
        recipients: [String] = [],
        expireAt: Int64 = 0
    ) {
        self.files = files
        self.reactions = reactions
        self.emojis = emojis
        self.embeds = embeds
        self.priority = priority
        self.acknowledgements = acknowledgements
        self.recipients = recipients
        self.expireAt = expireAt
    }

    enum CodingKeys: String, CodingKey {
        case files, reactions, emojis, embeds, priority, acknowledgements, recipients
        case expireAt = "expire_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        files = c.value(.files, default: [])
        reactions = c.value(.reactions, default: [])
        emojis = c.value(.emojis, default: [])
        embeds = c.value(.embeds, default: [])
        priority = c.optional(.priority)
        acknowledgements = c.value(.acknowledgements, default: [])
        recipients = c.value(.recipients, default: [])
        expireAt = c.int64(.expireAt)
    }
}

public struct Post: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var createAt: Int64
    public var updateAt: Int64
    public var editAt: Int64
    public var deleteAt: Int64
    public var isPinned: Bool
    public var userId: String
    public var channelId: String
    public var rootId: String
    public var message: String
    public var type: String
    public var props: JSONObject
    public var hashtags: String
    public var fileIds: [String]
    public var pendingPostId: String
    public var replyCount: Int
    public var lastReplyAt: Int64
    public var participantIds: [String]
    public var isFollowing: Bool?
    public var metadata: PostMetadata

    public init(
        id: String,
        createAt: Int64 = 0,
        updateAt: Int64 = 0,
        editAt: Int64 = 0,
        deleteAt: Int64 = 0,
        isPinned: Bool = false,
        userId: String,
        channelId: String,
        rootId: String = "",
        message: String,
        type: String = "",
        props: JSONObject = [:],
        hashtags: String = "",
        fileIds: [String] = [],
        pendingPostId: String = "",
        replyCount: Int = 0,
        lastReplyAt: Int64 = 0,
        participantIds: [String] = [],
        isFollowing: Bool? = nil,
        metadata: PostMetadata = PostMetadata()
    ) {
        self.id = id
        self.createAt = createAt
        self.updateAt = updateAt
        self.editAt = editAt
        self.deleteAt = deleteAt
        self.isPinned = isPinned
        self.userId = userId
        self.channelId = channelId
        self.rootId = rootId
        self.message = message
        self.type = type
        self.props = props
        self.hashtags = hashtags
        self.fileIds = fileIds
        self.pendingPostId = pendingPostId
        self.replyCount = replyCount
        self.lastReplyAt = lastReplyAt
        self.participantIds = participantIds
        self.isFollowing = isFollowing
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id, message, type, props, hashtags, metadata
        case createAt = "create_at"
        case updateAt = "update_at"
        case editAt = "edit_at"
        case deleteAt = "delete_at"
        case isPinned = "is_pinned"
        case userId = "user_id"
        case channelId = "channel_id"
        case rootId = "root_id"
        case fileIds = "file_ids"
        case pendingPostId = "pending_post_id"
        case replyCount = "reply_count"
        case lastReplyAt = "last_reply_at"
        case participantIds = "participants"
        case isFollowing = "is_following"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createAt = c.int64(.createAt)
        updateAt = c.int64(.updateAt)
        editAt = c.int64(.editAt)
        deleteAt = c.int64(.deleteAt)
        isPinned = c.value(.isPinned, default: false)
        userId = c.value(.userId, default: "")
        channelId = c.value(.channelId, default: "")
        rootId = c.value(.rootId, default: "")
        message = c.value(.message, default: "")
        type = c.value(.type, default: "")
        props = c.value(.props, default: [:])
        hashtags = c.value(.hashtags, default: "")
        fileIds = c.value(.fileIds, default: [])
        pendingPostId = c.value(.pendingPostId, default: "")
        replyCount = c.int(.replyCount)
        lastReplyAt = c.int64(.lastReplyAt)
        participantIds = Self.decodeParticipants(c)
        isFollowing = try? c.decodeIfPresent(Bool.self, forKey: .isFollowing)
        metadata = c.value(.metadata, default: PostMetadata())
    }

    static func decodeParticipants(_ c: KeyedDecodingContainer<CodingKeys>) -> [String] {
        if let users = try? c.decodeIfPresent([ParticipantReference].self, forKey: .participantIds) {
            return users.map(\.id).filter { !$0.isEmpty }
        }
        return c.value(.participantIds, default: [])
    }

    public func mergingThreadSummary(from old: Post) -> Post {
        var merged = self
        if merged.participantIds.isEmpty { merged.participantIds = old.participantIds }
        if merged.isFollowing == nil { merged.isFollowing = old.isFollowing }
        if merged.replyCount == 0 && merged.lastReplyAt == 0 {
            merged.replyCount = old.replyCount
            merged.lastReplyAt = old.lastReplyAt
        }
        return merged
    }

    public var isReply: Bool { !rootId.isEmpty }

    public var threadId: String { rootId.isEmpty ? id : rootId }

    public var isSystemMessage: Bool { type.hasPrefix("system_") }

    public var isDeleted: Bool { deleteAt > 0 }

    public var isEdited: Bool { editAt > 0 }

    public var overrideUsername: String? {
        guard props["from_webhook"]?.boolValue == true || props["from_bot"]?.boolValue == true else { return nil }
        return props["override_username"]?.stringValue
    }

    public var attachments: [JSONValue] { props["attachments"]?.arrayValue ?? [] }

    public var reactionSummary: [ReactionSummary] {
        var order: [String] = []
        var users: [String: [String]] = [:]
        for reaction in metadata.reactions.sorted(by: { $0.createAt < $1.createAt }) {
            if users[reaction.emojiName] == nil { order.append(reaction.emojiName) }
            users[reaction.emojiName, default: []].append(reaction.userId)
        }
        return order.map { ReactionSummary(emojiName: $0, userIds: users[$0] ?? []) }
    }
}

struct ParticipantReference: Decodable {
    var id: String
}

public struct ReactionSummary: Hashable, Sendable {
    public var emojiName: String
    public var userIds: [String]

    public init(emojiName: String, userIds: [String]) {
        self.emojiName = emojiName
        self.userIds = userIds
    }

    public var count: Int { userIds.count }
}

public struct PostList: Codable, Hashable, Sendable {
    public var order: [String]
    public var posts: [String: Post]
    public var nextPostId: String
    public var prevPostId: String
    public var hasNext: Bool

    public init(order: [String] = [], posts: [String: Post] = [:], nextPostId: String = "", prevPostId: String = "", hasNext: Bool = false) {
        self.order = order
        self.posts = posts
        self.nextPostId = nextPostId
        self.prevPostId = prevPostId
        self.hasNext = hasNext
    }

    enum CodingKeys: String, CodingKey {
        case order, posts
        case nextPostId = "next_post_id"
        case prevPostId = "prev_post_id"
        case hasNext = "has_next"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = c.value(.order, default: [])
        posts = c.value(.posts, default: [:])
        nextPostId = c.value(.nextPostId, default: "")
        prevPostId = c.value(.prevPostId, default: "")
        hasNext = c.value(.hasNext, default: false)
    }

    public var orderedPosts: [Post] { order.compactMap { posts[$0] } }
}

public struct PostSearchResults: Codable, Hashable, Sendable {
    public var order: [String]
    public var posts: [String: Post]
    public var hasNext: Bool

    public init(order: [String] = [], posts: [String: Post] = [:], hasNext: Bool = false) {
        self.order = order
        self.posts = posts
        self.hasNext = hasNext
    }

    enum CodingKeys: String, CodingKey {
        case order, posts
        case hasNext = "has_next"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = c.value(.order, default: [])
        posts = c.value(.posts, default: [:])
        hasNext = c.value(.hasNext, default: false)
    }

    public var orderedPosts: [Post] { order.compactMap { posts[$0] } }
}
