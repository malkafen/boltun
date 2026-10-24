import AppKit
import BoltunKit
import Foundation
import SwiftUI
import Testing
@testable import BoltunUI

@MainActor
struct LoginAddServerTests {
    @Test func validatesAndAddsServer() async {
        let harness = Harness()
        let viewModel = AddServerViewModel(model: harness.model)
        #expect(!viewModel.canSubmit)
        #expect(viewModel.namePlaceholder == "Server name")
        #expect(await viewModel.submit() == nil)
        viewModel.urlText = "http://chat.example.com:8065/"
        #expect(viewModel.namePlaceholder == "chat.example.com")
        #expect(viewModel.canSubmit)
        let server = await viewModel.submit()
        #expect(server?.name == "Test Site")
        #expect(server?.url == URL(string: "http://chat.example.com:8065"))
        #expect(viewModel.siteName == "Test Site")
        #expect(viewModel.namePlaceholder == "Test Site")
        #expect(viewModel.errorMessage == nil)
        #expect(harness.model.servers.count == 1)
        #expect(harness.model.needsLogin.contains(server!.id))
        viewModel.urlText = "http://other.example.com"
        #expect(viewModel.state == .idle)
    }

    @Test func prefersCustomNameAndAvoidsDuplicateSiteNames() async {
        let harness = Harness(servers: [ServerConfig(name: "Test Site", url: URL(string: "https://first.example.com")!)])
        let viewModel = AddServerViewModel(model: harness.model, urlText: "http://second.example.com")
        await viewModel.validate()
        #expect(viewModel.resolvedName == "second.example.com")
        viewModel.name = "  Work  "
        #expect(viewModel.resolvedName == "Work")
        #expect(await viewModel.submit()?.name == "Work")
    }

    @Test func reportsErrors() async {
        let transport = FakeTransport()
        let harness = Harness(transport: transport)
        let viewModel = AddServerViewModel(model: harness.model, urlText: "ftp://bad")
        #expect(!(await viewModel.validate()))
        #expect(viewModel.errorMessage?.contains("valid server URL") == true)
        transport.set("GET system/ping", status: 404, "{}")
        viewModel.urlText = "http://chat.example.com"
        #expect(!(await viewModel.validate()))
        #expect(viewModel.errorMessage == "No Mattermost server was found at this address.")
        transport.set("GET system/ping", status: 200, "<html>")
        #expect(!(await viewModel.validate()))
        #expect(viewModel.errorMessage == "This address does not look like a Mattermost server.")
        transport.set("GET system/ping", status: 500, #"{"id":"x","message":"Down for maintenance"}"#)
        #expect(!(await viewModel.validate()))
        #expect(viewModel.errorMessage == "Down for maintenance")
        transport.set("GET system/ping", status: 500, "Internal Server Error")
        #expect(!(await viewModel.validate()))
        #expect(viewModel.errorMessage == "No Mattermost server was found at this address.")
        #expect(!viewModel.isValidating)
    }

    @Test func rendersStates() async {
        let harness = Harness()
        let viewModel = AddServerViewModel(model: harness.model, urlText: "http://chat.example.com")
        #expect(Render.png(AddServerView(viewModel: viewModel, onCancel: {}), name: "login-add-server") != nil)
        await viewModel.validate()
        #expect(Render.png(AddServerView(viewModel: viewModel), name: "login-add-server-validated") != nil)
        let failing = AddServerViewModel(model: harness.model, urlText: "ftp://x")
        await failing.validate()
        #expect(Render.png(AddServerView(viewModel: failing), name: "login-add-server-error") != nil)
        #expect(Render.png(AddServerView(model: harness.model, onAdded: { _ in }, onCancel: {}), name: "login-add-server-public") != nil)
    }
}

@MainActor
struct LoginViewModelTests {
    let server = Harness.server()

    func make(_ transport: FakeTransport = FakeTransport(), config: ClientConfig? = nil, auth: FakeWebAuthenticator? = nil) -> (Harness, LoginViewModel) {
        let harness = Harness(servers: [server], transport: transport)
        return (harness, LoginViewModel(model: harness.model, serverId: server.id, config: config, authenticator: auth))
    }

    @Test func logsInWithCredentials() async {
        let (harness, viewModel) = make()
        #expect(!viewModel.canSubmit)
        viewModel.loginId = " boltun "
        viewModel.password = "pw"
        #expect(viewModel.canSubmit)
        #expect(await viewModel.submit())
        #expect(harness.credentials.token(for: server.id) == "session-token")
        #expect(!harness.model.needsLogin.contains(server.id))
        #expect(harness.model.session(for: server.id)?.connection == .connected)
        let body = harness.transport.requests(matching: "POST users/login").first?.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(body.contains(#""login_id":"boltun""#))
    }

    @Test func handlesMFA() async {
        let transport = FakeTransport()
        transport.set("POST users/login", status: 401, #"{"id":"mfa.validate_token.authenticate.app_error","message":"MFA"}"#)
        let (harness, viewModel) = make(transport)
        viewModel.loginId = "boltun"
        viewModel.password = "pw"
        #expect(!(await viewModel.submit()))
        #expect(viewModel.step == .mfa)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.canSubmit)
        viewModel.mfaCode = "000000"
        #expect(!(await viewModel.submit()))
        #expect(viewModel.errorMessage == "The MFA code is incorrect.")
        #expect(viewModel.mfaCode == "")
        transport.set("POST users/login", status: 200, FakeTransport.me, headers: ["Token": "mfa-token"])
        viewModel.mfaCode = "123456"
        #expect(await viewModel.submit())
        #expect(harness.credentials.token(for: server.id) == "mfa-token")
        let body = transport.requests(matching: "POST users/login").last?.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(body.contains(#""token":"123456""#))
        viewModel.useCredentials()
        #expect(viewModel.step == .credentials)
    }

    @Test func showsServerErrors() async {
        let transport = FakeTransport()
        transport.set("POST users/login", status: 401, #"{"id":"api.user.login.invalid_credentials","message":"Enter a valid email or username and/or password."}"#)
        let (_, viewModel) = make(transport)
        viewModel.loginId = "boltun"
        viewModel.password = "bad"
        #expect(!(await viewModel.submit()))
        #expect(viewModel.errorMessage == "Enter a valid email or username and/or password.")
        transport.set("POST users/login", status: 401, "{}")
        #expect(!(await viewModel.submit()))
        #expect(viewModel.errorMessage == "Incorrect username or password.")
        transport.set("POST users/login", status: 503, "{}")
        #expect(!(await viewModel.submit()))
        #expect(viewModel.errorMessage == "Server error (503).")
    }

    @Test func logsInWithAccessToken() async {
        let transport = FakeTransport()
        let (harness, viewModel) = make(transport)
        viewModel.useAccessToken()
        #expect(viewModel.step == .token)
        viewModel.accessToken = "  pat  "
        #expect(await viewModel.submit())
        #expect(harness.credentials.token(for: server.id) == "pat")
        transport.set("GET users/me", status: 401, "{}")
        viewModel.accessToken = "bad"
        #expect(!(await viewModel.submit()))
        #expect(viewModel.errorMessage == "The access token is invalid.")
        transport.set("GET users/me", status: 401, #"{"id":"x","message":"Token revoked"}"#)
        #expect(!(await viewModel.submit()))
        #expect(viewModel.errorMessage == "Token revoked")
    }

    @Test func loadsConfigAndProviders() async {
        let (_, viewModel) = make()
        #expect(viewModel.ssoProviders.isEmpty)
        #expect(viewModel.siteName == "Alpha")
        #expect(viewModel.allowsPasswordLogin)
        #expect(viewModel.loginIdPlaceholder == "Email or username")
        await viewModel.loadConfig()
        #expect(viewModel.siteName == "Test Site")
        #expect(viewModel.ssoProviders == [.gitlab, .saml])
        await viewModel.loadConfig()
    }

    @Test func adaptsToLoginMethods() {
        let emailOnly = ClientConfig(values: ["EnableSignInWithUsername": "false"])
        #expect(make(config: emailOnly).1.loginIdPlaceholder == "Email")
        let usernameOnly = ClientConfig(values: ["EnableSignInWithEmail": "false"])
        #expect(make(config: usernameOnly).1.loginIdPlaceholder == "Username")
        let ssoOnly = ClientConfig(values: ["EnableSignInWithEmail": "false", "EnableSignInWithUsername": "false", "EnableSignUpWithGoogle": "true"])
        let viewModel = make(config: ssoOnly).1
        #expect(!viewModel.allowsPasswordLogin)
        #expect(viewModel.ssoProviders == [.google])
    }

    @Test func signsInWithSSO() async {
        let auth = FakeWebAuthenticator(result: .success(URL(string: "mmauth://callback?MMAUTHTOKEN=sso-token&MMCSRF=csrf")!))
        let (harness, viewModel) = make(auth: auth)
        #expect(await viewModel.signIn(with: .gitlab))
        #expect(harness.credentials.token(for: server.id) == "sso-token")
        #expect(auth.requests.first?.0.absoluteString == "http://chat.example.com:8065/oauth/gitlab/mobile_login?redirect_to=mmauth://callback")
        #expect(auth.requests.first?.1 == "mmauth")
        #expect(viewModel.activeProvider == nil)
        #expect(!viewModel.isWorking)
    }

    @Test func handlesSSOFailures() async {
        let auth = FakeWebAuthenticator(result: .failure(SSOError.cancelled))
        let (_, viewModel) = make(auth: auth)
        #expect(!(await viewModel.signIn(with: .saml)))
        #expect(viewModel.errorMessage == nil)
        auth.result = .success(URL(string: "mmauth://callback")!)
        #expect(!(await viewModel.signIn(with: .saml)))
        #expect(viewModel.errorMessage == SSOError.missingToken.localizedDescription)
        auth.result = .failure(SSOError.failed("Denied"))
        #expect(!(await viewModel.signIn(with: .openid)))
        #expect(viewModel.errorMessage == "Denied")
    }

    @Test func ignoresUnknownServer() async {
        let harness = Harness()
        let viewModel = LoginViewModel(model: harness.model, serverId: UUID(), authenticator: FakeWebAuthenticator(result: .failure(SSOError.cancelled)))
        #expect(!(await viewModel.signIn(with: .gitlab)))
        await viewModel.loadConfig()
        #expect(viewModel.siteName == "Mattermost")
    }

    @Test func rendersSteps() async {
        let auth = FakeWebAuthenticator(result: .failure(SSOError.cancelled))
        let transport = FakeTransport()
        transport.set("POST users/login", status: 401, #"{"id":"mfa.validate_token.authenticate.app_error","message":"MFA"}"#)
        let config = ClientConfig(values: ["SiteName": "Test Site", "EnableSignUpWithGitLab": "true", "EnableSaml": "true", "EnableSignUpWithOpenId": "true"])
        let (harness, viewModel) = make(transport, config: config, auth: auth)
        #expect(Render.png(LoginView(viewModel: viewModel, onCancel: {}), size: CGSize(width: 420, height: 560), name: "login-credentials") != nil)
        viewModel.loginId = "boltun"
        viewModel.password = "pw"
        await viewModel.submit()
        #expect(Render.png(LoginView(viewModel: viewModel), size: CGSize(width: 420, height: 400), name: "login-mfa") != nil)
        viewModel.useAccessToken()
        #expect(Render.png(LoginView(viewModel: viewModel), size: CGSize(width: 420, height: 400), name: "login-token") != nil)
        let ssoOnly = LoginViewModel(model: harness.model, serverId: server.id, config: ClientConfig(values: ["EnableSignInWithEmail": "false", "EnableSignInWithUsername": "false", "EnableSignUpWithGoogle": "true"]), authenticator: auth)
        #expect(Render.png(LoginView(viewModel: ssoOnly), size: CGSize(width: 420, height: 400), name: "login-sso-only") != nil)
        #expect(Render.png(LoginView(model: harness.model, serverId: server.id, onSuccess: {}), size: CGSize(width: 420, height: 400), name: "login-public") != nil)
    }

    @Test func rendersSetupFlow() async {
        let harness = Harness(servers: [server])
        #expect(Render.png(ServerSetupFlow(model: harness.model) {}, name: "login-flow-add") != nil)
        #expect(Render.png(ServerSetupFlow(model: harness.model, stage: .login(server.id)) {}, name: "login-flow-login") != nil)
        #expect(Render.png(BrandMark(size: 96), size: CGSize(width: 120, height: 120), name: "login-brand") != nil)
        #expect(Render.png(VStack { InlineError(message: nil); Text("x") }, size: CGSize(width: 100, height: 20), name: "login-no-error") != nil)
    }
}

struct LoginSSOTests {
    let server = URL(string: "https://chat.example.com")!

    @Test func buildsMobileLoginURLs() {
        #expect(SSOProvider.gitlab.loginURL(server: server).absoluteString == "https://chat.example.com/oauth/gitlab/mobile_login?redirect_to=mmauth://callback")
        #expect(SSOProvider.google.loginURL(server: server).absoluteString == "https://chat.example.com/oauth/google/mobile_login?redirect_to=mmauth://callback")
        #expect(SSOProvider.office365.loginURL(server: server).absoluteString == "https://chat.example.com/oauth/office365/mobile_login?redirect_to=mmauth://callback")
        #expect(SSOProvider.openid.loginURL(server: server).absoluteString == "https://chat.example.com/oauth/openid/mobile_login?redirect_to=mmauth://callback")
        #expect(SSOProvider.saml.loginURL(server: server).absoluteString == "https://chat.example.com/login/sso/saml?action=mobile&redirect_to=mmauth://callback")
        let nested = URL(string: "https://example.org/mm/")!
        #expect(SSOProvider.gitlab.loginURL(server: nested).absoluteString == "https://example.org/mm/oauth/gitlab/mobile_login?redirect_to=mmauth://callback")
    }

    @Test func detectsEnabledProviders() {
        let config = ClientConfig(values: [
            "EnableSignUpWithGitLab": "true", "EnableSignUpWithGoogle": "true", "EnableSignUpWithOffice365": "true",
            "EnableSignUpWithOpenId": "true", "EnableSaml": "true", "OpenIdButtonText": "Keycloak",
        ])
        #expect(SSOProvider.enabled(in: config) == SSOProvider.allCases)
        #expect(SSOProvider.enabled(in: ClientConfig(values: [:])).isEmpty)
        #expect(SSOProvider.openid.title(config: config) == "Keycloak")
        #expect(SSOProvider.saml.title(config: config) == "SAML")
        #expect(SSOProvider.gitlab.title(config: config) == "GitLab")
        #expect(SSOProvider.google.title(config: config) == "Google")
        #expect(SSOProvider.office365.title(config: config) == "Entra ID")
        #expect(SSOProvider.openid.title(config: ClientConfig(values: [:])) == "OpenID Connect")
        #expect(SSOProvider.saml.systemImage == "building.columns")
        #expect(SSOProvider.gitlab.systemImage == "person.badge.key")
        #expect(SSOProvider.gitlab.id == "gitlab")
    }

    @Test func parsesCallbacks() {
        #expect(SSOError.parse(callback: URL(string: "mmauth://callback?MMAUTHTOKEN=t&MMCSRF=c")!) == .success(SSOCredentials(token: "t", csrf: "c")))
        #expect(SSOError.parse(callback: URL(string: "mmauth://callback?MMAUTHTOKEN=t&MMCSRF=")!) == .success(SSOCredentials(token: "t")))
        #expect(SSOError.parse(callback: URL(string: "mmauth://callback?error=Access%20denied")!) == .failure(.failed("Access denied")))
        #expect(SSOError.parse(callback: URL(string: "mmauth://callback?MMAUTHTOKEN=")!) == .failure(.missingToken))
        #expect(SSOError.parse(callback: URL(string: "https://evil.example.com/?MMAUTHTOKEN=t")!) == .failure(.missingToken))
        #expect(SSOError.parse(callback: URL(string: "mmauth://callback")!) == .failure(.missingToken))
        #expect(SSOError.cancelled.localizedDescription == "Sign-in was cancelled.")
    }

    @Test @MainActor func systemAuthenticatorConstructs() {
        _ = SystemWebAuthenticator()
    }
}
