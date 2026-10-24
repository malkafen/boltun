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

    public static func from(status: Int, data: Data) -> APIError {
        let body = try? MattermostJSON.decoder.decode(ServerErrorBody.self, from: data)
        if status == 401 {
            if body?.id == "mfa.validate_token.authenticate.app_error" || body?.id == "api.context.mfa_required.app_error" {
                return .mfaRequired
            }
            return .unauthorized(body)
        }
        if body?.id == "mfa.validate_token.authenticate.app_error" { return .mfaRequired }
        return .server(status: status, body: body)
    }

    public static func wrap(_ error: Error) -> APIError {
        if let error = error as? APIError { return error }
        if let error = error as? DecodingError { return .decoding(String(describing: error)) }
        return .transport(error.localizedDescription)
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
