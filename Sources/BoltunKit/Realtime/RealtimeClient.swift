import Foundation

public protocol WebSocketConnection: Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func close()
}

public protocol WebSocketConnector: Sendable {
    func connect(url: URL, token: String) -> WebSocketConnection
}

public final class URLSessionWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
        task.maximumMessageSize = 16 << 20
        task.resume()
    }

    public func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    public func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let text): return text
        case .data(let data): return String(decoding: data, as: UTF8.self)
        @unknown default: return ""
        }
    }

    public func close() {
        task.cancel(with: .goingAway, reason: nil)
    }
}

public struct URLSessionWebSocketConnector: WebSocketConnector {
    let session: URLSession

    public init(session: URLSession = URLSessionWebSocketConnector.makeSession()) {
        self.session = session
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    public func connect(url: URL, token: String) -> WebSocketConnection {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        return URLSessionWebSocketConnection(task: session.webSocketTask(with: request))
    }
}

public enum RealtimeEvent: Sendable, Equatable {
    case connected(needsResync: Bool)
    case disconnected(String)
    case event(WebSocketEvent)
}

public actor RealtimeClient {
    public typealias Sleeper = @Sendable (Duration) async throws -> Void

    private let url: URL
    private let token: String
    private let connector: WebSocketConnector
    private let sleeper: Sleeper
    private let maxBackoff: Duration
    private let handshakeTimeout: Duration?
    private var connection: WebSocketConnection?
    private var loop: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var backoffWaiter: Task<Void, Error>?
    private var seq: Int64 = 1
    private var connectionId = ""
    private var nextServerSeq: Int64 = 0
    private var hasConnectedBefore = false
    private var generation = 0
    private var established = false
    private var announced = false
    private var stopped = false
    private var skipBackoff = false
    private var attempt = 0
    private let continuation: AsyncStream<RealtimeEvent>.Continuation
    public nonisolated let events: AsyncStream<RealtimeEvent>

    public init(
        url: URL,
        token: String,
        connector: WebSocketConnector = URLSessionWebSocketConnector(),
        maxBackoff: Duration = .seconds(30),
        handshakeTimeout: Duration? = .seconds(20),
        sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.url = url
        self.token = token
        self.connector = connector
        self.sleeper = sleeper
        self.maxBackoff = maxBackoff
        self.handshakeTimeout = handshakeTimeout
        (events, continuation) = AsyncStream.makeStream(of: RealtimeEvent.self, bufferingPolicy: .unbounded)
    }

    public func start() {
        guard loop == nil, !stopped else { return }
        loop = Task { await self.run() }
    }

    public func stop() {
        stopped = true
        loop?.cancel()
        loop = nil
        watchdog?.cancel()
        watchdog = nil
        backoffWaiter?.cancel()
        backoffWaiter = nil
        connection?.close()
        connection = nil
        continuation.finish()
    }

    public func reconnectNow() {
        guard !stopped else { return }
        skipBackoff = true
        if let backoffWaiter {
            backoffWaiter.cancel()
        } else {
            connection?.close()
        }
    }

    public func userTyping(channelId: String, parentId: String = "") async {
        await sendAction("user_typing", data: ["channel_id": .string(channelId), "parent_id": .string(parentId)])
    }

    public func sendAction(_ action: String, data: JSONObject) async {
        guard let connection else { return }
        let message: JSONObject = ["action": .string(action), "seq": .number(Double(seq)), "data": .object(data)]
        seq += 1
        guard let encoded = try? MattermostJSON.encoder.encode(message) else { return }
        try? await connection.send(String(decoding: encoded, as: UTF8.self))
    }

    func connectionURL() -> URL {
        guard !connectionId.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = [
            URLQueryItem(name: "connection_id", value: connectionId),
            URLQueryItem(name: "sequence_number", value: String(nextServerSeq)),
        ]
        return components.url ?? url
    }

    private func run() async {
        attempt = 0
        while !Task.isCancelled && !stopped {
            let connection = connector.connect(url: connectionURL(), token: token)
            generation += 1
            self.connection = connection
            seq = 1
            established = false
            announced = false
            armWatchdog(generation: generation)
            await sendAction("ping", data: [:])
            do {
                while !Task.isCancelled && !stopped {
                    let text = try await connection.receive()
                    handle(text)
                }
            } catch {
                connection.close()
                self.connection = nil
                watchdog?.cancel()
                if Task.isCancelled || stopped { break }
                continuation.yield(.disconnected(error.localizedDescription))
            }
            if Task.isCancelled || stopped { break }
            if skipBackoff {
                skipBackoff = false
                attempt = 0
                continue
            }
            attempt += 1
            guard await waitBeforeReconnect(backoff(attempt: attempt)) else { break }
        }
    }

    private func waitBeforeReconnect(_ delay: Duration) async -> Bool {
        let sleeper = self.sleeper
        let waiter = Task { try await sleeper(delay) }
        backoffWaiter = waiter
        let result = await waiter.result
        backoffWaiter = nil
        if stopped || Task.isCancelled { return false }
        if skipBackoff {
            skipBackoff = false
            return true
        }
        if case .failure = result { return false }
        return true
    }

    private func armWatchdog(generation current: Int) {
        watchdog?.cancel()
        watchdog = nil
        guard let handshakeTimeout else { return }
        let sleeper = self.sleeper
        watchdog = Task { [weak self] in
            do { try await sleeper(handshakeTimeout) } catch { return }
            await self?.handshakeExpired(generation: current)
        }
    }

    private func handshakeExpired(generation current: Int) {
        guard current == generation, !established else { return }
        connection?.close()
    }

    func backoff(attempt: Int) -> Duration {
        let seconds = min(Double(1 << min(max(attempt, 1) - 1, 10)), Double(maxBackoff.components.seconds))
        return .seconds(max(seconds, 0))
    }

    private func handle(_ text: String) {
        guard let event = WebSocketEvent.parse(text) else {
            handleReply(text)
            return
        }
        if event.event == WebSocketEventType.hello {
            handleHello(event)
            return
        }
        guard !connectionId.isEmpty, event.seq > 0 else {
            if !announced && !connectionId.isEmpty { announce(needsResync: false) }
            continuation.yield(.event(event))
            return
        }
        if event.seq < nextServerSeq {
            if !announced { announce(needsResync: false) }
            return
        }
        let gap = event.seq > nextServerSeq
        if !announced {
            announce(needsResync: gap)
        } else if gap {
            continuation.yield(.connected(needsResync: true))
        }
        nextServerSeq = event.seq + 1
        continuation.yield(.event(event))
    }

    private func handleHello(_ event: WebSocketEvent) {
        let newId = event.string("connection_id") ?? ""
        let resumed = !connectionId.isEmpty && newId == connectionId
        let needsResync = hasConnectedBefore && !resumed
        connectionId = newId
        nextServerSeq = event.seq + 1
        announce(needsResync: needsResync)
    }

    private func handleReply(_ text: String) {
        let reply = text.data(using: .utf8).flatMap { try? MattermostJSON.decoder.decode(JSONObject.self, from: $0) } ?? [:]
        if reply["status"]?.stringValue == "FAIL" {
            if reply["error"]?["id"]?.stringValue?.contains("not_authenticated") == true { connection?.close() }
            return
        }
        if !announced && !connectionId.isEmpty { announce(needsResync: false) }
    }

    private func announce(needsResync: Bool) {
        if !established {
            established = true
            attempt = 0
            watchdog?.cancel()
            watchdog = nil
        }
        announced = true
        hasConnectedBefore = true
        continuation.yield(.connected(needsResync: needsResync))
    }
}
