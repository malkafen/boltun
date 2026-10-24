import BoltunKit
import SwiftUI

public struct AppRootView: View {
    let model: AppModel
    @Bindable var router: AppRouter
    @Environment(\.openSettings) private var openSettings

    public init(model: AppModel, router: AppRouter) {
        self.model = model
        self.router = router
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let server = signedOutServer {
                SignedOutBanner(serverName: server.name) { router.presentLogin(serverId: server.id) }
            }
            content
        }
        .background(Theme.content)
        .environment(\.fontScale, model.settings.fontScale)
        .environment(\.appRouter, router)
        .preferredColorScheme(.dark)
        .sheet(item: $router.sheet) { sheet in
            sheetContent(sheet)
        }
        .onAppear {
            router.openSettingsWindow = { openSettings() }
            router.presentLoginIfNeeded()
        }
        .onChange(of: model.needsLogin) { router.presentLoginIfNeeded() }
        .onChange(of: model.selectedServerId) { router.presentLoginIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if model.servers.isEmpty {
            WelcomeView { router.presentAddServer() }
        } else {
            MainView(model: model, onAddServer: { router.presentAddServer() }, onLogin: { router.presentLogin(serverId: $0) })
        }
    }

    private var signedOutServer: ServerConfig? {
        guard router.currentServerNeedsLogin else { return nil }
        return model.selectedServer
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .addServer:
            ServerSetupFlow(model: model) { router.dismissSheet() }
        case .login(let serverId):
            ServerSetupFlow(model: model, stage: .login(serverId)) { router.dismissSheet() }
        }
    }
}

struct SignedOutBanner: View {
    let serverName: String
    let onLogin: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
            Text("You are signed out of \(serverName).")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button("Log In", action: onLogin)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Theme.warningBanner, ignoresSafeAreaEdges: [])
    }
}
