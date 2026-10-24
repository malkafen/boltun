import Foundation

public protocol AppStateStoring: Sendable {
    func load() -> AppState
    func save(_ state: AppState) throws
}

public struct FileAppStateStore: AppStateStoring {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultURL(appName: String = "Boltun") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return base.appending(path: appName).appending(path: "state.json")
    }

    public func load() -> AppState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(AppState.self, from: data)
        else { return AppState() }
        return state
    }

    public func save(_ state: AppState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}

public final class MemoryAppStateStore: AppStateStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: AppState

    public init(_ state: AppState = AppState()) {
        self.state = state
    }

    public func load() -> AppState {
        lock.withLock { state }
    }

    public func save(_ state: AppState) throws {
        lock.withLock { self.state = state }
    }
}
