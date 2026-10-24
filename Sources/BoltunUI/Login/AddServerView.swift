import BoltunKit
import SwiftUI

public struct AddServerView: View {
    @State private var viewModel: AddServerViewModel
    let onAdded: (ServerConfig) -> Void
    let onCancel: (() -> Void)?

    public init(model: AppModel, onAdded: @escaping (ServerConfig) -> Void, onCancel: (() -> Void)? = nil) {
        _viewModel = State(initialValue: AddServerViewModel(model: model))
        self.onAdded = onAdded
        self.onCancel = onCancel
    }

    init(viewModel: AddServerViewModel, onAdded: @escaping (ServerConfig) -> Void = { _ in }, onCancel: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onAdded = onAdded
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BrandMark(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a Mattermost server")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Enter the address you use to reach your team.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.bottom, 4)

            VStack(spacing: 6) {
                FieldLabel(text: "Server URL")
                TextField("https://chat.example.com", text: $viewModel.urlText)
                    .textFieldStyle(FormFieldStyle())
                    .textContentType(.URL)
                    .onSubmit(submit)
                    .accessibilityIdentifier("server-url")
            }
            VStack(spacing: 6) {
                FieldLabel(text: "Display name")
                TextField(viewModel.namePlaceholder, text: $viewModel.name)
                    .textFieldStyle(FormFieldStyle())
                    .onSubmit(submit)
                    .accessibilityIdentifier("server-name")
            }
            if let siteName = viewModel.siteName {
                Label("Found \(siteName)", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.online)
            }
            InlineError(message: viewModel.errorMessage)

            HStack(spacing: 10) {
                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(SecondaryButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
                Button(action: submit) {
                    HStack(spacing: 8) {
                        if viewModel.isValidating {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(viewModel.isValidating ? "Checking…" : "Continue")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canSubmit)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 420)
        .background(Theme.panel)
    }

    private func submit() {
        guard viewModel.canSubmit else { return }
        Task {
            if let server = await viewModel.submit() { onAdded(server) }
        }
    }
}
