import Foundation
import Synchronization

public final class MessageRenderCache: Sendable {
    public static let shared = MessageRenderCache()

    public struct Statistics: Hashable, Sendable {
        public var hits: Int
        public var misses: Int
        public var count: Int
    }

    private struct Key: Hashable {
        let message: String
        let context: MarkupContext
    }

    private struct Entry {
        let blocks: [MessageBlock]
        var lastUse: UInt64
    }

    private struct State {
        var entries: [Key: Entry] = [:]
        var clock: UInt64 = 0
        var hits = 0
        var misses = 0
    }

    public let capacity: Int
    private let state = Mutex(State())

    public init(capacity: Int = 2_000) {
        self.capacity = max(1, capacity)
    }

    public func blocks(for message: String, context: MarkupContext = MarkupContext()) -> [MessageBlock] {
        let key = Key(message: message, context: context)
        if let cached = lookup(key) {
            return cached
        }
        let blocks = MessageRenderer.render(message, context: context)
        store(blocks, for: key)
        return blocks
    }

    public var statistics: Statistics {
        state.withLock { Statistics(hits: $0.hits, misses: $0.misses, count: $0.entries.count) }
    }

    public func removeAll() {
        state.withLock { $0 = State() }
    }

    private func lookup(_ key: Key) -> [MessageBlock]? {
        state.withLock { state in
            state.clock += 1
            guard var entry = state.entries[key] else {
                state.misses += 1
                return nil
            }
            state.hits += 1
            entry.lastUse = state.clock
            state.entries[key] = entry
            return entry.blocks
        }
    }

    private func store(_ blocks: [MessageBlock], for key: Key) {
        let capacity = capacity
        state.withLock { state in
            state.clock += 1
            state.entries[key] = Entry(blocks: blocks, lastUse: state.clock)
            guard state.entries.count > capacity else { return }
            let keep = max(1, capacity * 3 / 4)
            let evicted = state.entries.sorted { $0.value.lastUse < $1.value.lastUse }.prefix(state.entries.count - keep)
            for (key, _) in evicted {
                state.entries.removeValue(forKey: key)
            }
        }
    }
}
