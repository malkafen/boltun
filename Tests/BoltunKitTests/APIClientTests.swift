import Foundation
import Testing
@testable import BoltunKit

@Suite struct APIClientTests {
    let transport = FakeTransport()

    func client(token: String? = "tok", base: String = "https://chat.example.com") -> APIClient {
        APIClient(baseURL: URL(string: base)!, token: token, transport: transport)
    }

    @Test(arguments: [
        ("chat.example.com", "https://chat.example.com"),
        ("  https://chat.example.com/// ", "https://chat.example.com"),
        ("http://10.0.0.1:8065", "http://10.0.0.1:8065"),
        ("example.com:8065/mattermost/", "https://example.com:8065/mattermost"),
    ])
    func normalizesURLs(raw: String, expected: String) throws {
        #expect(try APIClient.normalize(raw).absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "ftp://example.com", "https://", "http:///path"])
    func rejectsInvalidURLs(raw: String) {
        #expect(throws: APIError.invalidURL(raw)) { try APIClient.normalize(raw) }
    }

    @Test func buildsURLsWithEncodedQuery() {
        let url = client().url("users/autocomplete", query: ["name": "c++ & co=1", "in_team": "t1", "emoji": "ü"])
        #expect(url.absoluteString == "https://chat.example.com/api/v4/users/autocomplete?emoji=%C3%BC&in_team=t1&name=c%2B%2B%20%26%20co%3D1")
        #expect(client().url("system/ping").absoluteString == "https://chat.example.com/api/v4/system/ping")
        #expect(client(base: "https://example.com/mm").apiBase.absoluteString == "https://example.com/mm/api/v4")
    }

    @Test func requestCarriesHeaders() {
        let request = client().request(.post, "posts", body: Data("{}".utf8))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody == Data("{}".utf8))
        let anonymous = client(token: nil).request(.get, "system/ping")
        #expect(anonymous.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(anonymous.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(anonymous.httpBody == nil)
    }

    @Test func mapsUnauthorized() async {
        transport.on("GET", "users/me", .error(401, id: "api.context.session_expired.app_error", message: "Invalid or expired session, please login again."))
        await #expect(throws: APIError.unauthorized(ServerErrorBody(id: "api.context.session_expired.app_error", message: "Invalid or expired session, please login again.", statusCode: 401, requestId: "req"))) {
            try await client().me()
        }
    }

    @Test(arguments: ["mfa.validate_token.authenticate.app_error", "api.context.mfa_required.app_error", "api.user.check_user_mfa.bad_code.app_error"])
    func mapsMFA(id: String) async {
        transport.on("POST", "users/login", .error(401, id: id))
        await #expect(throws: APIError.mfaRequired) { try await client(token: nil).login(loginId: "a", password: "b") }
        transport.on("POST", "users/login", .error(400, id: id))
        await #expect(throws: APIError.mfaRequired) { try await client(token: nil).login(loginId: "a", password: "b") }
    }

    @Test func mapsServerErrors() async {
        transport.on("GET", "users/me", .error(500, id: "app.user.get.app_error", message: "Database down"))
        do {
            _ = try await client().me()
            Issue.record("expected failure")
        } catch let error as APIError {
            #expect(error == .server(status: 500, body: ServerErrorBody(id: "app.user.get.app_error", message: "Database down", statusCode: 500, requestId: "req")))
            #expect(error.localizedDescription == "Database down")
            #expect(!error.isUnauthorized)
        } catch {
            Issue.record("unexpected \(error)")
        }
        transport.on("GET", "users/me", FakeResponse(status: 502, body: Data("<html>Bad gateway</html>".utf8)))
        await #expect(throws: APIError.server(status: 502, body: nil)) { try await client().me() }
    }

    @Test func mapsTransportAndCancellation() async {
        transport.on("GET", "users/me") { _ in throw FakeTransportError() }
        await #expect(throws: APIError.transport("The network connection was lost.")) { try await client().me() }
        transport.on("GET", "users/me") { _ in throw URLError(.cancelled) }
        await #expect(throws: CancellationError.self) { try await client().me() }
        transport.on("GET", "users/me") { _ in throw CancellationError() }
        await #expect(throws: CancellationError.self) { try await client().me() }
    }

    @Test func mapsDecodingFailures() async {
        transport.on("GET", "users/me", json: #"{"username":"no id"}"#)
        do {
            _ = try await client().me()
            Issue.record("expected failure")
        } catch let APIError.decoding(detail) {
            #expect(detail.contains("id"))
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func encodingFailureIsWrapped() {
        #expect(throws: APIError.self) { try client().encode(Double.nan) }
    }

    @Test func sendVariants() async throws {
        transport.on("PUT", "things", json: #"{"status":"OK"}"#)
        transport.on("DELETE", "things", json: "")
        let status = try await client().send(StatusOK.self, .put, "things", json: ["a": 1])
        #expect(status.status == "OK")
        #expect(transport.last("PUT", "things")?.jsonObject["a"] as? Int == 1)
        try await client().sendVoid(.delete, "things", query: ["x": "1"])
        #expect(transport.last("DELETE", "things")?.query == ["x": "1"])
        try await client().sendVoid(.put, "things", json: ["b": true])
        #expect(transport.last("PUT", "things")?.jsonObject["b"] as? Bool == true)
    }

    @Test func dataAtURLUsesAuthHeaders() async throws {
        transport.on("GET", "/files/raw", FakeResponse(body: Data([1, 2, 3])))
        let data = try await client().data(at: URL(string: "https://chat.example.com/files/raw")!)
        #expect(data == Data([1, 2, 3]))
        let request = try #require(transport.requests.last)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
        _ = try await client(token: nil).data(at: URL(string: "https://chat.example.com/files/raw")!)
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func webSocketURL() {
        #expect(client().webSocketURL.absoluteString == "wss://chat.example.com/api/v4/websocket")
        #expect(client(base: "http://10.0.0.1:8065/mm").webSocketURL.absoluteString == "ws://10.0.0.1:8065/mm/api/v4/websocket")
    }

    @Test func errorDescriptions() {
        #expect(APIError.invalidURL("x").localizedDescription == "Invalid server URL: x")
        #expect(APIError.invalidResponse.localizedDescription == "The server returned an invalid response.")
        #expect(APIError.unauthorized(nil).localizedDescription == "Your session has expired. Please log in again.")
        #expect(APIError.unauthorized(ServerErrorBody(id: "x", message: "Wrong password")).localizedDescription == "Wrong password")
        #expect(APIError.unauthorized(ServerErrorBody(id: "x", message: "")).localizedDescription == "Your session has expired. Please log in again.")
        #expect(APIError.mfaRequired.localizedDescription == "Multi-factor authentication code required.")
        #expect(APIError.server(status: 503, body: nil).localizedDescription == "Server error (503).")
        #expect(APIError.decoding("bad").localizedDescription == "Unexpected server data: bad")
        #expect(APIError.transport("offline").localizedDescription == "offline")
        #expect(APIError.unauthorized(nil).isUnauthorized)
        #expect(!APIError.mfaRequired.isUnauthorized)
    }

    @Test func wrapAndCancellationClassification() {
        #expect(APIError.wrap(APIError.mfaRequired) == .mfaRequired)
        #expect(APIError.wrap(FakeTransportError()) == .transport("The network connection was lost."))
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "broken"))
        if case .decoding = APIError.wrap(decoding) {} else { Issue.record("expected decoding") }
        #expect(APIError.isCancellation(CancellationError()))
        #expect(APIError.isCancellation(URLError(.cancelled)))
        #expect(!APIError.isCancellation(URLError(.timedOut)))
        #expect(!APIError.isCancellation(FakeTransportError()))
    }

    @Test func urlSessionTransportReportsConnectionFailures() async {
        let session = URLSessionTransport.makeSession()
        #expect(session.configuration.httpCookieStorage == nil)
        #expect(!session.configuration.httpShouldSetCookies)
        #expect(session.configuration.timeoutIntervalForRequest == 30)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 5
        let transport = URLSessionTransport(session: URLSession(configuration: configuration))
        let client = APIClient(baseURL: URL(string: "http://127.0.0.1:9")!, transport: transport)
        await #expect(throws: APIError.self) { try await client.ping() }
    }
}
