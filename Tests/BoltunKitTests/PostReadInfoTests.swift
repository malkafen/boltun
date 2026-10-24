import Foundation
import Testing
@testable import BoltunKit

extension Fixtures {
    static func priority(_ level: String, requestedAck: Bool = false, persistent: Bool = false) -> [String: Any] {
        ["priority": level, "requested_ack": requestedAck, "persistent_notifications": persistent]
    }

    static func acknowledgement(user: String, post: String, at: Int64, channel: String = "c-town") -> [String: Any] {
        ["user_id": user, "post_id": post, "acknowledged_at": at, "channel_id": channel]
    }

    static func readInfoPost(
        _ id: String,
        channel: String = "c-town",
        user: String,
        message: String,
        createAt: Int64,
        updateAt: Int64? = nil,
        type: String = "",
        priority: [String: Any]? = nil,
        acknowledgements: [[String: Any]] = [],
        recipients: [String]? = nil,
        expireAt: Int64? = nil,
        readDuration: Int64? = nil
    ) -> [String: Any] {
        var post = Fixtures.post(id, channel: channel, user: user, message: message, createAt: createAt, updateAt: updateAt, type: type)
        var metadata = post["metadata"] as? [String: Any] ?? [:]
        if let priority { metadata["priority"] = priority }
        if !acknowledgements.isEmpty { metadata["acknowledgements"] = acknowledgements }
        if let recipients { metadata["recipients"] = recipients }
        if let expireAt { metadata["expire_at"] = expireAt }
        post["metadata"] = metadata
        if let readDuration {
            post["props"] = ["read_duration": readDuration, "expire_at": createAt + 604_800_000]
        }
        return post
    }

    static var licensedConfig: [String: String] { [
        "PostPriority": "true",
        "PostAcknowledgements": "true",
        "AllowPersistentNotifications": "true",
        "PersistentNotificationIntervalMinutes": "5",
        "EnableBurnOnRead": "true",
        "FeatureFlagBurnOnRead": "true",
        "BurnOnReadDurationSeconds": "600",
    ] }

    static var entryLicense: [String: String] { ["IsLicensed": "true", "SkuShortName": "entry"] }
}

@Suite struct PostReadInfoDecodingTests {
    @Test func priorityMetadataDecodes() throws {
        let raw = Fixtures.readInfoPost("p1", user: "u2", message: "hi", createAt: 1, priority: Fixtures.priority("urgent", requestedAck: true, persistent: true))
        let post = try Fixtures.decode(Post.self, raw)
        #expect(post.priorityLevel == .urgent)
        #expect(post.requestsAcknowledgement)
        #expect(post.priority.persistentNotifications)
        #expect(!post.priority.isDefault)
    }

    @Test func priorityDefaultsWhenMissingOrUnknown() throws {
        let plain = try Fixtures.decode(Post.self, Fixtures.post("p1", channel: "c", user: "u", message: "x", createAt: 1))
        #expect(plain.metadata.priority == nil)
        #expect(plain.priorityLevel == .standard)
        #expect(!plain.requestsAcknowledgement)
        let odd = try Fixtures.decode(Post.self, Fixtures.readInfoPost("p2", user: "u", message: "x", createAt: 1, priority: ["priority": "whatever"]))
        #expect(odd.priorityLevel == .standard)
        #expect(odd.priority.isDefault)
        let empty = try Fixtures.decode(Post.self, Fixtures.readInfoPost("p3", user: "u", message: "x", createAt: 1, priority: ["requested_ack": true]))
        #expect(empty.priorityLevel == .standard)
        #expect(empty.requestsAcknowledgement)
    }

    @Test func serverEchoesPriorityWithExtraFields() throws {
        var priority = Fixtures.priority("important")
        priority["PostId"] = "p1"
        priority["ChannelId"] = "c-town"
        let post = try Fixtures.decode(Post.self, Fixtures.readInfoPost("p1", user: "u2", message: "hi", createAt: 1, priority: priority))
        #expect(post.priorityLevel == .important)
    }

    @Test func priorityRoundTripsThroughEncoding() throws {
        let priority = PostPriority(priority: .urgent, requestedAck: true, persistentNotifications: true)
        let data = try MattermostJSON.encoder.encode(priority)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["priority"] as? String == "urgent")
        #expect(json["requested_ack"] as? Bool == true)
        #expect(json["persistent_notifications"] as? Bool == true)
        #expect(try MattermostJSON.decoder.decode(PostPriority.self, from: data) == priority)
        let standard = try MattermostJSON.encoder.encode(PostPriority())
        #expect(try #require(try JSONSerialization.jsonObject(with: standard) as? [String: Any])["priority"] as? String == "")
    }

    @Test func acknowledgementsDecodeAndSortNewestFirst() throws {
        let raw = Fixtures.readInfoPost("p1", user: "u2", message: "hi", createAt: 1, priority: Fixtures.priority("", requestedAck: true), acknowledgements: [
            Fixtures.acknowledgement(user: "u3", post: "p1", at: 10),
            Fixtures.acknowledgement(user: "me1", post: "p1", at: 30),
            Fixtures.acknowledgement(user: "u4", post: "p1", at: 20),
        ])
        let post = try Fixtures.decode(Post.self, raw)
        #expect(post.metadata.acknowledgements.count == 3)
        #expect(post.acknowledgements.map(\.userId) == ["me1", "u4", "u3"])
        #expect(post.acknowledgedAt(by: "me1") == 30)
        #expect(post.acknowledgedAt(by: "nobody") == nil)
        let first = try #require(post.acknowledgements.first)
        #expect(first.channelId == "c-town")
        #expect(first.postId == "p1")
    }

    @Test func acknowledgementsTieBreakOnUserId() {
        let post = Post(id: "p", userId: "u", channelId: "c", message: "", metadata: PostMetadata(acknowledgements: [
            PostAcknowledgement(userId: "zoe", postId: "p", acknowledgedAt: 5),
            PostAcknowledgement(userId: "amy", postId: "p", acknowledgedAt: 5),
        ]))
        #expect(post.acknowledgements.map(\.userId) == ["amy", "zoe"])
    }

    @Test func burnOnReadMetadataDecodes() throws {
        let raw = Fixtures.readInfoPost("b1", user: "u2", message: "secret", createAt: 1, type: "burn_on_read", expireAt: 9_000, readDuration: 600_000)
        let post = try Fixtures.decode(Post.self, raw)
        #expect(post.isBurnOnRead)
        #expect(post.burnOnReadExpireAt == 9_000)
        #expect(post.burnOnReadReadDurationMillis == 600_000)
        #expect(post.isBurnOnReadRevealed(by: "me1"))
        #expect(!post.isBurnOnReadConcealed(for: "me1"))
        let concealed = try Fixtures.decode(Post.self, Fixtures.readInfoPost("b2", user: "u2", message: "", createAt: 1, type: "burn_on_read", readDuration: 600_000))
        #expect(concealed.isBurnOnReadConcealed(for: "me1"))
        #expect(concealed.isBurnOnReadRevealed(by: "u2"))
        #expect(!concealed.isBurnOnReadConcealed(for: "u2"))
    }

    @Test func recipientsDecodeForAuthor() throws {
        let raw = Fixtures.readInfoPost("b1", user: "me1", message: "secret", createAt: 1, type: "burn_on_read", recipients: ["u2", "u3"])
        let post = try Fixtures.decode(Post.self, raw)
        #expect(post.burnOnReadRevealedBy == ["u2", "u3"])
    }

    @Test func plainPostsAreNeverConcealed() {
        let post = Post(id: "p", userId: "u2", channelId: "c", message: "")
        #expect(!post.isBurnOnRead)
        #expect(post.isBurnOnReadRevealed(by: "me1"))
        #expect(!post.isBurnOnReadConcealed(for: "me1"))
        #expect(post.mergingReadInfo(from: Post(id: "p", userId: "u2", channelId: "c", message: "old")).message.isEmpty)
    }

    @Test func mergingReadInfoKeepsRevealedContent() {
        let revealed = Post(
            id: "b1",
            userId: "u2",
            channelId: "c",
            message: "secret",
            type: "burn_on_read",
            metadata: PostMetadata(recipients: ["me1"], expireAt: 500)
        )
        let concealed = Post(id: "b1", userId: "u2", channelId: "c", message: "", type: "burn_on_read")
        let merged = concealed.mergingReadInfo(from: revealed)
        #expect(merged.message == "secret")
        #expect(merged.metadata.expireAt == 500)
        #expect(merged.metadata.recipients == ["me1"])
        var newer = concealed
        newer.message = "edited"
        newer.metadata.expireAt = 900
        let kept = newer.mergingReadInfo(from: revealed)
        #expect(kept.message == "edited")
        #expect(kept.metadata.expireAt == 900)
    }

    @Test func burnOnReadTimerHelpers() {
        #expect(BurnOnRead.remaining(expireAt: 0, now: 100) == 0)
        #expect(BurnOnRead.remaining(expireAt: 1_000, now: 400) == 600)
        #expect(BurnOnRead.remaining(expireAt: 400, now: 1_000) == -600)
        #expect(!BurnOnRead.isExpired(expireAt: 0, now: 100))
        #expect(BurnOnRead.isExpired(expireAt: 100, now: 100))
        #expect(!BurnOnRead.isExpired(expireAt: 101, now: 100))
    }
}

@Suite struct ReadInfoGatingTests {
    @Test func priorityAndAcknowledgementsFollowConfig() {
        #expect(!ClientConfig(values: [:]).postPriority)
        #expect(!ClientConfig(values: [:]).postAcknowledgements)
        let teamEdition = ClientConfig(values: ["PostPriority": "true"])
        #expect(teamEdition.postPriority)
        #expect(!teamEdition.postAcknowledgements)
        #expect(!teamEdition.allowPersistentNotifications)
        let licensed = ClientConfig(values: Fixtures.licensedConfig.merging(["AllowPersistentNotifications": "true"]) { a, _ in a })
        #expect(licensed.postPriority)
        #expect(licensed.postAcknowledgements)
        #expect(licensed.allowPersistentNotifications)
        #expect(licensed.persistentNotificationIntervalMinutes == 5)
        let withoutPriority = ClientConfig(values: ["PostAcknowledgements": "true", "AllowPersistentNotifications": "true"])
        #expect(!withoutPriority.postAcknowledgements)
        #expect(!withoutPriority.allowPersistentNotifications)
        #expect(ClientConfig(values: [:]).persistentNotificationIntervalMinutes == 5)
    }

    @Test func burnOnReadConfigNeedsFlagAndDuration() {
        #expect(!ClientConfig(values: [:]).enableBurnOnRead)
        #expect(ClientConfig(values: ["EnableBurnOnRead": "true"]).enableBurnOnRead)
        #expect(!ClientConfig(values: ["EnableBurnOnRead": "true", "FeatureFlagBurnOnRead": "false"]).enableBurnOnRead)
        #expect(ClientConfig(values: [:]).burnOnReadDurationSeconds == 600)
        #expect(ClientConfig(values: ["BurnOnReadDurationSeconds": "900"]).burnOnReadDurationMinutes == 15)
        #expect(ClientConfig(values: ["BurnOnReadDurationSeconds": "30"]).burnOnReadDurationMinutes == 0)
    }

    @Test func licenseTiersMatchTheWebapp() {
        #expect(ClientLicense.tier(sku: "professional") == 10)
        #expect(ClientLicense.tier(sku: "enterprise") == 20)
        #expect(ClientLicense.tier(sku: "entry") == 30)
        #expect(ClientLicense.tier(sku: "advanced") == 30)
        #expect(ClientLicense.tier(sku: "starter") == 0)
        #expect(!ClientLicense(values: ["IsLicensed": "false"]).isLicensed)
        #expect(!ClientLicense(values: ["IsLicensed": "false", "SkuShortName": "entry"]).isMinimumEnterpriseAdvanced)
        #expect(!ClientLicense(values: ["IsLicensed": "true", "SkuShortName": "professional"]).isMinimumEnterpriseAdvanced)
        let entry = ClientLicense(values: Fixtures.entryLicense)
        #expect(entry.isMinimumEnterpriseAdvanced)
        #expect(entry.skuShortName == "entry")
        #expect(entry["IsLicensed"] == "true")
    }
}

@Suite struct ReadInfoEndpointTests {
    func client(_ transport: FakeTransport) -> APIClient {
        APIClient(baseURL: MockServer.baseURL, token: "t", transport: transport)
    }

    @Test func acknowledgementEndpointsUseUserPostRoutes() async throws {
        let transport = FakeTransport()
        transport.on("POST", "users/me1/posts/p1/ack", object: Fixtures.acknowledgement(user: "me1", post: "p1", at: 42))
        transport.on("DELETE", "users/me1/posts/p1/ack", .ok)
        let client = client(transport)
        let added = try await client.acknowledgePost(userId: "me1", postId: "p1")
        #expect(added == PostAcknowledgement(userId: "me1", postId: "p1", acknowledgedAt: 42, channelId: "c-town"))
        try await client.unacknowledgePost(userId: "me1", postId: "p1")
        #expect(transport.count("POST", "users/me1/posts/p1/ack") == 1)
        #expect(transport.count("DELETE", "users/me1/posts/p1/ack") == 1)
    }

    @Test func revealAndBurnEndpoints() async throws {
        let transport = FakeTransport()
        transport.on("GET", "posts/b1/reveal", object: Fixtures.readInfoPost("b1", user: "u2", message: "secret", createAt: 1, type: "burn_on_read", expireAt: 777))
        transport.on("DELETE", "posts/b1/burn", .ok)
        let client = client(transport)
        let revealed = try await client.revealPost(id: "b1")
        #expect(revealed.message == "secret")
        #expect(revealed.burnOnReadExpireAt == 777)
        try await client.burnPost(id: "b1")
        #expect(transport.count("GET", "posts/b1/reveal") == 1)
        #expect(transport.count("DELETE", "posts/b1/burn") == 1)
    }

    @Test func clientLicenseUsesOldFormat() async throws {
        let transport = FakeTransport()
        transport.on("GET", "license/client", object: ["IsLicensed": "true", "SkuShortName": "entry", "Users": 100])
        let license = try await client(transport).clientLicense()
        #expect(license.isMinimumEnterpriseAdvanced)
        #expect(try #require(transport.last("GET", "license/client")).query["format"] == "old")
    }

    @Test func createPostSendsPriorityAndType() async throws {
        let transport = FakeTransport()
        transport.on("POST", "posts") { request in .object(request.jsonObject, status: 201) }
        let client = client(transport)
        _ = try? await client.createPost(
            channelId: "c",
            message: "urgent",
            priority: PostPriority(priority: .urgent, requestedAck: true),
            postType: PostType.burnOnRead
        )
        let body = try #require(transport.last("POST", "posts")).jsonObject
        #expect(body["type"] as? String == "burn_on_read")
        let metadata = try #require(body["metadata"] as? [String: Any])
        let priority = try #require(metadata["priority"] as? [String: Any])
        #expect(priority["priority"] as? String == "urgent")
        #expect(priority["requested_ack"] as? Bool == true)
        #expect(priority["persistent_notifications"] as? Bool == false)
        _ = try? await client.createPost(channelId: "c", message: "plain")
        let plain = try #require(transport.last("POST", "posts")).jsonObject
        #expect(plain["metadata"] == nil)
        #expect(plain["type"] as? String == "")
    }
}
