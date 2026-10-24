import BoltunKit
import SwiftUI

public struct LoginView: View {
    @State private var viewModel: LoginViewModel
    let onSuccess: () -> Void
    let onCancel: (() -> Void)?

    public init(model: AppModel, serverId: UUID, config: ClientConfig? = nil, onSuccess: @escaping () -> Void, onCancel: (() -> Void)? = nil) {
        _viewModel = State(initialValue: LoginViewModel(model: model, serverId: serverId, config: config))
        self.onSuccess = onSuccess
        self.onCancel = onCancel
    }

    init(viewModel: LoginViewModel, onSuccess: @escaping () -> Void = {}, onCancel: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onSuccess = onSuccess
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch viewModel.step {
            case .credentials:
                if viewModel.allowsPasswordLogin { credentialsForm }
            case .mfa:
                mfaForm
            case .token:
                tokenForm
            }
            InlineError(message: viewModel.errorMessage)
            actions
            if viewModel.step == .credentials, !viewModel.ssoProviders.isEmpty { ssoSection }
            alternatives
        }
        .padding(24)
        .frame(width: 420)
        .background(Theme.panel)
        .task { await viewModel.loadConfig() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrandMark(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Log in to \(viewModel.siteName)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(viewModel.server?.url.absoluteString ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.bottom, 4)
    }

    private var credentialsForm: some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                FieldLabel(text: viewModel.loginIdPlaceholder)
                TextField(viewModel.loginIdPlaceholder, text: $viewModel.loginId)
                    .textFieldStyle(FormFieldStyle())
                    .textContentType(.username)
                    .onSubmit(submit)
                    .accessibilityIdentifier("login-id")
            }
            VStack(spacing: 6) {
                FieldLabel(text: "Password")
                SecureField("Password", text: $viewModel.password)
                    .textFieldStyle(FormFieldStyle())
                    .textContentType(.password)
                    .onSubmit(submit)
                    .accessibilityIdentifier("password")
            }
        }
    }

    private var mfaForm: some View {
        VStack(spacing: 6) {
            Text("Enter the code from your authenticator app.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("MFA code", text: $viewModel.mfaCode)
                .textFieldStyle(FormFieldStyle())
                .textContentType(.oneTimeCode)
                .onSubmit(submit)
                .accessibilityIdentifier("mfa-code")
        }
    }

    private var tokenForm: some View {
        VStack(spacing: 6) {
            FieldLabel(text: "Personal access token")
            SecureField("Token", text: $viewModel.accessToken)
                .textFieldStyle(FormFieldStyle())
                .onSubmit(submit)
                .accessibilityIdentifier("access-token")
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            if viewModel.step != .credentials || viewModel.allowsPasswordLogin {
                Button(action: submit) {
                    HStack(spacing: 8) {
                        if viewModel.isWorking, viewModel.activeProvider == nil {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(viewModel.step == .mfa ? "Verify" : "Log In")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canSubmit)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, 4)
    }

    private var ssoSection: some View {
        VStack(spacing: 8) {
            HStack {
                Rectangle().fill(Theme.separator).frame(height: 1)
                Text("or").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
            ForEach(viewModel.ssoProviders) { provider in
                Button {
                    Task { if await viewModel.signIn(with: provider) { onSuccess() } }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.activeProvider == provider {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: provider.systemImage)
                        }
                        Text("Continue with \(provider.title(config: viewModel.config ?? ClientConfig(values: [:])))")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(viewModel.isWorking)
            }
        }
    }

    private var alternatives: some View {
        HStack {
            switch viewModel.step {
            case .credentials:
                Button("Use a personal access token") { viewModel.useAccessToken() }
            case .mfa, .token:
                Button("Back to password login") { viewModel.useCredentials() }
            }
            Spacer()
        }
        .buttonStyle(.link)
        .font(.system(size: 12))
    }

    private func submit() {
        guard viewModel.canSubmit else { return }
        Task { if await viewModel.submit() { onSuccess() } }
    }
}
