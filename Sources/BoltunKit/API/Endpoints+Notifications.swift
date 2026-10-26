import Foundation

public extension APIClient {
    func updateChannelNotifyProps(channelId: String, userId: String, props: [String: String]) async throws {
        try await sendVoid(.put, "channels/\(channelId)/members/\(userId)/notify_props", json: props)
    }

    func updateMyNotifyProps(_ props: [String: String]) async throws -> User {
        try await send(User.self, .put, "users/me/patch", json: ["notify_props": props])
    }
}
