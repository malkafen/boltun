import Foundation
@testable import BoltunKit

struct FakeResponse: Sendable {
    var status: Int
    var body: Data
    var headers: [String: String]

    init(status: Int = 200, body: Data = Data(), headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }

    static func json(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> FakeResponse {
        FakeResponse(status: status, body: Data(text.utf8), headers: headers.merging(["Content-Type": "application/json"]) { a, _ in a })
    }

    static func object(_ value: Any, status: Int = 200, headers: [String: String] = [:]) -> FakeResponse {
        .json(Fixtures.json(value), status: status, headers: headers)
    }

    static func error(_ status: Int, id: String = "app.error", message: String = "Something failed") -> FakeResponse {
        .object(["id": id, "message": message, "status_code": status, "request_id": "req"], status: status)
    }

    static let ok = FakeResponse.json(#"{"status":"OK"}"#)
}

struct FakeTransportError: Error, LocalizedError {
    var errorDescription: String? { "The network connection was lost." }
}

final class FakeTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> FakeResponse

    private let lock = NSLock()
    private var routes: [String: Handler] = [:]
    private var recorded: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { recorded } }

    func on(_ method: String, _ path: String, _ response: FakeResponse) {
        on(method, path) { _ in response }
    }

    func on(_ method: String, _ path: String, json: String, status: Int = 200) {
        on(method, path, .json(json, status: status))
    }

    func on(_ method: String, _ path: String, object: Any, status: Int = 200) {
        on(method, path, .object(object, status: status))
    }

    func on(_ method: String, _ path: String, handler: @escaping Handler) {
        lock.withLock { routes[Self.key(method, Self.fullPath(path))] = handler }
    }

    func reset() {
        lock.withLock { recorded.removeAll() }
    }

    func requests(_ method: String, _ path: String) -> [URLRequest] {
        let full = Self.fullPath(path)
        return requests.filter { $0.httpMethod == method && $0.url?.path == full }
    }

    func count(_ method: String, _ path: String) -> Int {
        requests(method, path).count
    }

    func last(_ method: String, _ path: String) -> URLRequest? {
        requests(method, path).last
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let handler: Handler? = lock.withLock {
            recorded.append(request)
            return routes[Self.key(request.httpMethod ?? "GET", request.url?.path ?? "")]
        }
        let response = try await (handler ?? { _ in .error(404, id: "api.context.404.app_error", message: "Not found") })(request)
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
        return (response.body, http)
    }

    static func fullPath(_ path: String) -> String {
        path.hasPrefix("/") ? path : "/api/v4/" + path
    }

    static func key(_ method: String, _ path: String) -> String {
        "\(method) \(path)"
    }
}

actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

extension URLRequest {
    var query: [String: String] {
        guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    var jsonBody: Any? {
        guard let httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: httpBody, options: [.fragmentsAllowed])
    }

    var jsonObject: [String: Any] { jsonBody as? [String: Any] ?? [:] }

    var bodyText: String { httpBody.map { String(decoding: $0, as: UTF8.self) } ?? "" }
}
