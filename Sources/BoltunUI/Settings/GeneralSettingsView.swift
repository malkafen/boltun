import BoltunKit
import SwiftUI

public struct GeneralSettingsView: View {
    @Bindable var viewModel: GeneralSettingsViewModel

    public init(viewModel: GeneralSettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        @Bindable var model = viewModel.model
        Form {
            Section("Startup") {
                Toggle("Launch Boltun at login", isOn: $viewModel.launchAtLogin)
                if let error = viewModel.loginItemError {
                    Text(error).font(.system(size: 11)).foregroundStyle(Theme.error)
                }
                Toggle("Show icon in the menu bar", isOn: $model.settings.showMenuBarIcon)
            }
            Section("Notifications") {
                Toggle("Show notifications for mentions and direct messages", isOn: $model.settings.notificationsEnabled)
                Toggle("Play a sound", isOn: $model.settings.notificationSound)
                    .disabled(!model.settings.notificationsEnabled)
                Toggle("Bounce the Dock icon on mention", isOn: $model.settings.bounceDockIcon)
                Toggle("Show unread badge on the Dock icon", isOn: $model.settings.showUnreadBadge)
            }
            Section("Messages") {
                Toggle(isOn: $model.settings.collapsedThreads) {
                    Text("Collapsed reply threads")
                    Text("Show replies in the thread pane instead of the channel.")
                }
                Toggle(isOn: $model.settings.showReadStatus) {
                    Text("Show read status")
                    Text("Mark your direct and group messages once the other members have seen them.")
                }
                Toggle("Check spelling while typing", isOn: $model.settings.spellChecking)
                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $model.settings.fontScale, in: AppRouter.fontScaleRange, step: AppRouter.fontScaleStep)
                            .frame(width: 160)
                        Text("\(Int((model.settings.fontScale * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Section("Downloads") {
                LabeledContent("Save files to") {
                    HStack {
                        Text(viewModel.downloadLocationDisplay)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(Theme.textSecondary)
                        Button("Choose…") { viewModel.chooseDownloadLocation() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
