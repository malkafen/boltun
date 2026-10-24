import BoltunKit
import Foundation

struct AcknowledgementPerson: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var timeText: String
    var isMe: Bool
    var avatarURL: URL?
}

struct AcknowledgementRowModel: Equatable, Sendable {
    var postId: String
    var isAuthor: Bool
    var acknowledgedByMe: Bool
    var canToggle: Bool
    var people: [AcknowledgementPerson]

    var count: Int { people.count }

    var showsCount: Bool { count > 0 || isAuthor }

    var buttonText: String { showsCount ? String(count) : "Acknowledge" }

    var helpText: String {
        if isAuthor { return AcknowledgementText.authorHelp(count: count) }
        if acknowledgedByMe { return canToggle ? "Remove your acknowledgement" : "Acknowledged" }
        return "Acknowledge this message"
    }
}

enum AcknowledgementText {
    static func authorHelp(count: Int) -> String {
        switch count {
        case 0: return "Nobody acknowledged this message yet"
        case 1: return "1 person acknowledged this message"
        default: return "\(count) people acknowledged this message"
        }
    }

    static func popoverTitle(count: Int) -> String {
        count == 0 ? "Acknowledgements" : "Acknowledgements (\(count))"
    }

    static func name(_ person: AcknowledgementPerson) -> String {
        person.isMe ? "\(person.name) (you)" : person.name
    }
}

enum PostPriorityText {
    static func label(_ level: PostPriorityLevel) -> String? {
        switch level {
        case .standard: return nil
        case .important: return "IMPORTANT"
        case .urgent: return "URGENT"
        }
    }

    static func menuTitle(_ level: PostPriorityLevel) -> String {
        switch level {
        case .standard: return "Standard"
        case .important: return "Important"
        case .urgent: return "Urgent"
        }
    }

    static func icon(_ level: PostPriorityLevel) -> String {
        switch level {
        case .standard: return "message"
        case .important: return "exclamationmark.circle"
        case .urgent: return "exclamationmark.triangle"
        }
    }

    static func persistentNotificationsDescription(intervalMinutes: Int) -> String {
        let interval = intervalMinutes == 1 ? "1 minute" : "\(intervalMinutes) minutes"
        return "Recipients will be notified every \(interval) until they acknowledge or reply"
    }
}

struct BurnOnReadRowModel: Equatable, Sendable {
    var postId: String
    var authorName: String
    var isSender: Bool
    var isRevealed: Bool
    var isRevealing: Bool
    var expireAt: Int64
    var readDurationMillis: Int64
    var receipt: BurnOnReadReceipt?

    var showsPlaceholder: Bool { !isSender && !isRevealed }

    var showsTimer: Bool { isRevealed && expireAt > 0 }

    var showsBadge: Bool { isSender ? expireAt == 0 : !isRevealed }

    var badgeHelp: String {
        if isSender {
            let delete = "Click to delete message for everyone"
            guard let receipt else { return delete }
            return "\(delete)\n\(BurnOnReadText.readReceipt(receipt))"
        }
        let title = "Burn-on-read message"
        guard readDurationMillis > 0 else { return title }
        return "\(title)\nMessage will be deleted \(BurnOnReadText.duration(millis: readDurationMillis)) after you view it"
    }
}

enum BurnOnReadText {
    static func duration(millis: Int64) -> String {
        let minutes = Int(millis / 60_000)
        guard minutes > 0 else { return "less than 1 min" }
        return minutes == 1 ? "1 min" : "\(minutes) mins"
    }

    static func readReceipt(_ receipt: BurnOnReadReceipt) -> String {
        "Read by \(receipt.revealedCount) of \(receipt.totalRecipients) recipient\(receipt.totalRecipients == 1 ? "" : "s")"
    }

    static func timeRemaining(millis: Int64) -> String {
        let totalSeconds = Int((max(0, millis) + 999) / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func isWarning(millis: Int64) -> Bool { millis <= 60_000 }

    static func timerHelp(millis: Int64) -> String {
        "Deletes in \(timeRemaining(millis: millis))\nClick here to delete immediately"
    }

    static func composerLabel(durationMinutes: Int) -> String {
        let duration = durationMinutes <= 1 ? "1 minute" : "\(durationMinutes) minutes"
        return "Burn on read · deleted \(duration) after it is opened"
    }
}
