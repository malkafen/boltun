import Foundation

public extension APIClient {
    func clientLicense() async throws -> ClientLicense {
        let raw = try await send(JSONObject.self, .get, "license/client", query: ["format": "old"])
        return ClientLicense(values: raw.compactMapValues(\.stringValue))
    }

    func acknowledgePost(userId: String, postId: String) async throws -> PostAcknowledgement {
        try await send(PostAcknowledgement.self, .post, "users/\(userId)/posts/\(postId)/ack")
    }

    func unacknowledgePost(userId: String, postId: String) async throws {
        try await sendVoid(.delete, "users/\(userId)/posts/\(postId)/ack")
    }

    func revealPost(id: String) async throws -> Post {
        try await send(Post.self, .get, "posts/\(id)/reveal")
    }

    func burnPost(id: String) async throws {
        try await sendVoid(.delete, "posts/\(id)/burn")
    }
}
