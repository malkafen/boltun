import BoltunKit
import Foundation

public final class FileCredentialStore: CredentialStore, @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultURL() -> URL {
        FileAppStateStore.defaultURL().deletingLastPathComponent().appending(path: "debug-credentials.json")
    }

    public func token(for serverId: UUID) -> String? {
        lock.withLock { load()[serverId.uuidString] }
    }

    public func setToken(_ token: String, for serverId: UUID) throws {
        try lock.withLock {
            var tokens = load()
            tokens[serverId.uuidString] = token
            try save(tokens)
        }
    }

    public func removeToken(for serverId: UUID) {
        lock.withLock {
            var tokens = load()
            guard tokens.removeValue(forKey: serverId.uuidString) != nil else { return }
            try? save(tokens)
        }
    }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let tokens = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return tokens
    }

    private func save(_ tokens: [String: String]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(tokens).write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
