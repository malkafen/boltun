import Foundation
import Testing
@testable import BoltunKit

extension Date {
    static func millis(_ value: Int64) -> Date { Date(timeIntervalSince1970: Double(value) / 1000) }
}

extension MockServer {
    func licensed(sku: String = "entry") {
        transport.on("GET", "config/client", object: Fixtures.clientConfig.merging(Fixtures.licensedConfig) { _, new in new })
        transport.on("GET", "license/client", object: ["IsLicensed": "true", "SkuShortName": sku])
        transport.on("GET", "channels/c-town/stats", object: ["channel_id": "c-town", "member_count": 4, "guest_count": 0, "pinnedpost_count": 0, "files_count": 0])
    }

    func acknowledgements(user: String = "me1", post: String, at: Int64 = 5_000) {
        transport.on("POST", "users/\(user)/posts/\(post)/ack", object: Fixtures.acknowledgement(user: user, post: post, at: at))
        transport.on("DELETE", "users/\(user)/posts/\(post)/ack", .ok)
    }
}

@MainActor
@Suite struct AcknowledgementSessionTests {
    func server() -> MockServer {
        let server = MockServer(pageSize: 10)
        server.licensed()
        server.setPosts("c-town", [
            Fixtures.readInfoPost("ask", user: "u2", message: "please confirm", createAt: 100, priority: Fixtures.priority("urgent", requestedAck: true)),
            Fixtures.readInfoPost("mine", user: "me1", message: "mine", createAt: 200, priority: Fixtures.priority("important", requestedAck: true)),
            Fixtures.post("plain", channel: "c-town", user: "u2", message: "plain", createAt: 300),
        ])
        server.acknowledgements(post: "ask")
        return server
    }

    func started(_ server: MockServer) async -> ServerSession {
        let session = server.session(pageSize: 10)
        await session.start()
        await session.selectTeam("t1", channelId: "c-town")
        #expect(await eventually { session.license.isLicensed })
        return session
    }

    @Test func featureFlagsFollowConfigAndLicense() async {
        let session = await started(server())
        #expect(session.postPriorityEnabled)
        #expect(session.acknowledgementsEnabled)
        #expect(session.persistentNotificationsEnabled)
        #expect(session.burnOnReadEnabled)
        session.config = ClientConfig(values: ["PostPriority": "true"])
        #expect(session.postPriorityEnabled)
        #expect(!session.acknowledgementsEnabled)
        #expect(!session.persistentNotificationsEnabled)
        #expect(!session.burnOnReadEnabled)
        session.stop()
    }

    @Test func licenseFailureLeavesFeaturesOff() async {
        let server = MockServer(pageSize: 10)
        server.transport.on("GET", "license/client", .error(404, message: "no license"))
        let session = await server.startedSession(pageSize: 10)
        await session.loadLicense()
        #expect(!session.license.isLicensed)
        #expect(!session.burnOnReadEnabled)
        #expect(session.lastError == nil)
        session.stop()
    }

    @Test func toggleAcknowledgementAddsAndRemovesMine() async {
        let server = server()
        let session = await started(server)
        session.now = { Date.millis(5_100) }
        #expect(session.canToggleAcknowledgement(postId: "ask"))
        await session.toggleAcknowledgement(postId: "ask")
        #expect(session.posts["ask"]?.acknowledgedAt(by: "me1") == 5_000)
        #expect(session.acknowledgementPeople(postId: "ask").map(\.userId) == ["me1"])
        await session.toggleAcknowledgement(postId: "ask")
        #expect(session.posts["ask"]?.metadata.acknowledgements.isEmpty == true)
        #expect(server.transport.count("POST", "users/me1/posts/ask/ack") == 1)
        #expect(server.transport.count("DELETE", "users/me1/posts/ask/ack") == 1)
        session.stop()
    }

    @Test func removalIsOnlyAllowedInsideTheWindow() async {
        let server = server()
        let session = await started(server)
        session.now = { Date.millis(5_000) }
        await session.toggleAcknowledgement(postId: "ask")
        session.now = { Date.millis(5_000 + BurnOnRead.acknowledgementWindow) }
        #expect(session.canToggleAcknowledgement(postId: "ask"))
        session.now = { Date.millis(5_001 + BurnOnRead.acknowledgementWindow) }
        #expect(!session.canToggleAcknowledgement(postId: "ask"))
        await session.toggleAcknowledgement(postId: "ask")
        #expect(session.posts["ask"]?.acknowledgedAt(by: "me1") == 5_000)
        #expect(server.transport.count("DELETE", "users/me1/posts/ask/ack") == 0)
        session.stop()
    }

    @Test func toggleIgnoresOwnPlainDeletedPendingAndDisabledPosts() async {
        let server = server()
        let session = await started(server)
        #expect(!session.canToggleAcknowledgement(postId: "mine"))
        #expect(!session.canToggleAcknowledgement(postId: "plain"))
        #expect(!session.canToggleAcknowledgement(postId: "missing"))
        session.posts["ask"]?.deleteAt = 10
        #expect(!session.canToggleAcknowledgement(postId: "ask"))
        session.posts["ask"]?.deleteAt = 0
        session.pendingPostIds.insert("ask")
        #expect(!session.canToggleAcknowledgement(postId: "ask"))
        session.pendingPostIds.remove("ask")
        session.config = ClientConfig(values: [:])
        #expect(!session.canToggleAcknowledgement(postId: "ask"))
        session.config = ClientConfig(values: Fixtures.licensedConfig)
        session.me = nil
        #expect(!session.canToggleAcknowledgement(postId: "ask"))
        await session.toggleAcknowledgement(postId: "ask")
        #expect(server.transport.count("POST", "users/me1/posts/ask/ack") == 0)
        #expect(session.acknowledgementPeople(postId: "missing").isEmpty)
        session.stop()
    }

    @Test func failedAcknowledgementReports() async {
        let server = server()
        server.transport.on("POST", "users/me1/posts/ask/ack", .error(403, message: "denied"))
        let session = await started(server)
        await session.toggleAcknowledgement(postId: "ask")
        #expect(session.posts["ask"]?.metadata.acknowledgements.isEmpty == true)
        #expect(session.lastError == "denied")
        session.lastError = nil
        session.posts["ask"]?.metadata.acknowledgements = [PostAcknowledgement(userId: "me1", postId: "ask", acknowledgedAt: 1)]
        session.now = { Date.millis(2) }
        server.transport.on("DELETE", "users/me1/posts/ask/ack", .error(500, message: "nope"))
        await session.toggleAcknowledgement(postId: "ask")
        #expect(session.posts["ask"]?.acknowledgedAt(by: "me1") == 1)
        #expect(session.lastError == "nope")
        session.stop()
    }

    @Test func websocketEventsUpdateAcknowledgements() async {
        let session = await started(server())
        let payload = Fixtures.json(Fixtures.acknowledgement(user: "u3", post: "ask", at: 700))
        session.apply(Fixtures.wsEvent("post_acknowledgement_added", data: ["acknowledgement": payload], channel: "c-town"))
        #expect(session.posts["ask"]?.acknowledgedAt(by: "u3") == 700)
        session.apply(Fixtures.wsEvent("post_acknowledgement_added", data: ["acknowledgement": payload], channel: "c-town"))
        #expect(session.posts["ask"]?.metadata.acknowledgements.count == 1)
        session.apply(Fixtures.wsEvent("post_acknowledgement_removed", data: ["acknowledgement": payload], channel: "c-town"))
        #expect(session.posts["ask"]?.metadata.acknowledgements.isEmpty == true)
        session.apply(Fixtures.wsEvent("post_acknowledgement_added", data: ["acknowledgement": "not json"], channel: "c-town"))
        session.apply(Fixtures.wsEvent("post_acknowledgement_added", data: ["acknowledgement": Fixtures.json(Fixtures.acknowledgement(user: "u3", post: "gone", at: 1))], channel: "c-town"))
        #expect(session.posts["ask"]?.metadata.acknowledgements.isEmpty == true)
        session.stop()
    }

    @Test func acknowledgingUserIsFetched() async {
        let server = server()
        server.users([Fixtures.user("u9", "dave", first: "Dave", last: "Davis")])
        let session = await started(server)
        session.apply(Fixtures.wsEvent("post_acknowledgement_added", data: ["acknowledgement": Fixtures.json(Fixtures.acknowledgement(user: "u9", post: "ask", at: 700))], channel: "c-town"))
        #expect(await eventually { session.users["u9"]?.username == "dave" })
        session.stop()
    }

    @Test func acknowledgementsSurviveRefetchAndAuthorsAreKnown() async {
        let server = server()
        server.updatePost("ask", in: "c-town") { post in
            var updated = post
            var metadata = updated["metadata"] as? [String: Any] ?? [:]
            metadata["acknowledgements"] = [Fixtures.acknowledgement(user: "u3", post: "ask", at: 400)]
            updated["metadata"] = metadata
            return updated
        }
        let session = await started(server)
        #expect(session.posts["ask"]?.acknowledgedAt(by: "u3") == 400)
        #expect(await eventually { session.users["u3"] != nil })
        session.stop()
    }

    @Test func priorityIsSentOnlyForRootPostsAndEnabledFeatures() async throws {
        let server = server()
        server.acceptPosts()
        let session = await started(server)
        let urgent = PostPriority(priority: .urgent, requestedAck: true, persistentNotifications: true)
        #expect(await session.send("now", channelId: "c-town", priority: urgent))
        var metadata = try #require(server.transport.last("POST", "posts")?.jsonObject["metadata"] as? [String: Any])
        var priority = try #require(metadata["priority"] as? [String: Any])
        #expect(priority["priority"] as? String == "urgent")
        #expect(priority["requested_ack"] as? Bool == true)
        #expect(priority["persistent_notifications"] as? Bool == true)

        #expect(await session.send("reply", channelId: "c-town", rootId: "ask", priority: urgent))
        #expect(try #require(server.transport.last("POST", "posts")).jsonObject["metadata"] == nil)

        session.config = ClientConfig(values: ["PostPriority": "true"])
        #expect(await session.send("downgraded", channelId: "c-town", priority: urgent))
        metadata = try #require(server.transport.last("POST", "posts")?.jsonObject["metadata"] as? [String: Any])
        priority = try #require(metadata["priority"] as? [String: Any])
        #expect(priority["requested_ack"] as? Bool == false)
        #expect(priority["persistent_notifications"] as? Bool == false)

        session.config = ClientConfig(values: [:])
        #expect(await session.send("plain", channelId: "c-town", priority: urgent))
        #expect(try #require(server.transport.last("POST", "posts")).jsonObject["metadata"] == nil)
        session.stop()
    }

    @Test func effectivePriorityDropsEmptyAndNonUrgentNotifications() async {
        let session = await started(server())
        #expect(session.effectivePriority(nil, rootId: "") == nil)
        #expect(session.effectivePriority(PostPriority(), rootId: "") == nil)
        #expect(session.effectivePriority(PostPriority(priority: .important, persistentNotifications: true), rootId: "")
            == PostPriority(priority: .important))
        #expect(session.effectivePriority(PostPriority(requestedAck: true), rootId: "") == PostPriority(requestedAck: true))
        session.stop()
    }

    @Test func pendingPriorityPostShowsLabelBeforeConfirmation() async {
        let server = server()
        let gate = Gate()
        server.acceptPosts(gate: gate)
        let session = await started(server)
        async let sent = session.send("wait", channelId: "c-town", priority: PostPriority(priority: .urgent, requestedAck: true))
        #expect(await eventually { session.timelinePosts(channelId: "c-town").last?.priorityLevel == .urgent })
        let pending = session.timelinePosts(channelId: "c-town").last
        #expect(pending?.requestsAcknowledgement == true)
        #expect(session.canToggleAcknowledgement(postId: pending?.id ?? "") == false)
        await gate.open()
        #expect(await sent)
        session.stop()
    }
}

@MainActor
@Suite struct BurnOnReadSessionTests {
    static let incoming = "burn-in"
    static let outgoing = "burn-out"

    func server() -> MockServer {
        let server = MockServer(pageSize: 10)
        server.licensed()
        server.setPosts("c-town", [
            Fixtures.readInfoPost(Self.incoming, user: "u2", message: "", createAt: 100, type: "burn_on_read", readDuration: 600_000),
            Fixtures.readInfoPost(Self.outgoing, user: "me1", message: "mine", createAt: 200, type: "burn_on_read", recipients: [], readDuration: 600_000),
        ])
        server.transport.on("GET", "posts/\(Self.incoming)/reveal", object: Fixtures.readInfoPost(
            Self.incoming, user: "u2", message: "the secret", createAt: 100, type: "burn_on_read", expireAt: 9_000_000, readDuration: 600_000
        ))
        server.transport.on("DELETE", "posts/\(Self.outgoing)/burn", .ok)
        return server
    }

    func started(_ server: MockServer) async -> ServerSession {
        let session = server.session(pageSize: 10)
        session.now = { Date.millis(1_000) }
        await session.start()
        await session.selectTeam("t1", channelId: "c-town")
        #expect(await eventually { session.burnOnReadEnabled })
        return session
    }

    @Test func incomingMessageStaysConcealedUntilRevealed() async {
        let server = server()
        let session = await started(server)
        #expect(session.isConcealed(postId: Self.incoming))
        #expect(!session.isConcealed(postId: Self.outgoing))
        #expect(!session.isRevealing(postId: Self.incoming))
        await session.revealBurnOnRead(postId: Self.incoming)
        #expect(session.posts[Self.incoming]?.message == "the secret")
        #expect(!session.isConcealed(postId: Self.incoming))
        #expect(session.posts[Self.incoming]?.burnOnReadExpireAt == 9_000_000)
        await session.revealBurnOnRead(postId: Self.incoming)
        #expect(server.transport.count("GET", "posts/\(Self.incoming)/reveal") == 1)
        session.stop()
    }

    @Test func revealIsReportedWhenItFails() async {
        let server = server()
        server.transport.on("GET", "posts/\(Self.incoming)/reveal", .error(410, message: "gone"))
        let session = await started(server)
        await session.revealBurnOnRead(postId: Self.incoming)
        #expect(session.lastError == "gone")
        #expect(session.isConcealed(postId: Self.incoming))
        #expect(!session.isRevealing(postId: Self.incoming))
        session.stop()
    }

    @Test func revealSkipsOwnPendingAndPlainPosts() async {
        let server = server()
        let session = await started(server)
        await session.revealBurnOnRead(postId: Self.outgoing)
        await session.revealBurnOnRead(postId: "p1")
        await session.revealBurnOnRead(postId: "missing")
        session.pendingPostIds.insert(Self.incoming)
        await session.revealBurnOnRead(postId: Self.incoming)
        #expect(server.transport.count("GET", "posts/\(Self.incoming)/reveal") == 0)
        session.stop()
    }

    @Test func revealingFlagIsVisibleWhileTheRequestRuns() async {
        let server = server()
        let gate = Gate()
        let postId = Self.incoming
        server.hold("GET", "posts/\(postId)/reveal", gate: gate) { _ in
            .object(Fixtures.readInfoPost(postId, user: "u2", message: "late", createAt: 100, type: "burn_on_read", expireAt: 9_000_000))
        }
        let session = await started(server)
        async let reveal: Void = session.revealBurnOnRead(postId: Self.incoming)
        #expect(await eventually { session.isRevealing(postId: Self.incoming) })
        await gate.open()
        await reveal
        #expect(!session.isRevealing(postId: Self.incoming))
        #expect(session.posts[Self.incoming]?.message == "late")
        session.stop()
    }

    @Test func revealedContentSurvivesRefetchAndEdits() async {
        let server = server()
        let session = await started(server)
        await session.revealBurnOnRead(postId: Self.incoming)
        session.apply(Fixtures.wsEvent("post_edited", data: [
            "post": Fixtures.json(Fixtures.readInfoPost(Self.incoming, user: "u2", message: "", createAt: 100, updateAt: 150, type: "burn_on_read")),
        ], channel: "c-town"))
        #expect(session.posts[Self.incoming]?.message == "the secret")
        #expect(session.posts[Self.incoming]?.burnOnReadExpireAt == 9_000_000)
        session.store(Post(id: Self.incoming, updateAt: 200, userId: "u2", channelId: "c-town", message: "", type: "burn_on_read"))
        #expect(session.posts[Self.incoming]?.message == "the secret")
        session.stop()
    }

    @Test func senderSeesReadReceipts() async {
        let session = await started(server())
        #expect(await eventually { session.channelMemberCounts["c-town"] == 4 })
        #expect(session.burnOnReadReceipt(postId: Self.outgoing) == BurnOnReadReceipt(revealedCount: 0, totalRecipients: 3))
        #expect(session.burnOnReadReceipt(postId: Self.incoming) == nil)
        #expect(session.burnOnReadReceipt(postId: "p1") == nil)
        session.posts[Self.outgoing]?.metadata.recipients = ["u2", "u3"]
        #expect(session.burnOnReadReceipt(postId: Self.outgoing)?.revealedCount == 2)
        session.channelMemberCounts["c-town"] = 0
        #expect(session.burnOnReadReceipt(postId: Self.outgoing)?.totalRecipients == 0)
        session.channelMemberCounts.removeValue(forKey: "c-town")
        #expect(session.burnOnReadReceipt(postId: Self.outgoing) == nil)
        session.stop()
    }

    @Test func channelStatsAreRequestedOnce() async {
        let server = server()
        let session = await started(server)
        #expect(await eventually { session.channelMemberCounts["c-town"] == 4 })
        await session.refreshChannelStats(channelId: "c-town")
        await session.refreshChannelStats(channelId: "")
        #expect(server.transport.count("GET", "channels/c-town/stats") == 1)
        session.stop()
    }

    @Test func failedChannelStatsCanBeRetried() async {
        let server = MockServer(pageSize: 10)
        server.licensed()
        server.transport.on("GET", "channels/c-town/stats", .error(500, message: "boom"))
        let session = await server.startedSession(pageSize: 10)
        await session.refreshChannelStats(channelId: "c-town")
        #expect(session.channelMemberCounts["c-town"] == nil)
        #expect(session.lastError == nil)
        server.transport.on("GET", "channels/c-town/stats", object: ["channel_id": "c-town", "member_count": 2, "guest_count": 0, "pinnedpost_count": 0, "files_count": 0])
        await session.refreshChannelStats(channelId: "c-town")
        #expect(session.channelMemberCounts["c-town"] == 2)
        session.stop()
    }

    @Test func revealEventAddsRecipientsForTheSender() async {
        let session = await started(server())
        let revealed = Fixtures.json(Fixtures.readInfoPost(Self.outgoing, user: "me1", message: "mine", createAt: 200, type: "burn_on_read", expireAt: 2_000_000))
        session.apply(Fixtures.wsEvent("post_revealed", data: ["post": revealed, "recipients": Fixtures.json(["u2"])], channel: "c-town"))
        #expect(session.posts[Self.outgoing]?.burnOnReadRevealedBy == ["u2"])
        #expect(session.posts[Self.outgoing]?.burnOnReadExpireAt == 2_000_000)
        session.apply(Fixtures.wsEvent("post_revealed", data: ["post": revealed, "recipients": Fixtures.json(["u3", "u2", ""])], channel: "c-town"))
        #expect(session.posts[Self.outgoing]?.burnOnReadRevealedBy == ["u2", "u3"])
        #expect(await eventually { session.users["u3"] != nil })
        session.stop()
    }

    @Test func revealEventWithContentRevealsForRecipients() async {
        let session = await started(server())
        let revealed = Fixtures.json(Fixtures.readInfoPost(Self.incoming, user: "u2", message: "shown", createAt: 100, type: "burn_on_read", expireAt: 3_000_000))
        session.apply(Fixtures.wsEvent("post_revealed", data: ["post": revealed], channel: "c-town"))
        #expect(session.posts[Self.incoming]?.message == "shown")
        let empty = Fixtures.json(Fixtures.readInfoPost(Self.incoming, user: "u2", message: "", createAt: 100, type: "burn_on_read"))
        session.apply(Fixtures.wsEvent("post_revealed", data: ["post": empty], channel: "c-town"))
        #expect(session.posts[Self.incoming]?.message == "shown")
        session.apply(Fixtures.wsEvent("post_revealed", data: ["post": "nonsense"], channel: "c-town"))
        session.apply(Fixtures.wsEvent("post_revealed", data: [
            "post": Fixtures.json(Fixtures.readInfoPost("unknown", user: "u2", message: "x", createAt: 1, type: "burn_on_read")),
        ], channel: "c-town"))
        #expect(session.posts["unknown"] == nil)
        session.stop()
    }

    @Test func allRevealedEventStartsTheSendersCountdown() async {
        let session = await started(server())
        session.apply(Fixtures.wsEvent("burn_on_read_all_revealed", data: ["post_id": Self.outgoing, "sender_expire_at": 4_000_000], channel: "c-town"))
        #expect(session.posts[Self.outgoing]?.burnOnReadExpireAt == 4_000_000)
        session.apply(Fixtures.wsEvent("burn_on_read_all_revealed", data: ["post_id": Self.outgoing, "sender_expire_at": 0], channel: "c-town"))
        #expect(session.posts[Self.outgoing]?.burnOnReadExpireAt == 4_000_000)
        session.apply(Fixtures.wsEvent("burn_on_read_all_revealed", data: ["post_id": "unknown", "sender_expire_at": 10], channel: "c-town"))
        session.apply(Fixtures.wsEvent("burn_on_read_all_revealed", data: ["sender_expire_at": 10], channel: "c-town"))
        #expect(session.posts["unknown"] == nil)
        session.stop()
    }

    @Test func burnEventAndCommandRemoveThePost() async {
        let server = server()
        let session = await started(server)
        await session.burn(postId: Self.outgoing)
        #expect(session.posts[Self.outgoing] == nil)
        #expect(!session.timelinePosts(channelId: "c-town").contains { $0.id == Self.outgoing })
        session.apply(Fixtures.wsEvent("post_burned", data: ["post_id": Self.incoming], channel: "c-town"))
        #expect(session.posts[Self.incoming] == nil)
        session.apply(Fixtures.wsEvent("post_burned", data: ["post_id": "unknown"], channel: "c-town"))
        session.apply(Fixtures.wsEvent("post_burned", data: [:], channel: "c-town"))
        #expect(server.transport.count("DELETE", "posts/\(Self.outgoing)/burn") == 1)
        session.stop()
    }

    @Test func burnReportsFailuresAndSkipsPlainPosts() async {
        let server = server()
        server.transport.on("DELETE", "posts/\(Self.outgoing)/burn", .error(403, message: "denied"))
        let session = await started(server)
        await session.burn(postId: "p1")
        await session.burn(postId: "missing")
        session.pendingPostIds.insert(Self.outgoing)
        await session.burn(postId: Self.outgoing)
        #expect(server.transport.count("DELETE", "posts/\(Self.outgoing)/burn") == 0)
        session.pendingPostIds.remove(Self.outgoing)
        await session.burn(postId: Self.outgoing)
        #expect(session.posts[Self.outgoing] != nil)
        #expect(session.lastError == "denied")
        session.stop()
    }

    @Test func expiredMessagesDisappear() async {
        let session = await started(server())
        var clock: Int64 = 1_000
        session.now = { Date.millis(clock) }
        session.posts[Self.incoming]?.metadata.expireAt = 1_100
        #expect(session.nextBurnOnReadExpiry == 1_100)
        session.scheduleBurnOnReadExpiry()
        #expect(session.posts[Self.incoming] != nil)
        clock = 2_000
        #expect(await eventually(timeout: .seconds(2)) { session.posts[Self.incoming] == nil })
        #expect(session.nextBurnOnReadExpiry == nil)
        #expect(session.burnOnReadTask == nil)
        session.stop()
    }

    @Test func expiryTimerStopsWithTheSession() async {
        let session = await started(server())
        session.posts[Self.incoming]?.metadata.expireAt = 60_000
        session.scheduleBurnOnReadExpiry()
        #expect(session.burnOnReadTask != nil)
        session.stop()
        #expect(session.burnOnReadTask == nil)
    }

    @Test func sendingBurnOnReadUsesThePostType() async throws {
        let server = server()
        server.acceptPosts()
        let session = await started(server)
        #expect(await session.send("secret", channelId: "c-town", burnOnRead: true))
        #expect(try #require(server.transport.last("POST", "posts")).jsonObject["type"] as? String == "burn_on_read")
        #expect(await session.send("reply", channelId: "c-town", rootId: "root", burnOnRead: true))
        #expect(try #require(server.transport.last("POST", "posts")).jsonObject["type"] as? String == "")
        session.config = ClientConfig(values: [:])
        #expect(await session.send("plain", channelId: "c-town", burnOnRead: true))
        #expect(try #require(server.transport.last("POST", "posts")).jsonObject["type"] as? String == "")
        session.stop()
    }

    @Test func burnOnReadIsOfferedOnlyWhereItWorks() async {
        let session = await started(server())
        #expect(session.canSendBurnOnRead(channelId: "c-town"))
        #expect(session.canSendBurnOnRead(channelId: "c-dm"))
        #expect(!session.canSendBurnOnRead(channelId: "missing"))
        session.channels["c-dm"]?.name = "me1__me1"
        #expect(!session.canSendBurnOnRead(channelId: "c-dm"))
        session.channels["c-dm"]?.name = "me1__u2"
        session.users["u2"]?.isBot = true
        #expect(!session.canSendBurnOnRead(channelId: "c-dm"))
        session.users["u2"]?.isBot = false
        session.channels["c-town"]?.deleteAt = 10
        #expect(!session.canSendBurnOnRead(channelId: "c-town"))
        session.license = ClientLicense(values: [:])
        #expect(!session.canSendBurnOnRead(channelId: "c-dm"))
        session.stop()
    }

    @Test func durationComesFromTheServerConfig() async {
        let session = await started(server())
        #expect(session.burnOnReadDurationMinutes == 10)
        session.config = ClientConfig(values: ["EnableBurnOnRead": "true", "BurnOnReadDurationSeconds": "120"])
        #expect(session.burnOnReadDurationMinutes == 2)
        session.stop()
    }

    @Test func arrivingMessageStartsTrackingForTheSender() async {
        let server = MockServer(pageSize: 10)
        server.licensed()
        let session = await server.startedSession(pageSize: 10, team: "t1")
        await session.loadLicense()
        session.apply(Fixtures.posted(Fixtures.readInfoPost("new", user: "me1", message: "mine", createAt: 2_000, type: "burn_on_read", recipients: ["u3"])))
        #expect(await eventually { session.channelMemberCounts["c-town"] == 4 })
        #expect(await eventually { session.users["u3"] != nil })
        #expect(session.posts["new"]?.isBurnOnRead == true)
        session.stop()
    }
}
