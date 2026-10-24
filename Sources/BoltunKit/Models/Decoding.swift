import Foundation

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }

    func optional<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    func int64(_ key: Key) -> Int64 {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int64(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key), let parsed = Int64(value) { return parsed }
        return 0
    }

    func int(_ key: Key) -> Int { Int(int64(key)) }
}

public enum MattermostJSON {
    public static let decoder = JSONDecoder()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

public extension Int64 {
    var mattermostDate: Date { Date(timeIntervalSince1970: TimeInterval(self) / 1000) }
}

public extension Date {
    var mattermostMillis: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }
}
