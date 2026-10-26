import BoltunKit
import SwiftUI

enum AccountNotifyLabels {
    static func level(_ level: NotificationLevel) -> String {
        switch level {
        case .all: return "All new messages"
        case .none: return "Nothing"
        case .mention, .default: return "Mentions, direct messages and keywords"
        }
    }

    static let levelFootnote = "Muted channels and teams only notify you when you are mentioned. Override a single channel from its Notification Preferences."

    static func firstName(_ name: String) -> String {
        name.isEmpty ? "Your first name (not set on this server)" : "Your first name “\(name)”"
    }

    static func username(_ name: String) -> String {
        "Your username “\(name)” without the @"
    }

    static func usernameFootnote(_ name: String) -> String {
        "@\(name) always notifies you."
    }

    static let channelWide = "Channel-wide mentions @channel, @all and @here"
    static let keywordsPrompt = "deploy, release, oncall"
    static let keywordsFootnote = "Separate keywords with commas. Keywords are not case-sensitive."
}

public struct NotificationSettingsView: View {
    @Bindable var viewModel: NotificationSettingsViewModel

    public init(viewModel: NotificationSettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        @Bindable var model = viewModel.model
        Form {
            Section("This Mac") {
                Toggle("Show desktop notifications", isOn: $model.settings.notificationsEnabled)
                Toggle("Play a sound", isOn: $model.settings.notificationSound)
                    .disabled(!model.settings.notificationsEnabled)
                Toggle("Bounce the Dock icon for new notifications", isOn: $model.settings.bounceDockIcon)
                Toggle("Show unread badge on the Dock icon", isOn: $model.settings.showUnreadBadge)
            }
            if viewModel.servers.count > 1 {
                Section {
                    Picker("Server", selection: $viewModel.serverId) {
                        ForEach(viewModel.servers) { server in
                            Text(server.name).tag(Optional(server.id))
                        }
                    }
                }
            }
            if viewModel.isAvailable {
                accountSections
            } else {
                Section("Account") {
                    Text(viewModel.unavailableMessage).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: viewModel.user?.notifyProps) { viewModel.syncIfUnchanged() }
        .onChange(of: viewModel.user?.id) { viewModel.reload() }
    }

    @ViewBuilder var accountSections: some View {
        Section {
            Picker("Notify me about", selection: $viewModel.settings.desktop) {
                ForEach(AccountNotifySettings.levels, id: \.self) { level in
                    Text(AccountNotifyLabels.level(level)).tag(level)
                }
            }
            .pickerStyle(.radioGroup)
            if viewModel.showsThreadReplies {
                Toggle("Notify me about replies to threads I follow", isOn: $viewModel.settings.threadReplies)
            }
        } header: {
            Text(viewModel.servers.count > 1 ? "Account on \(viewModel.serverName)" : "Account")
        } footer: {
            footnote(AccountNotifyLabels.levelFootnote)
        }
        Section {
            Toggle(AccountNotifyLabels.firstName(viewModel.firstName), isOn: $viewModel.settings.firstName)
                .disabled(viewModel.firstName.isEmpty && !viewModel.settings.firstName)
            Toggle(isOn: $viewModel.settings.username) {
                Text(AccountNotifyLabels.username(viewModel.username))
                Text(AccountNotifyLabels.usernameFootnote(viewModel.username))
            }
            Toggle(AccountNotifyLabels.channelWide, isOn: $viewModel.settings.channelWide)
            TextField("Other keywords", text: $viewModel.keywordsText, prompt: Text(AccountNotifyLabels.keywordsPrompt))
                .accessibilityIdentifier("settings-notification-keywords")
        } header: {
            Text("Keywords that trigger notifications")
        } footer: {
            footnote(AccountNotifyLabels.keywordsFootnote)
        }
        Section {
            HStack {
                if let error = viewModel.errorMessage {
                    Text(error).font(.system(size: 11)).foregroundStyle(Theme.error).lineLimit(2)
                }
                Spacer()
                Button("Revert") { viewModel.revert() }
                    .disabled(!viewModel.hasChanges || viewModel.saving)
                Button("Save") { Task { await viewModel.save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.hasChanges || viewModel.saving)
            }
        }
    }

    func footnote(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
    }
}
