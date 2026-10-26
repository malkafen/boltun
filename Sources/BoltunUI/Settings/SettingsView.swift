import BoltunKit
import SwiftUI

public struct SettingsView: View {
    let model: AppModel
    @Bindable var router: AppRouter
    @State private var general: GeneralSettingsViewModel
    @State private var notifications: NotificationSettingsViewModel

    public init(model: AppModel, router: AppRouter, loginItem: LoginItemControlling) {
        self.model = model
        self.router = router
        _general = State(initialValue: GeneralSettingsViewModel(model: model, loginItem: loginItem))
        _notifications = State(initialValue: NotificationSettingsViewModel(model: model))
    }

    public var body: some View {
        TabView(selection: $router.settingsTab) {
            ServersSettingsView(model: model)
                .tabItem { Label(SettingsTab.servers.title, systemImage: SettingsTab.servers.systemImage) }
                .tag(SettingsTab.servers)
            GeneralSettingsView(viewModel: general)
                .tabItem { Label(SettingsTab.general.title, systemImage: SettingsTab.general.systemImage) }
                .tag(SettingsTab.general)
            NotificationSettingsView(viewModel: notifications)
                .tabItem { Label(SettingsTab.notifications.title, systemImage: SettingsTab.notifications.systemImage) }
                .tag(SettingsTab.notifications)
            AboutSettingsView(info: .current, openURL: router.openExternalURL)
                .tabItem { Label(SettingsTab.about.title, systemImage: SettingsTab.about.systemImage) }
                .tag(SettingsTab.about)
        }
        .frame(width: 600, height: 560)
        .preferredColorScheme(.dark)
        .onChange(of: router.settingsTab) { _, tab in
            if tab == .notifications { notifications.syncIfUnchanged() }
        }
    }
}
