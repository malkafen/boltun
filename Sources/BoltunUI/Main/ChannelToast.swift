import BoltunKit
import Foundation

enum ChannelToastKind: String, Equatable, Sendable {
    case unread
    case unreadWithBottomStart
    case newMessages
    case history
    case scrollToBottom

    var dismissesOnEscape: Bool { self != .scrollToBottom }
}

struct ChannelToast: Equatable, Sendable {
    var kind: ChannelToastKind
    var count = 0
    var since: Int64 = 0
    var showActions = true

    var actionTitle: String {
        switch kind {
        case .unread, .history, .scrollToBottom: return "Jump to recents"
        case .unreadWithBottomStart: return "Jump to unreads"
        case .newMessages: return "Jump to new messages"
        }
    }

    var jumpsUp: Bool { kind == .unreadWithBottomStart }
}

struct ChannelToastInputs: Equatable, Sendable {
    var atBottom: Bool?
    var unreadCount = 0
    var lastViewedAt: Int64 = 0
    var latestPostAt: Int64 = 0
    var lastViewedBottom: Int64 = 0
    var focused = false
    var initialOffsetFromBottom: Double = 0
    var startFromNewest = false
    var markedUnread = false
    var newMessageLineReached = false
}

struct ChannelToastState: Equatable, Sendable {
    static let historyOffset: Double = 1000

    let initialUnreadCountInChannel: Int
    private(set) var inputs = ChannelToastInputs()
    private(set) var unreadCount = 0
    private(set) var showUnread: Bool?
    private(set) var showNewMessages: Bool?
    private(set) var showHistory: Bool?
    private(set) var showUnreadWithBottomStart: Bool?
    private(set) var showScrollToBottom = false
    private(set) var scrollToBottomDismissed = false
    private var derivedLastViewedAt: Int64?
    private var derivedMarkedUnread = false

    init(initialUnreadCountInChannel: Int = 0) {
        self.initialUnreadCountInChannel = initialUnreadCountInChannel
    }

    mutating func update(_ next: ChannelToastInputs) {
        let reachedBottom = inputs.atBottom != true && next.atBottom == true
        inputs = next
        derive()
        if reachedBottom {
            hideNewMessages(lastViewedBottom: nil)
            hideUnread()
            hideHistory()
        }
    }

    mutating func hideUnread() {
        guard showUnread == true else { return }
        showUnread = false
        derive()
    }

    mutating func hideNewMessages(lastViewedBottom: Int64?) {
        guard showNewMessages == true else { return }
        showNewMessages = false
        if let lastViewedBottom { inputs.lastViewedBottom = lastViewedBottom }
        derive()
    }

    mutating func hideHistory() {
        guard showHistory == true else { return }
        showHistory = false
        derive()
    }

    mutating func resetHistory() {
        showHistory = nil
    }

    mutating func hideUnreadWithBottomStart() {
        guard showUnreadWithBottomStart == true else { return }
        showUnreadWithBottomStart = false
        derive()
    }

    mutating func escape(lastViewedBottom: Int64) {
        if showUnread == true {
            hideUnread()
        } else if showNewMessages == true {
            hideNewMessages(lastViewedBottom: lastViewedBottom)
        } else if showUnreadWithBottomStart == true {
            hideUnreadWithBottomStart()
        } else {
            hideHistory()
        }
    }

    mutating func updateScrollToBottom(offsetFromBottom: Double, threshold: Double) {
        if showScrollToBottom && inputs.atBottom == true {
            showScrollToBottom = false
            return
        }
        if !scrollToBottomDismissed {
            showScrollToBottom = offsetFromBottom > threshold
        }
    }

    mutating func hideScrollToBottom() {
        showScrollToBottom = false
    }

    mutating func dismissScrollToBottom() {
        showScrollToBottom = false
        scrollToBottomDismissed = true
    }

    var visible: ChannelToast? {
        let since = inputs.lastViewedAt
        let notAtBottom = inputs.atBottom == false
        if showUnread == true && unreadCount > 0 {
            return ChannelToast(kind: .unread, count: unreadCount, since: since, showActions: notAtBottom)
        }
        if showUnreadWithBottomStart == true && unreadCount > 0 {
            return ChannelToast(kind: .unreadWithBottomStart, count: unreadCount, since: since)
        }
        if showNewMessages == true {
            return ChannelToast(kind: .newMessages, count: unreadCount, since: since, showActions: notAtBottom)
        }
        if showHistory == true {
            return ChannelToast(kind: .history)
        }
        if showScrollToBottom {
            return ChannelToast(kind: .scrollToBottom)
        }
        return nil
    }

    private mutating func derive() {
        let previousShowUnread = showUnread
        let previousLastViewedAt = derivedLastViewedAt
        let previousMarkedUnread = derivedMarkedUnread
        let count = inputs.startFromNewest && initialUnreadCountInChannel > 0 ? initialUnreadCountInChannel : inputs.unreadCount
        var unread = showUnread
        if unread == nil, let atBottom = inputs.atBottom {
            unread = count > 0 && !atBottom
        }
        if showHistory == nil, inputs.focused, inputs.atBottom != nil {
            showHistory = inputs.initialOffsetFromBottom > Self.historyOffset
        }
        if inputs.markedUnread && inputs.atBottom == false && !previousMarkedUnread && previousShowUnread != true {
            unread = true
        }
        if inputs.markedUnread && inputs.lastViewedAt != previousLastViewedAt && inputs.atBottom == false {
            unread = true
        }
        if unread != true && count > 0 && inputs.atBottom == false && inputs.latestPostAt > 0 && inputs.lastViewedBottom < inputs.latestPostAt {
            showNewMessages = true
        }
        if inputs.startFromNewest && !inputs.markedUnread {
            unread = false
        }
        if count == 0 {
            unread = false
            showNewMessages = false
        }
        if inputs.newMessageLineReached {
            showUnreadWithBottomStart = false
        }
        if showUnreadWithBottomStart == nil, inputs.lastViewedAt > 0, inputs.lastViewedAt != previousLastViewedAt,
           inputs.startFromNewest, count > 0, !inputs.newMessageLineReached {
            showUnreadWithBottomStart = true
        }
        showUnread = unread
        unreadCount = count
        derivedLastViewedAt = inputs.lastViewedAt
        derivedMarkedUnread = inputs.markedUnread
    }
}

enum ToastWidth: Equatable, Sendable {
    case compact
    case medium
    case wide

    static let textCollapseWidth: Double = 500
    static let mobileWidth: Double = 768

    init(width: Double) {
        if width <= Self.textCollapseWidth {
            self = .compact
        } else if width <= Self.mobileWidth {
            self = .medium
        } else {
            self = .wide
        }
    }

    var showsSince: Bool { self != .compact }
    var showsActionTitle: Bool { self == .wide }
}

enum ChannelToastText {
    static func message(for toast: ChannelToast, width: ToastWidth, now: Date, calendar: Calendar) -> String {
        switch toast.kind {
        case .history:
            return "Viewing message history"
        case .scrollToBottom:
            return toast.actionTitle
        case .unread, .unreadWithBottomStart, .newMessages:
            return newMessages(count: toast.count, since: toast.since, width: width, now: now, calendar: calendar)
        }
    }

    static func newMessages(count: Int, since: Int64, width: ToastWidth, now: Date, calendar: Calendar) -> String {
        let counted = "\(formatted(count)) new \(count == 1 ? "message" : "messages")"
        guard width.showsSince else { return counted }
        let date = since.mattermostDate
        let days = dayDifference(from: now, to: date, calendar: calendar)
        if days == 0 { return "\(counted) today" }
        return "\(counted) since \(sinceText(date, days: days, now: now, calendar: calendar))"
    }

    static func sinceText(_ date: Date, days: Int, now: Date, calendar: Calendar) -> String {
        if days == -1 { return "yesterday" }
        if (-6...0).contains(days) { return formatter("EEEE", calendar: calendar).string(from: date) }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return formatter(sameYear ? "MMMM dd" : "MMMM dd, yyyy", calendar: calendar).string(from: date)
    }

    static func dayDifference(from now: Date, to date: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    static func formatted(_ count: Int) -> String {
        count.formatted(.number.locale(Locale(identifier: "en_US")))
    }

    private static let cache = FormatterCache()

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        cache.formatter(format: format, calendar: calendar)
    }
}

enum UnreadScrollTarget: Equatable, Sendable {
    case bottom
    case top(String)

    static let toastClearance: Double = 50
    static let newMessagesId = TimelineItem.newMessages.id

    static func initial(items: [TimelineItem], startFromNewest: Bool) -> UnreadScrollTarget {
        guard !startFromNewest, let index = newMessagesIndex(items) else { return .bottom }
        if index > 0, case .date = items[index - 1] { return .top(items[index - 1].id) }
        return .top(items[index].id)
    }

    static func newMessages(items: [TimelineItem]) -> UnreadScrollTarget? {
        newMessagesIndex(items).map { .top(items[$0].id) }
    }

    static func trackedIds(items: [TimelineItem]) -> Set<String> {
        guard newMessagesIndex(items) != nil else { return [] }
        return Set([initial(items: items, startFromNewest: false), newMessages(items: items)].compactMap { target in
            if case .top(let id)? = target { return id }
            return nil
        })
    }

    static func newMessagesIndex(_ items: [TimelineItem]) -> Int? {
        items.firstIndex { if case .newMessages = $0 { return true } else { return false } }
    }

    var description: String {
        switch self {
        case .bottom: return "bottom"
        case .top(let id): return id
        }
    }
}
