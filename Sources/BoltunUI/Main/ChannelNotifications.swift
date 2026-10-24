import BoltunKit
import SwiftUI

struct ChannelNotificationsTarget: Identifiable, Hashable {
    var id: String
}

enum ChannelNotifyLabels {
    static func muteTitle(muted: Bool, isDirect: Bool) -> String {
        "\(muted ? "Unmute" : "Mute") \(isDirect ? "Conversation" : "Channel")"
    }

    static func teamMuteTitle(muted: Bool) -> String {
        muted ? "Unmute Notifications" : "Mute Notifications"
    }

    static func muteDescription(isDirect: Bool) -> String {
        "Turns off notifications for this \(isDirect ? "conversation" : "channel"). You will still see badges if you are mentioned."
    }

    static func level(_ level: NotificationLevel, fallback: NotificationLevel) -> String {
        switch level {
        case .default: return "Default (\(short(fallback)))"
        case .all: return "All new messages"
        case .mention: return "Mentions, direct messages and keywords only"
        case .none: return "Nothing"
        }
    }

    static func short(_ level: NotificationLevel) -> String {
        switch level {
        case .all: return "All new messages"
        case .none: return "Nothing"
        default: return "Mentions only"
        }
    }
}

@MainActor
@Observable
final class ChannelNotificationsModel {
    let workspace: Workspace
    let channelId: String
    private(set) var original: ChannelNotifySettings
    var settings: ChannelNotifySettings
    private(set) var saving = false

    init(workspace: Workspace, channelId: String) {
        self.workspace = workspace
        self.channelId = channelId
        let current = workspace.session.notifySettings(channelId: channelId)
        original = current
        settings = current
    }

    var session: ServerSession { workspace.session }

    var channel: Channel? { session.channels[channelId] }

    var isDirect: Bool { channel?.type.isDirectOrGroup ?? false }

    var channelName: String { channel.map { session.displayName(channel: $0) } ?? "" }

    var muteTitle: String { ChannelNotifyLabels.muteTitle(muted: settings.muted, isDirect: isDirect) }

    var desktopFallback: NotificationLevel {
        ChannelNotifySettings().desktopLevel(user: session.me)
    }

    var desktopLevel: NotificationLevel { settings.desktopLevel(user: session.me) }

    var showsThreadReplies: Bool { session.collapsedThreads && desktopLevel == .mention }

    var threadReplies: Bool {
        get { settings.desktopThreadsLevel(user: session.me) == .all }
        set { settings.desktopThreads = newValue ? .all : .mention }
    }

    var ignoreChannelMentions: Bool {
        get { settings.ignoresChannelMentions(user: session.me) }
        set { settings.ignoreChannelMentions = newValue ? .on : .off }
    }

    var hasChanges: Bool { !settings.changes(from: original).isEmpty }

    func save() async -> Bool {
        guard !saving else { return false }
        saving = true
        defer { saving = false }
        let applied = await session.applyNotifySettings(settings, channelId: channelId)
        if applied { original = settings }
        return applied
    }
}

struct ChannelNotificationsSheet: View {
    let workspace: Workspace
    let channelId: String
    @State private var model: ChannelNotificationsModel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .frame(width: 440)
        .background(Theme.content)
        .onAppear {
            if model == nil { model = ChannelNotificationsModel(workspace: workspace, channelId: channelId) }
        }
    }

    @ViewBuilder func content(_ model: ChannelNotificationsModel) -> some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Notification Preferences").scaledFont(16, weight: .bold)
                if !model.channelName.isEmpty {
                    Text(model.channelName).scaledFont(12).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $model.settings.muted) {
                    Text(model.isDirect ? "Mute conversation" : "Mute channel").scaledFont(13, weight: .medium)
                }
                Text(ChannelNotifyLabels.muteDescription(isDirect: model.isDirect))
                    .scaledFont(11.5)
                    .foregroundStyle(Theme.textSecondary)
                Toggle(isOn: $model.ignoreChannelMentions) {
                    Text("Ignore mentions for @channel, @here and @all").scaledFont(13, weight: .medium)
                }
            }
            if !model.settings.muted {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notify me about…").scaledFont(13, weight: .semibold)
                    Picker("", selection: $model.settings.desktop) {
                        ForEach(NotificationLevel.allCases, id: \.self) { level in
                            Text(ChannelNotifyLabels.level(level, fallback: model.desktopFallback)).tag(level)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    if model.showsThreadReplies {
                        Toggle(isOn: $model.threadReplies) {
                            Text("Notify me about replies to threads I follow").scaledFont(13)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        if await model.save() { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.hasChanges || model.saving)
            }
        }
        .toggleStyle(.checkbox)
        .padding(18)
    }
}

struct ChannelNotifyMenuItems: View {
    let workspace: Workspace
    let channelId: String
    let isDirect: Bool

    var body: some View {
        let muted = workspace.session.isMuted(channelId: channelId)
        Button(ChannelNotifyLabels.muteTitle(muted: muted, isDirect: isDirect)) {
            Task { await workspace.session.setMuted(channelId: channelId, !muted) }
        }
        Button("Notification Preferences…") {
            workspace.notificationPreferences = ChannelNotificationsTarget(id: channelId)
        }
    }
}

struct ChannelHeaderMenu: View {
    let workspace: Workspace
    let channel: Channel

    var body: some View {
        Menu {
            ChannelNotifyMenuItems(workspace: workspace, channelId: channel.id, isDirect: channel.type.isDirectOrGroup)
            if channel.type != .direct {
                Divider()
                Button("Members") { workspace.openMembers() }
            }
        } label: {
            Image(systemName: "ellipsis")
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointerStyle(.link)
        .help("Channel options")
    }
}

struct MutedBellIcon: View {
    var size: CGFloat = 10.5

    var body: some View {
        Image(systemName: "bell.slash.fill")
            .scaledFont(size)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityLabel("Muted")
    }
}

extension Workspace {
    func openNotificationPreferences() {
        guard let channelId = session.currentChannelId else { return }
        notificationPreferences = ChannelNotificationsTarget(id: channelId)
    }

    func toggleMuteCurrentChannel() async {
        guard let channelId = session.currentChannelId else { return }
        await session.toggleMuted(channelId: channelId)
    }
}
