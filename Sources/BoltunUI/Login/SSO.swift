import AuthenticationServices
import BoltunKit
import Foundation
import Synchronization

public enum SSOProvider: String, CaseIterable, Hashable, Sendable, Identifiable {
    case gitlab
    case google
    case office365
    case openid
    case saml

    public static let callbackScheme = "mmauth"
    public static let callbackURL = "mmauth://callback"

    public var id: String { rawValue }

    public func title(config: ClientConfig) -> String {
        switch self {
        case .gitlab: return "GitLab"
        case .google: return "Google"
        case .office365: return "Entra ID"
        case .openid: return config["OpenIdButtonText"].flatMap { $0.isEmpty ? nil : $0 } ?? "OpenID Connect"
        case .saml: return config["SamlLoginButtonText"].flatMap { $0.isEmpty ? nil : $0 } ?? "SAML"
        }
    }

    public var systemImage: String {
        switch self {
        case .saml: return "building.columns"
        default: return "person.badge.key"
        }
    }

    public func isEnabled(in config: ClientConfig) -> Bool {
        switch self {
        case .gitlab: return config.enableGitLab
        case .google: return config.enableGoogle
        case .office365: return config.enableOffice365
        case .openid: return config.enableOpenId
        case .saml: return config.enableSaml
        }
    }

    public static func enabled(in config: ClientConfig) -> [SSOProvider] {
        allCases.filter { $0.isEnabled(in: config) }
    }

    public func loginURL(server: URL) -> URL {
        var components = URLComponents(url: server, resolvingAgainstBaseURL: false)!
        let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        switch self {
        case .saml:
            components.path = base + "/login/sso/saml"
            components.queryItems = [URLQueryItem(name: "action", value: "mobile"), URLQueryItem(name: "redirect_to", value: Self.callbackURL)]
        default:
            components.path = base + "/oauth/\(rawValue)/mobile_login"
            components.queryItems = [URLQueryItem(name: "redirect_to", value: Self.callbackURL)]
        }
        return components.url!
    }
}

public struct SSOCredentials: Equatable, Sendable {
    public var token: String
    public var csrf: String?

    public init(token: String, csrf: String? = nil) {
        self.token = token
        self.csrf = csrf
    }
}

public enum SSOError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case missingToken
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled: return "Sign-in was cancelled."
        case .missingToken: return "The server did not return a session token. Make sure mmauth:// is an allowed app custom URL scheme on the server."
        case .failed(let message): return message
        }
    }

    public static func parse(callback url: URL) -> Result<SSOCredentials, SSOError> {
        guard url.scheme?.lowercased() == SSOProvider.callbackScheme,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return .failure(.missingToken) }
        let values = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        if let token = values["MMAUTHTOKEN"], !token.isEmpty {
            return .success(SSOCredentials(token: token, csrf: values["MMCSRF"].flatMap { $0.isEmpty ? nil : $0 }))
        }
        if let message = values["error"] ?? values["message"], !message.isEmpty {
            return .failure(.failed(message))
        }
        return .failure(.missingToken)
    }
}

@MainActor
public protocol WebAuthenticating {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

@MainActor
public final class SystemWebAuthenticator: NSObject, WebAuthenticating, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    public override init() {}

    public func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = WebAuthenticationGate(continuation)
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme, completionHandler: Self.completionHandler(gate))
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                gate.resume(with: .failure(.failed("Could not start the sign-in session.")))
            }
        }
    }

    nonisolated static func completionHandler(_ gate: WebAuthenticationGate) -> @Sendable (URL?, (any Error)?) -> Void {
        { callback, error in gate.resume(with: result(callback: callback, error: error)) }
    }

    nonisolated static func result(callback: URL?, error: (any Error)?) -> Result<URL, SSOError> {
        if let callback {
            return .success(callback)
        }
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
            return .failure(.cancelled)
        }
        return .failure(.failed(error?.localizedDescription ?? "Sign-in failed."))
    }

    nonisolated public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? ASPresentationAnchor()
        }
    }
}

final class WebAuthenticationGate: Sendable {
    private let continuation: Mutex<CheckedContinuation<URL, any Error>?>

    init(_ continuation: CheckedContinuation<URL, any Error>) {
        self.continuation = Mutex(continuation)
    }

    func resume(with result: Result<URL, SSOError>) {
        let pending = continuation.withLock { value -> CheckedContinuation<URL, any Error>? in
            defer { value = nil }
            return value
        }
        pending?.resume(with: result.mapError { $0 as any Error })
    }
}
