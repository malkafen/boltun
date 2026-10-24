import SwiftUI

public struct WelcomeView: View {
    let onAddServer: () -> Void

    public init(onAddServer: @escaping () -> Void) {
        self.onAddServer = onAddServer
    }

    public var body: some View {
        VStack(spacing: 18) {
            BrandMark(size: 96)
            VStack(spacing: 6) {
                Text("Welcome to Boltun")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("A fast, native Mattermost client. Connect to one or more servers to get started.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            Button(action: onAddServer) {
                Label("Add Server", systemImage: "plus")
                    .padding(.horizontal, 20)
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(width: 200)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("welcome-add-server")
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.content)
    }
}
