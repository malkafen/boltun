import Foundation

public enum APIError: Error, Equatable, Sendable, LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case unauthorized(ServerErrorBody?)
    case mfaRequired
    case server(status: Int, body: ServerErrorBody?)
    case decoding(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "Invalid server URL: \(value)"
        case .invalidResponse:
            return "The server returned an invalid response."
        case .unauthorized(let body):
            return body?.message.nonEmpty ?? "Your session has expired. Please log in again."
        case .mfaRequired:
            return "Multi-factor authentication code required."
        case .server(let status, let body):
            return body?.message.nonEmpty ?? "Server error (\(status))."
        case .decoding(let detail):
            return "Unexpected server data: \(detail)"
        case .transport(let detail):
            return detail
        }
    }

    public var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    static let mfaErrorIds: Set<String> = [
        "mfa.validate_token.authenticate.app_error",
        "api.context.mfa_required.app_error",
        "api.user.check_user_mfa.bad_code.app_error",
    ]

    public static func from(status: Int, data: Data) -> APIError {
        let body = try? MattermostJSON.decoder.decode(ServerErrorBody.self, from: data)
        if let id = body?.id, mfaErrorIds.contains(id) { return .mfaRequired }
        if status == 401 { return .unauthorized(body) }
        return .server(status: status, body: body)
    }

    public static func wrap(_ error: Error) -> APIError {
        if let error = error as? APIError { return error }
        if let error = error as? DecodingError { return .decoding(String(describing: error)) }
        return .transport(error.localizedDescription)
    }

    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let error = error as? URLError, error.code == .cancelled { return true }
        return false
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
