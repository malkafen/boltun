import BoltunKit
import SwiftUI

public struct EditServerView: View {
    @State private var viewModel: EditServerViewModel
    let onDone: () -> Void

    public init(viewModel: EditServerViewModel, onDone: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onDone = onDone
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Server")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            VStack(spacing: 6) {
                FieldLabel(text: "Display name")
                TextField("Name", text: $viewModel.name)
                    .textFieldStyle(FormFieldStyle())
            }
            VStack(spacing: 6) {
                FieldLabel(text: "Server URL")
                TextField("https://chat.example.com", text: $viewModel.urlText)
                    .textFieldStyle(FormFieldStyle())
            }
            if viewModel.urlChanged {
                Text("Changing the URL signs you out of this server.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.away)
            }
            InlineError(message: viewModel.errorMessage)
            HStack(spacing: 10) {
                Button("Cancel", action: onDone)
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { if await viewModel.save() { onDone() } }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isSaving { ProgressView().controlSize(.small).tint(.white) }
                        Text("Save")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }
}
