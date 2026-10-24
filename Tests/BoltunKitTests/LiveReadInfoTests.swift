import Foundation
import Testing
@testable import BoltunKit

enum LiveEnterprise {
    static let variable = ProcessInfo.processInfo.environment["BOLTUN_LIVE_ENTERPRISE"]
    static let enabled = variable != nil
    static var baseURL: String {
        let custom = variable ?? ""
        return custom.hasPrefix("http") ? custom : "http://192.168.15.101:8067"
    }

    static let partner = "user1"
    static let partnerPassword = "User1-pass1"
    static let channelName = "boltun-read-info-live"

    static func channel(_ client: APIClient, team: Team) async throws -> Channel {
        do {
            return try await client.send(Channel.self, .get, "teams/\(team.id)/channels/name/\(channelName)")
        } catch APIError.server(status: 404, _) {
            return try await client.send(Channel.self, .post, "channels", json: [
                "team_id": team.id,
                "name": channelName,
                "display_name": "Boltun Read Info Live",
                "type": "P",
            ])
        }
    }

    static func addMember(_ client: APIClient, channelId: String, userId: String) async throws {
        _ = try? await client.send(ChannelMember.self, .post, "channels/\(channelId)/members", json: ["user_id": userId])
    }
}

@Suite(.enabled(if: LiveEnterprise.enabled), .serialized, .timeLimit(.minutes(2)))
struct LiveReadInfoTests {
    @Test func licensedFeaturesAreAdvertised() async throws {
        let (client, _) = try await Live.login(LiveEnterprise.baseURL)
        let config = try await client.clientConfig()
        #expect(config.postPriority)
        #expect(config.postAcknowledgements)
        #expect(config.enableBurnOnRead)
        #expect(config.burnOnReadDurationSeconds > 0)
        let license = try await client.clientLicense()
        #expect(license.isLicensed)
        #expect(license.isMinimumEnterpriseAdvanced)
    }

    @Test func acknowledgementsRoundTrip() async throws {
        let base = LiveEnterprise.baseURL
        let (client, me) = try await Live.login(base)
        let (partner, partnerUser) = try await Live.login(base, user: LiveEnterprise.partner, password: LiveEnterprise.partnerPassword)
        let team = try await Live.team(client)
        let channel = try await LiveEnterprise.channel(client, team: team)
        try await LiveEnterprise.addMember(client, channelId: channel.id, userId: partnerUser.id)
        let marker = Live.marker()
        let post = try await client.createPost(
            channelId: channel.id,
            message: "\(marker) please acknowledge",
            priority: PostPriority(priority: .urgent, requestedAck: true)
        )
        defer { Task { try? await client.deletePost(id: post.id) } }
        #expect(post.priorityLevel == .urgent)
        #expect(post.requestsAcknowledgement)

        let acknowledgement = try await partner.acknowledgePost(userId: partnerUser.id, postId: post.id)
        #expect(acknowledgement.userId == partnerUser.id)
        #expect(acknowledgement.postId == post.id)
        #expect(acknowledgement.acknowledgedAt > 0)
        let fetched = try await client.post(id: post.id)
        #expect(fetched.acknowledgedAt(by: partnerUser.id) == acknowledgement.acknowledgedAt)
        #expect(fetched.acknowledgedAt(by: me.id) == nil)

        try await partner.unacknowledgePost(userId: partnerUser.id, postId: post.id)
        #expect(try await client.post(id: post.id).acknowledgements.isEmpty)
    }

    @MainActor
    @Test func sessionFollowsAcknowledgementsAndBurnOnRead() async throws {
        let base = LiveEnterprise.baseURL
        let (client, _) = try await Live.login(base)
        let (partner, partnerUser) = try await Live.login(base, user: LiveEnterprise.partner, password: LiveEnterprise.partnerPassword)
        let team = try await Live.team(client)
        let channel = try await LiveEnterprise.channel(client, team: team)
        try await LiveEnterprise.addMember(client, channelId: channel.id, userId: partnerUser.id)
        let session = ServerSession(serverId: UUID(), client: client, realtimeFactory: { url, token in
            RealtimeClient(url: url, token: token, connector: Live.connector, maxBackoff: .seconds(2))
        })
        defer { session.stop() }
        await session.start()
        await session.selectTeam(team.id, channelId: channel.id)
        #expect(await eventually(timeout: .seconds(10)) { session.license.isLicensed })
        #expect(session.acknowledgementsEnabled)
        #expect(session.burnOnReadEnabled)

        let marker = Live.marker()
        #expect(await session.send("\(marker) confirm", channelId: channel.id, priority: PostPriority(priority: .important, requestedAck: true)))
        let asked = try #require(session.timelinePosts(channelId: channel.id).last { $0.message.hasPrefix(marker) })
        #expect(asked.priorityLevel == .important)
        _ = try await partner.acknowledgePost(userId: partnerUser.id, postId: asked.id)
        #expect(await eventually(timeout: .seconds(15)) { session.posts[asked.id]?.acknowledgedAt(by: partnerUser.id) != nil })
        try await partner.unacknowledgePost(userId: partnerUser.id, postId: asked.id)
        #expect(await eventually(timeout: .seconds(15)) { session.posts[asked.id]?.acknowledgements.isEmpty == true })
        await session.delete(postId: asked.id)

        #expect(await session.send("\(marker) secret", channelId: channel.id, burnOnRead: true))
        let secret = try #require(session.timelinePosts(channelId: channel.id).last { $0.message.hasPrefix(marker) })
        #expect(secret.isBurnOnRead)
        #expect(await eventually(timeout: .seconds(10)) { session.channelMemberCounts[channel.id] != nil })
        #expect(session.burnOnReadReceipt(postId: secret.id)?.revealedCount == 0)

        let concealed = try await partner.post(id: secret.id)
        #expect(concealed.isBurnOnReadConcealed(for: partnerUser.id))
        let revealed = try await partner.revealPost(id: secret.id)
        #expect(revealed.message.hasPrefix(marker))
        #expect(revealed.burnOnReadExpireAt > 0)
        #expect(await eventually(timeout: .seconds(15)) { session.burnOnReadReceipt(postId: secret.id)?.revealedCount == 1 })

        await session.burn(postId: secret.id)
        #expect(session.posts[secret.id] == nil)
        await #expect(throws: APIError.self) { _ = try await partner.post(id: secret.id) }
        #expect(session.lastError == nil)
    }
}
