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

    public init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
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
    private var connection: WebSocketConnection?
    private var loop: Task<Void, Never>?
    private var seq: Int64 = 1
    private var connectionId = ""
    private var lastServerSeq: Int64 = -1
    private var hasConnectedBefore = false
    private let continuation: AsyncStream<RealtimeEvent>.Continuation
    public nonisolated let events: AsyncStream<RealtimeEvent>

    public init(url: URL, token: String, connector: WebSocketConnector = URLSessionWebSocketConnector(), maxBackoff: Duration = .seconds(30), sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) }) {
        self.url = url
        self.token = token
        self.connector = connector
        self.sleeper = sleeper
        self.maxBackoff = maxBackoff
        (events, continuation) = AsyncStream.makeStream(of: RealtimeEvent.self, bufferingPolicy: .unbounded)
    }

    public func start() {
        guard loop == nil else { return }
        loop = Task { await self.run() }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        connection?.close()
        connection = nil
        continuation.finish()
    }

    public func reconnectNow() {
        connection?.close()
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
            URLQueryItem(name: "sequence_number", value: String(lastServerSeq)),
        ]
        return components.url ?? url
    }

    private func run() async {
        var attempt = 0
        while !Task.isCancelled {
            let connection = connector.connect(url: connectionURL(), token: token)
            self.connection = connection
            seq = 1
            var receivedAny = false
            do {
                while !Task.isCancelled {
                    let text = try await connection.receive()
                    guard let event = WebSocketEvent.parse(text) else { continue }
                    if !receivedAny {
                        receivedAny = true
                        attempt = 0
                    }
                    handle(event)
                }
            } catch {
                connection.close()
                self.connection = nil
                if Task.isCancelled { break }
                continuation.yield(.disconnected(error.localizedDescription))
            }
            if Task.isCancelled { break }
            attempt += 1
            let delay = backoff(attempt: attempt)
            do { try await sleeper(delay) } catch { break }
        }
    }

    func backoff(attempt: Int) -> Duration {
        let seconds = min(Double(1 << min(attempt - 1, 10)), Double(maxBackoff.components.seconds))
        return .seconds(max(seconds, 0))
    }

    private func handle(_ event: WebSocketEvent) {
        if event.event == WebSocketEventType.hello {
            let newId = event.string("connection_id") ?? ""
            let resumed = !connectionId.isEmpty && newId == connectionId
            connectionId = newId
            lastServerSeq = event.seq
            let reconnected = hasConnectedBefore
            hasConnectedBefore = true
            continuation.yield(.connected(needsResync: reconnected && !resumed))
            return
        }
        lastServerSeq = event.seq
        continuation.yield(.event(event))
    }
}
