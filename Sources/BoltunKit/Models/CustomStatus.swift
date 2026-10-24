import Foundation

public struct CustomStatus: Codable, Hashable, Sendable {
    public static let dontClear = "dont_clear"

    public var emoji: String
    public var text: String
    public var duration: String
    public var expiresAt: Date?

    public init(emoji: String = "", text: String = "", duration: String = "", expiresAt: Date? = nil) {
        self.emoji = emoji
        self.text = text
        self.duration = duration
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case emoji, text, duration
        case expiresAt = "expires_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        emoji = c.value(.emoji, default: "")
        text = c.value(.text, default: "")
        duration = c.value(.duration, default: "")
        expiresAt = c.optional(.expiresAt).flatMap(Self.parseDate)
    }

    public init?(json: String) {
        guard let data = json.data(using: .utf8), let value = try? MattermostJSON.decoder.decode(CustomStatus.self, from: data) else { return nil }
        self = value
    }

    public var isSet: Bool { !text.isEmpty || !emoji.isEmpty }

    public func isExpired(now: Date) -> Bool {
        guard duration != Self.dontClear, let expiresAt else { return false }
        return now >= expiresAt
    }

    public var showsExpiry: Bool { duration != Self.dontClear && expiresAt != nil }

    static func parseDate(_ raw: String) -> Date? {
        if let date = try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
        return try? Date(raw, strategy: Date.ISO8601FormatStyle())
    }
}
