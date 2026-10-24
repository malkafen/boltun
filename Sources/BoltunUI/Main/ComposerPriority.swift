import BoltunKit
import SwiftUI

struct ComposerReadInfoLabels: View {
    let state: ComposerState

    var body: some View {
        let priority = state.priority
        HStack(spacing: 6) {
            if state.supportsPriority && !priority.isDefault {
                PostPriorityBadge(level: priority.priority)
                if priority.requestedAck {
                    ComposerReadInfoChip(systemName: "checkmark.circle", title: "Requested acknowledgement", tint: Theme.acknowledged)
                }
                if priority.persistentNotifications {
                    ComposerReadInfoChip(systemName: "bell.badge", title: "Persistent notifications", tint: Theme.priorityUrgent)
                }
                Button { state.clearPriority() } label: {
                    Image(systemName: "xmark.circle.fill").scaledFont(11).foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Remove message priority")
            }
            if state.supportsBurnOnRead && state.burnOnRead {
                ComposerReadInfoChip(
                    systemName: "flame.fill",
                    title: BurnOnReadText.composerLabel(durationMinutes: state.session.burnOnReadDurationMinutes),
                    tint: Theme.burnOnRead
                )
                Button { state.setBurnOnRead(false) } label: {
                    Image(systemName: "xmark.circle.fill").scaledFont(11).foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Turn off burn on read")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 5)
    }
}

struct ComposerReadInfoChip: View {
    let systemName: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
            Text(title)
        }
        .scaledFont(10.5, weight: .semibold)
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

struct PostPriorityPickerButton: View {
    let state: ComposerState
    @State private var shown = false

    var body: some View {
        IconButton(
            systemName: state.priority.priority.isLabelled ? "exclamationmark.circle.fill" : "exclamationmark.circle",
            help: "Message priority",
            tint: state.priority.priority.isLabelled ? Theme.priorityImportant : Theme.textSecondary
        ) { shown = true }
            .popover(isPresented: $shown, arrowEdge: .top) {
                PostPriorityPicker(
                    priority: state.priority,
                    acknowledgementsEnabled: state.session.acknowledgementsEnabled,
                    persistentNotificationsEnabled: state.session.persistentNotificationsEnabled,
                    persistentNotificationIntervalMinutes: state.session.config.persistentNotificationIntervalMinutes,
                    onCancel: { shown = false },
                    onApply: { applied in
                        shown = false
                        state.apply(priority: applied)
                    }
                )
            }
    }
}

struct PostPriorityPicker: View {
    let priority: PostPriority
    var acknowledgementsEnabled = false
    var persistentNotificationsEnabled = false
    var persistentNotificationIntervalMinutes = 5
    let onCancel: () -> Void
    let onApply: (PostPriority) -> Void
    @State private var draft: PostPriority

    init(
        priority: PostPriority,
        acknowledgementsEnabled: Bool = false,
        persistentNotificationsEnabled: Bool = false,
        persistentNotificationIntervalMinutes: Int = 5,
        onCancel: @escaping () -> Void,
        onApply: @escaping (PostPriority) -> Void
    ) {
        self.priority = priority
        self.acknowledgementsEnabled = acknowledgementsEnabled
        self.persistentNotificationsEnabled = persistentNotificationsEnabled
        self.persistentNotificationIntervalMinutes = persistentNotificationIntervalMinutes
        self.onCancel = onCancel
        self.onApply = onApply
        _draft = State(initialValue: priority)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Message priority")
                .scaledFont(12.5, weight: .semibold)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            Divider()
            ForEach(PostPriorityLevel.allCases, id: \.self) { level in
                levelRow(level)
            }
            if acknowledgementsEnabled {
                Divider()
                toggleRow(
                    systemName: "checkmark.circle",
                    title: "Request acknowledgement",
                    description: "An acknowledgement button will appear with your message",
                    isOn: Binding(get: { draft.requestedAck }, set: { draft.requestedAck = $0 })
                )
            }
            if persistentNotificationsEnabled && draft.priority == .urgent {
                toggleRow(
                    systemName: "bell.badge",
                    title: "Send persistent notifications",
                    description: PostPriorityText.persistentNotificationsDescription(intervalMinutes: persistentNotificationIntervalMinutes),
                    isOn: Binding(get: { draft.persistentNotifications }, set: { draft.persistentNotifications = $0 })
                )
            }
            Divider()
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                Button("Apply") { onApply(draft) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(width: 300)
    }

    func levelRow(_ level: PostPriorityLevel) -> some View {
        Button {
            draft.priority = level
            if level != .urgent { draft.persistentNotifications = false }
            if !acknowledgementsEnabled { onApply(draft) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: PostPriorityText.icon(level))
                    .frame(width: 18)
                    .foregroundStyle(level == .urgent ? Theme.priorityUrgent : (level == .important ? Theme.priorityImportant : Theme.textSecondary))
                Text(PostPriorityText.menuTitle(level))
                    .scaledFont(12.5)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                if draft.priority == level {
                    Image(systemName: "checkmark").scaledFont(11, weight: .bold).foregroundStyle(Theme.link)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityLabel(PostPriorityText.menuTitle(level))
    }

    func toggleRow(systemName: String, title: String, description: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: systemName).frame(width: 18).foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).scaledFont(12.5).foregroundStyle(Theme.textPrimary)
                    Text(description).scaledFont(11).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

struct BurnOnReadToggleButton: View {
    let state: ComposerState

    var body: some View {
        IconButton(
            systemName: state.burnOnRead ? "flame.fill" : "flame",
            help: state.burnOnRead
                ? "Burn on read is on. The message is deleted \(state.session.burnOnReadDurationMinutes) minutes after it is opened."
                : "Send as a burn-on-read message",
            tint: state.burnOnRead ? Theme.burnOnRead : Theme.textSecondary
        ) {
            state.setBurnOnRead(!state.burnOnRead)
        }
    }
}
