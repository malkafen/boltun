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
        content
            .background(Theme.content)
            .environment(\.fontScale, model.settings.fontScale)
            .environment(\.spellChecking, model.settings.spellChecking)
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
