import BoltunKit
import SwiftUI

extension Theme {
    public static let priorityImportant = Color(red: 0.33, green: 0.56, blue: 0.95)
    public static let priorityImportantBackground = Color(red: 0.33, green: 0.56, blue: 0.95).opacity(0.18)
    public static let priorityUrgent = Color(red: 0.95, green: 0.38, blue: 0.38)
    public static let priorityUrgentBackground = Color(red: 0.95, green: 0.30, blue: 0.30).opacity(0.20)
    public static let acknowledged = Color(red: 0.24, green: 0.72, blue: 0.40)
    public static let acknowledgedBackground = Color(red: 0.24, green: 0.72, blue: 0.40).opacity(0.16)
    public static let burnOnRead = Color(red: 0.96, green: 0.54, blue: 0.22)
    public static let burnOnReadBackground = Color(red: 0.96, green: 0.54, blue: 0.22).opacity(0.14)
}

struct PostPriorityBadge: View {
    let level: PostPriorityLevel

    var color: Color { level == .urgent ? Theme.priorityUrgent : Theme.priorityImportant }

    var background: Color { level == .urgent ? Theme.priorityUrgentBackground : Theme.priorityImportantBackground }

    var body: some View {
        if let title = PostPriorityText.label(level) {
            HStack(spacing: 3) {
                Image(systemName: PostPriorityText.icon(level))
                Text(title)
            }
            .scaledFont(9.5, weight: .bold)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 3).fill(background))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(color.opacity(0.45)))
            .accessibilityLabel("\(PostPriorityText.menuTitle(level)) message")
        }
    }
}

struct AcknowledgementButton: View {
    let model: AcknowledgementRowModel
    let client: APIClient?
    let onToggle: () -> Void
    @State private var popoverShown = false

    init(model: AcknowledgementRowModel, client: APIClient?, popoverShown: Bool = false, onToggle: @escaping () -> Void) {
        self.model = model
        self.client = client
        self.onToggle = onToggle
        _popoverShown = State(initialValue: popoverShown)
    }

    var tint: Color { model.acknowledgedByMe ? Theme.acknowledged : Theme.textSecondary }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                HStack(spacing: 4) {
                    Image(systemName: model.acknowledgedByMe ? "checkmark.circle.fill" : "checkmark.circle")
                    Text(model.buttonText).monospacedDigit()
                }
                .scaledFont(11.5, weight: .semibold)
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .frame(minHeight: 22)
                .background(Capsule().fill(model.acknowledgedByMe ? Theme.acknowledgedBackground : Theme.reactionBackground))
                .overlay(Capsule().strokeBorder(model.acknowledgedByMe ? Theme.acknowledged.opacity(0.7) : Color.clear))
            }
            .buttonStyle(.plain)
            .disabled(!model.canToggle)
            .pointerStyle(model.canToggle ? .link : .default)
            .help(model.helpText)
            if model.count > 0 {
                Button { popoverShown = true } label: {
                    Image(systemName: "person.2")
                        .scaledFont(10.5, weight: .medium)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(Capsule().fill(Theme.reactionBackground))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(AcknowledgementText.authorHelp(count: model.count))
                .popover(isPresented: $popoverShown, arrowEdge: .top) {
                    AcknowledgementPopover(model: model, client: client)
                }
            }
        }
        .padding(.top, 3)
    }
}

struct AcknowledgementPopover: View {
    let model: AcknowledgementRowModel
    let client: APIClient?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(AcknowledgementText.popoverTitle(count: model.count))
                .scaledFont(11.5, weight: .semibold)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.people) { person in
                        HStack(spacing: 10) {
                            Avatar(url: person.avatarURL, client: client, name: person.name, size: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(AcknowledgementText.name(person))
                                    .scaledFont(12.5, weight: .medium)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(person.timeText)
                                    .scaledFont(11)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .frame(width: 248)
        .padding(.bottom, 6)
    }
}

struct BurnOnReadPlaceholder: View {
    let model: BurnOnReadRowModel
    let onReveal: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onReveal) {
            HStack(spacing: 6) {
                if model.isRevealing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "eye")
                }
                Text(model.isRevealing ? "Revealing…" : "View message")
            }
            .scaledFont(12, weight: .semibold)
            .foregroundStyle(Theme.burnOnRead)
            .padding(.horizontal, 10)
            .frame(minHeight: 26)
            .background(Capsule().fill(hovering ? Theme.burnOnReadBackground.opacity(1.6) : Theme.burnOnReadBackground))
            .overlay(Capsule().strokeBorder(Theme.burnOnRead.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .disabled(model.isRevealing)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .help(model.badgeHelp)
        .accessibilityLabel("Burn-on-read message from \(model.authorName). Click to reveal content.")
    }
}

struct BurnOnReadBadge: View {
    let model: BurnOnReadRowModel
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            Image(systemName: "flame.fill")
                .scaledFont(11)
                .foregroundStyle(Theme.burnOnRead)
                .frame(width: 20, height: 18)
                .background(Capsule().fill(Theme.burnOnReadBackground))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(model.badgeHelp)
        .accessibilityLabel(model.badgeHelp)
    }
}

struct BurnOnReadTimerChip: View {
    let model: BurnOnReadRowModel
    let now: () -> Date
    let onBurn: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            chip(remaining: BurnOnRead.remaining(expireAt: model.expireAt, now: now().mattermostMillis))
        }
    }

    func chip(remaining: Int64) -> some View {
        let warning = BurnOnReadText.isWarning(millis: remaining)
        return Button(action: onBurn) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                Text(BurnOnReadText.timeRemaining(millis: remaining)).monospacedDigit()
            }
            .scaledFont(11, weight: .semibold)
            .foregroundStyle(warning ? Theme.priorityUrgent : Theme.burnOnRead)
            .padding(.horizontal, 8)
            .frame(minHeight: 20)
            .background(Capsule().fill(warning ? Theme.priorityUrgentBackground : Theme.burnOnReadBackground))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(BurnOnReadText.timerHelp(millis: remaining))
    }
}