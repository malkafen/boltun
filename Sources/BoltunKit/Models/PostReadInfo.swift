import Foundation

public enum PostPriorityLevel: String, Codable, Sendable, CaseIterable {
    case standard = ""
    case important
    case urgent

    public init(raw: String?) {
        self = PostPriorityLevel(rawValue: raw?.lowercased() ?? "") ?? .standard
    }

    public var isLabelled: Bool { self != .standard }
}

public struct PostPriority: Codable, Hashable, Sendable {
    public var priority: PostPriorityLevel
    public var requestedAck: Bool
    public var persistentNotifications: Bool

    public init(priority: PostPriorityLevel = .standard, requestedAck: Bool = false, persistentNotifications: Bool = false) {
        self.priority = priority
        self.requestedAck = requestedAck
        self.persistentNotifications = persistentNotifications
    }

    enum CodingKeys: String, CodingKey {
        case priority
        case requestedAck = "requested_ack"
        case persistentNotifications = "persistent_notifications"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        priority = PostPriorityLevel(raw: c.optional(.priority))
        requestedAck = c.value(.requestedAck, default: false)
        persistentNotifications = c.value(.persistentNotifications, default: false)
    }

    public var isDefault: Bool { priority == .standard && !requestedAck && !persistentNotifications }
}

public struct PostAcknowledgement: Codable, Hashable, Sendable {
    public var userId: String
    public var postId: String
    public var acknowledgedAt: Int64
    public var channelId: String

    public init(userId: String, postId: String, acknowledgedAt: Int64 = 0, channelId: String = "") {
        self.userId = userId
        self.postId = postId
        self.acknowledgedAt = acknowledgedAt
        self.channelId = channelId
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case postId = "post_id"
        case acknowledgedAt = "acknowledged_at"
        case channelId = "channel_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = c.value(.userId, default: "")
        postId = c.value(.postId, default: "")
        acknowledgedAt = c.int64(.acknowledgedAt)
        channelId = c.value(.channelId, default: "")
    }
}

public enum PostType {
    public static let burnOnRead = "burn_on_read"
}

public enum BurnOnRead {
    public static let acknowledgementWindow: Int64 = 5 * 60 * 1000
    public static let defaultDurationSeconds = 600

    public static func remaining(expireAt: Int64, now: Int64) -> Int64 {
        guard expireAt > 0 else { return 0 }
        return expireAt - now
    }

    public static func isExpired(expireAt: Int64, now: Int64) -> Bool {
        expireAt > 0 && expireAt <= now
    }
}

public extension Post {
    var priority: PostPriority { metadata.priority ?? PostPriority() }

    var priorityLevel: PostPriorityLevel { priority.priority }

    var requestsAcknowledgement: Bool { priority.requestedAck }

    var acknowledgements: [PostAcknowledgement] {
        metadata.acknowledgements.sorted { $0.acknowledgedAt == $1.acknowledgedAt ? $0.userId < $1.userId : $0.acknowledgedAt > $1.acknowledgedAt }
    }

    func acknowledgedAt(by userId: String) -> Int64? {
        metadata.acknowledgements.first { $0.userId == userId }?.acknowledgedAt
    }

    var isBurnOnRead: Bool { type == PostType.burnOnRead }

    var burnOnReadReadDurationMillis: Int64 { Int64(clamping: props["read_duration"]?.doubleValue ?? 0) }

    var burnOnReadExpireAt: Int64 { metadata.expireAt }

    var burnOnReadRevealedBy: [String] { metadata.recipients }

    func isBurnOnReadRevealed(by userId: String) -> Bool {
        guard isBurnOnRead else { return true }
        if self.userId == userId { return true }
        return metadata.expireAt > 0
    }

    func isBurnOnReadConcealed(for userId: String) -> Bool {
        isBurnOnRead && !isBurnOnReadRevealed(by: userId)
    }

    func mergingReadInfo(from old: Post) -> Post {
        guard isBurnOnRead, old.isBurnOnRead else { return self }
        var merged = self
        if merged.message.isEmpty, !old.message.isEmpty { merged.message = old.message }
        if merged.metadata.expireAt == 0 { merged.metadata.expireAt = old.metadata.expireAt }
        if merged.metadata.recipients.isEmpty { merged.metadata.recipients = old.metadata.recipients }
        return merged
    }
}

public struct ClientLicense: Hashable, Sendable {
    public var values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }

    public subscript(key: String) -> String? { values[key] }

    public var isLicensed: Bool { values["IsLicensed"] == "true" }

    public var skuShortName: String { values["SkuShortName"] ?? "" }

    public var tier: Int { Self.tier(sku: skuShortName) }

    public static func tier(sku: String) -> Int {
        switch sku.lowercased() {
        case "professional": return 10
        case "enterprise": return 20
        case "entry", "advanced": return 30
        default: return 0
        }
    }

    public var isMinimumEnterpriseAdvanced: Bool { isLicensed && tier >= Self.tier(sku: "advanced") }
}

public extension ClientConfig {
    var postPriority: Bool { values["PostPriority"] == "true" }
    var postAcknowledgements: Bool { postPriority && values["PostAcknowledgements"] == "true" }
    var allowPersistentNotifications: Bool { postPriority && values["AllowPersistentNotifications"] == "true" }
    var persistentNotificationIntervalMinutes: Int { Int(values["PersistentNotificationIntervalMinutes"] ?? "") ?? 5 }
    var enableBurnOnRead: Bool { values["EnableBurnOnRead"] == "true" && values["FeatureFlagBurnOnRead"] != "false" }
    var burnOnReadDurationSeconds: Int { Int(values["BurnOnReadDurationSeconds"] ?? "") ?? BurnOnRead.defaultDurationSeconds }
    var burnOnReadDurationMinutes: Int { max(0, burnOnReadDurationSeconds / 60) }
}
