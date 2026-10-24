import Foundation
import Testing
@testable import BoltunMarkup

@Suite struct MessageRenderCacheTests {
    @Test func returnsSameBlocksAsRender() {
        let cache = MessageRenderCache(capacity: 10)
        let context = MarkupContext(myUsername: "me")
        #expect(cache.blocks(for: "hi @me", context: context) == MessageRenderer.render("hi @me", context: context))
        #expect(cache.blocks(for: "hi @me", context: context) == MessageRenderer.render("hi @me", context: context))
        #expect(cache.statistics == MessageRenderCache.Statistics(hits: 1, misses: 1, count: 1))
    }

    @Test func contextIsPartOfKey() {
        let cache = MessageRenderCache(capacity: 10)
        let plain = cache.blocks(for: "@me")
        let mine = cache.blocks(for: "@me", context: MarkupContext(myUsername: "me"))
        #expect(plain != mine)
        #expect(cache.statistics.count == 2)
        #expect(cache.statistics.misses == 2)
    }

    @Test func evictsLeastRecentlyUsed() {
        let cache = MessageRenderCache(capacity: 4)
        for index in 0..<4 {
            _ = cache.blocks(for: "m\(index)")
        }
        _ = cache.blocks(for: "m0")
        _ = cache.blocks(for: "m4")
        #expect(cache.statistics.count == 3)
        let before = cache.statistics
        _ = cache.blocks(for: "m0")
        _ = cache.blocks(for: "m4")
        #expect(cache.statistics.hits == before.hits + 2)
        _ = cache.blocks(for: "m1")
        #expect(cache.statistics.misses == before.misses + 1)
    }

    @Test func capacityIsAtLeastOne() {
        let cache = MessageRenderCache(capacity: 0)
        #expect(cache.capacity == 1)
        _ = cache.blocks(for: "a")
        _ = cache.blocks(for: "b")
        #expect(cache.statistics.count == 1)
        #expect(cache.blocks(for: "b") == [.paragraph("b")])
        #expect(cache.statistics.hits == 1)
    }

    @Test func removeAllResets() {
        let cache = MessageRenderCache()
        _ = cache.blocks(for: "a")
        cache.removeAll()
        #expect(cache.statistics == MessageRenderCache.Statistics(hits: 0, misses: 0, count: 0))
    }

    @Test func sharedCacheBacksCachedRender() {
        let message = "shared cache probe \(UUID().uuidString)"
        let before = MessageRenderCache.shared.statistics.hits
        #expect(MessageRenderer.cached(message) == [.paragraph(AttributedString(message))])
        #expect(MessageRenderer.cached(message) == [.paragraph(AttributedString(message))])
        #expect(MessageRenderCache.shared.statistics.hits >= before + 1)
    }

    @Test func isSafeUnderConcurrentAccess() async {
        let cache = MessageRenderCache(capacity: 50)
        await withTaskGroup(of: Bool.self) { group in
            for worker in 0..<8 {
                group.addTask {
                    (0..<200).allSatisfy { step in
                        let message = "**m\((worker * 7 + step) % 80)** @u"
                        return cache.blocks(for: message) == MessageRenderer.render(message)
                    }
                }
            }
            for await result in group {
                #expect(result)
            }
        }
        #expect(cache.statistics.count <= 50)
        #expect(cache.statistics.hits + cache.statistics.misses == 1_600)
    }
}
