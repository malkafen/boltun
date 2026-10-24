import Foundation

public extension APIClient {
    func updateChannelNotifyProps(channelId: String, userId: String, props: [String: String]) async throws {
        try await sendVoid(.put, "channels/\(channelId)/members/\(userId)/notify_props", json: props)
    }
}
