import BoltunKit
import Foundation
import Observation

@MainActor
@Observable
public final class LoginViewModel {
    public enum Step: Equatable, Sendable {
        case credentials
        case mfa
        case token
    }

    public var loginId = ""
    public var password = ""
    public var mfaCode = ""
    public var accessToken = ""
    public private(set) var step: Step = .credentials
    public private(set) var isWorking = false
    public private(set) var errorMessage: String?
    public private(set) var config: ClientConfig?
    public private(set) var activeProvider: SSOProvider?

    public let serverId: UUID
    let model: AppModel
    let authenticator: WebAuthenticating

    public init(model: AppModel, serverId: UUID, config: ClientConfig? = nil, authenticator: WebAuthenticating? = nil) {
        self.model = model
        self.serverId = serverId
        self.config = config ?? model.session(for: serverId).flatMap { $0.config.values.isEmpty ? nil : $0.config }
        self.authenticator = authenticator ?? SystemWebAuthenticator()
    }

    public var server: ServerConfig? { model.servers.first { $0.id == serverId } }

    public var siteName: String { config?.siteName ?? server?.name ?? "Mattermost" }

    public var ssoProviders: [SSOProvider] { config.map(SSOProvider.enabled(in:)) ?? [] }

    public var allowsPasswordLogin: Bool {
        guard let config else { return true }
        return config.enableSignInWithEmail || config.enableSignInWithUsername || config["EnableLdap"] == "true"
    }

    public var loginIdPlaceholder: String {
        guard let config else { return "Email or username" }
        switch (config.enableSignInWithEmail, config.enableSignInWithUsername || config["EnableLdap"] == "true") {
        case (true, false): return "Email"
        case (false, true): return "Username"
        default: return "Email or username"
        }
    }

    public var canSubmit: Bool {
        guard !isWorking else { return false }
        switch step {
        case .credentials: return !loginId.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
        case .mfa: return !mfaCode.trimmingCharacters(in: .whitespaces).isEmpty
        case .token: return !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public func loadConfig() async {
        guard config == nil, let server else { return }
        config = try? await model.validate(url: server.url.absoluteString).1
    }

    public func useAccessToken() {
        step = .token
        errorMessage = nil
    }

    public func useCredentials() {
        step = .credentials
        mfaCode = ""
        errorMessage = nil
    }

    @discardableResult
    public func submit() async -> Bool {
        guard canSubmit else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            switch step {
            case .credentials:
                try await model.login(serverId: serverId, loginId: loginId.trimmingCharacters(in: .whitespaces), password: password)
            case .mfa:
                try await model.login(serverId: serverId, loginId: loginId.trimmingCharacters(in: .whitespaces), password: password, mfaToken: mfaCode.trimmingCharacters(in: .whitespaces))
            case .token:
                try await model.login(serverId: serverId, accessToken: accessToken)
            }
            return true
        } catch APIError.mfaRequired where step == .credentials {
            step = .mfa
            return false
        } catch {
            errorMessage = Self.describe(error, step: step)
            if step == .mfa { mfaCode = "" }
            return false
        }
    }

    @discardableResult
    public func signIn(with provider: SSOProvider) async -> Bool {
        guard let server, !isWorking else { return false }
        isWorking = true
        activeProvider = provider
        errorMessage = nil
        defer {
            isWorking = false
            activeProvider = nil
        }
        do {
            let callback = try await authenticator.authenticate(url: provider.loginURL(server: server.url), callbackScheme: SSOProvider.callbackScheme)
            let credentials = try SSOError.parse(callback: callback).get()
            try await model.login(serverId: serverId, accessToken: credentials.token)
            return true
        } catch SSOError.cancelled {
            return false
        } catch {
            errorMessage = Self.describe(error, step: step)
            return false
        }
    }

    static func describe(_ error: Error, step: Step) -> String {
        if let error = error as? SSOError { return error.localizedDescription }
        switch APIError.wrap(error) {
        case .unauthorized(let body) where step == .token:
            return body?.message.isEmpty == false ? body!.message : "The access token is invalid."
        case .unauthorized(let body):
            return body?.message.isEmpty == false ? body!.message : "Incorrect username or password."
        case .mfaRequired:
            return "The MFA code is incorrect."
        case let other:
            return other.localizedDescription
        }
    }
}
