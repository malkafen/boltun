import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

public struct APIClient: Sendable {
    public let baseURL: URL
    public var token: String?
    public let transport: HTTPTransport

    public init(baseURL: URL, token: String? = nil, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.token = token
        self.transport = transport
    }

    public static func normalize(_ raw: String) throws -> URL {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw APIError.invalidURL(raw) }
        if !value.contains("://") { value = "https://" + value }
        while value.hasSuffix("/") { value.removeLast() }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              let url = components.url
        else { throw APIError.invalidURL(raw) }
        return url
    }

    public var apiBase: URL { baseURL.appending(path: "api/v4") }

    public func url(_ path: String, query: [String: String] = [:]) -> URL {
        var components = URLComponents(url: apiBase.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.percentEncodedQuery = query
                .sorted { $0.key < $1.key }
                .map { "\(Self.encodeQueryComponent($0.key))=\(Self.encodeQueryComponent($0.value))" }
                .joined(separator: "&")
        }
        return components.url!
    }

    static let queryAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func encodeQueryComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? value
    }

    public func request(_ method: HTTPMethod, _ path: String, query: [String: String] = [:], body: Data? = nil, contentType: String = "application/json") -> URLRequest {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method.rawValue
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    @discardableResult
    public func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            if APIError.isCancellation(error) { throw CancellationError() }
            throw APIError.wrap(error)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.from(status: response.statusCode, data: data)
        }
        return (data, response)
    }

    public func send<T: Decodable>(_ type: T.Type, _ method: HTTPMethod, _ path: String, query: [String: String] = [:]) async throws -> T {
        try await decode(T.self, request(method, path, query: query))
    }

    public func send<T: Decodable, B: Encodable>(_ type: T.Type, _ method: HTTPMethod, _ path: String, query: [String: String] = [:], json: B) async throws -> T {
        try await decode(T.self, request(method, path, query: query, body: encode(json)))
    }

    public func sendVoid(_ method: HTTPMethod, _ path: String, query: [String: String] = [:]) async throws {
        try await perform(request(method, path, query: query))
    }

    public func sendVoid<B: Encodable>(_ method: HTTPMethod, _ path: String, query: [String: String] = [:], json: B) async throws {
        try await perform(request(method, path, query: query, body: encode(json)))
    }

    func encode<B: Encodable>(_ value: B) throws -> Data {
        do {
            return try MattermostJSON.encoder.encode(value)
        } catch {
            throw APIError.wrap(error)
        }
    }

    func decode<T: Decodable>(_ type: T.Type, _ request: URLRequest) async throws -> T {
        let (data, _) = try await perform(request)
        do {
            return try MattermostJSON.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.wrap(error)
        }
    }

    public func data(at url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return try await perform(request).0
    }

    public var webSocketURL: URL {
        var components = URLComponents(url: apiBase.appending(path: "websocket"), resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        return components.url!
    }
}

struct StatusOK: Decodable {
    var status: String
}
