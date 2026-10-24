import AppKit
import BoltunKit
import SwiftUI

public struct BoltunApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    public init() {}

    public var body: some Scene {
        let environment = delegate.environment
        Settings {
            SettingsView(model: environment.model, router: environment.router, loginItem: environment.loginItem)
        }
        .commands { AppCommands(router: environment.router) }

        MenuBarExtra(isInserted: Self.menuBarBinding(environment.model)) {
            StatusMenuContent(router: environment.router)
        } label: {
            Image(systemName: environment.model.badgeLabel == nil ? "bubble.left.and.bubble.right" : "bubble.left.and.bubble.right.fill")
        }
    }

    @MainActor
    static func menuBarBinding(_ model: AppModel) -> Binding<Bool> {
        Binding(
            get: { model.settings.showMenuBarIcon },
            set: { if model.settings.showMenuBarIcon != $0 { model.settings.showMenuBarIcon = $0 } }
        )
    }
}
