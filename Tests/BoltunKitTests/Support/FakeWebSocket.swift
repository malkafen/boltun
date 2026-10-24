import Foundation
@testable import BoltunKit

struct SocketClosed: Error, LocalizedError {
    var errorDescription: String? { "Socket closed" }
}

final class FakeSocket: WebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [String] = []
    private var waiter: CheckedContinuation<String, Error>?
    private var closed = false
    private var sentMessages: [String] = []

    var sent: [String] { lock.withLock { sentMessages } }

    var sentObjects: [[String: Any]] {
        sent.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    var isClosed: Bool { lock.withLock { closed } }

    func push(_ text: String) {
        lock.lock()
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(returning: text)
        } else {
            queue.append(text)
            lock.unlock()
        }
    }

    func push(_ object: Any) {
        push(Fixtures.json(object))
    }

    func send(_ text: String) async throws {
        lock.withLock { sentMessages.append(text) }
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !queue.isEmpty {
                let next = queue.removeFirst()
                lock.unlock()
                continuation.resume(returning: next)
            } else if closed {
                lock.unlock()
                continuation.resume(throwing: SocketClosed())
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    func close() {
        lock.lock()
        closed = true
        let pending = waiter
        waiter = nil
        lock.unlock()
        pending?.resume(throwing: SocketClosed())
    }
}

final class FakeConnector: WebSocketConnector, @unchecked Sendable {
    private let lock = NSLock()
    private var created: [FakeSocket] = []
    private var connectedURLs: [URL] = []
    private var connectedTokens: [String] = []
    private let script: (@Sendable (FakeSocket, Int) -> Void)?

    init(script: (@Sendable (FakeSocket, Int) -> Void)? = nil) {
        self.script = script
    }

    var sockets: [FakeSocket] { lock.withLock { created } }
    var urls: [URL] { lock.withLock { connectedURLs } }
    var tokens: [String] { lock.withLock { connectedTokens } }

    func socket(_ index: Int) -> FakeSocket? {
        lock.withLock { created.indices.contains(index) ? created[index] : nil }
    }

    func connect(url: URL, token: String) -> WebSocketConnection {
        let socket = FakeSocket()
        let index = lock.withLock {
            created.append(socket)
            connectedURLs.append(url)
            connectedTokens.append(token)
            return created.count - 1
        }
        script?(socket, index)
        return socket
    }
}

final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration] = []
    private let blockOn: @Sendable (Duration, Int) -> Bool

    init(blockOn: @escaping @Sendable (Duration, Int) -> Bool = { _, _ in false }) {
        self.blockOn = blockOn
    }

    static func blocking() -> SleepRecorder { SleepRecorder { _, _ in true } }

    var durations: [Duration] { lock.withLock { recorded } }

    var sleeper: RealtimeClient.Sleeper {
        { [self] duration in
            let count = lock.withLock {
                recorded.append(duration)
                return recorded.count
            }
            if blockOn(duration, count) {
                try await Task.sleep(for: .seconds(3600))
            }
        }
    }
}

actor EventCollector {
    private(set) var events: [RealtimeEvent] = []

    init(_ client: RealtimeClient) {
        let stream = client.events
        Task { await self.consume(stream) }
    }

    private func consume(_ stream: AsyncStream<RealtimeEvent>) async {
        for await event in stream { events.append(event) }
        finished = true
    }

    private(set) var finished = false

    var connections: [Bool] {
        events.compactMap { if case .connected(let resync) = $0 { return resync } else { return nil } }
    }

    var received: [WebSocketEvent] {
        events.compactMap { if case .event(let event) = $0 { return event } else { return nil } }
    }

    var disconnects: Int {
        events.filter { if case .disconnected = $0 { return true } else { return false } }.count
    }
}
