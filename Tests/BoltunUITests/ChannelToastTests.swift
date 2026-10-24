import AppKit
@testable import BoltunKit
import Foundation
import SwiftUI
import Testing
@testable import BoltunUI

@Suite struct ChannelToastStateTests {
    func inputs(atBottom: Bool?, unread: Int = 5, lastViewedAt: Int64 = 100, latest: Int64 = 500, bottom: Int64 = 1000) -> ChannelToastInputs {
        ChannelToastInputs(atBottom: atBottom, unreadCount: unread, lastViewedAt: lastViewedAt, latestPostAt: latest, lastViewedBottom: bottom)
    }

    @Test func nothingIsShownBeforeTheListIsPositioned() {
        var state = ChannelToastState()
        state.update(inputs(atBottom: nil))
        #expect(state.visible == nil)
        #expect(state.showUnread == nil)
    }

    @Test func unreadToastWhenOpenedAboveTheBottom() {
        var state = ChannelToastState()
        state.update(inputs(atBottom: false))
        #expect(state.visible == ChannelToast(kind: .unread, count: 5, since: 100, showActions: true))
        state.update(inputs(atBottom: true))
        #expect(state.visible == nil)
        state.update(inputs(atBottom: false))
        #expect(state.visible == nil)
    }

    @Test func noUnreadToastWhenEverythingFits() {
        var state = ChannelToastState()
        state.update(inputs(atBottom: true))
        #expect(state.showUnread == false)
        #expect(state.visible == nil)
    }

    @Test func noToastWithoutUnreadPosts() {
        var state = ChannelToastState()
        state.update(inputs(atBottom: false, unread: 0))
        #expect(state.visible == nil)
        #expect(state.showNewMessages == false)
    }

    @Test func dismissingUnreadKeepsItHidden() {
        var state = ChannelToastState()
        state.update(inputs(atBottom: false))
        state.hideUnread()
        #expect(state.visible == nil)
        state.update(inputs(atBottom: false, unread: 6))
        #expect(state.visible == nil)
    }

    @Test func newMessagesToastWhenPostsArriveWhileScrolledUp() {
        var state = ChannelToastState()
        state.update(inputs(atBottom: true, unread: 0))
        state.update(inputs(atBottom: false, unread: 0))
        #expect(state.visible == nil)
        state.update(inputs(atBottom: false, unread: 2, lastViewedAt: 900, latest: 1200, bottom: 900))
        #expect(state.visible == ChannelToast(kind: .newMessages, count: 2, since: 900, showActions: true))
        state.hideNewMessages(lastViewedBottom: 1300)
        #expect(state.visible == nil)
        #expect(state.inputs.lastViewedBottom == 1300)
        state.update(inputs(atBottom: false, unread: 2, lastViewedAt: 900, latest: 1200, bottom: 1300))
        #expect(state.visible == nil)
    }

    @Test func newMessagesHideWhenReachingTheBottom() {
        var state = ChannelToastState()
        state.update(inputs(atBottom: true, unread: 0))
        state.update(inputs(atBottom: false, unread: 1, latest: 1200, bottom: 900))
        #expect(state.visible?.kind == .newMessages)
        state.update(inputs(atBottom: true, unread: 1, latest: 1200, bottom: 1300))
        #expect(state.visible == nil)
    }

    @Test func historyToastForFocusedPostsFarFromTheBottom() {
        var state = ChannelToastState()
        var next = inputs(atBottom: false, unread: 0)
        next.focused = true
        next.initialOffsetFromBottom = 1500
        state.update(next)
        #expect(state.visible == ChannelToast(kind: .history))
        state.hideHistory()
        #expect(state.visible == nil)
        var near = ChannelToastState()
        next.initialOffsetFromBottom = 1000
        near.update(next)
        #expect(near.visible == nil)
    }

    @Test func historyHidesAtTheBottom() {
        var state = ChannelToastState()
        var next = inputs(atBottom: false, unread: 0)
        next.focused = true
        next.initialOffsetFromBottom = 4000
        state.update(next)
        next.atBottom = true
        state.update(next)
        #expect(state.visible == nil)
    }

    @Test func startFromNewestShowsJumpToUnreads() {
        var state = ChannelToastState()
        var next = inputs(atBottom: true)
        next.startFromNewest = true
        state.update(next)
        #expect(state.visible == ChannelToast(kind: .unreadWithBottomStart, count: 5, since: 100))
        #expect(state.visible?.jumpsUp == true)
        next.atBottom = false
        state.update(next)
        #expect(state.visible?.kind == .unreadWithBottomStart)
        next.newMessageLineReached = true
        state.update(next)
        #expect(state.visible?.kind != .unreadWithBottomStart)
    }

    @Test func startFromNewestUsesTheChannelCountWithCollapsedThreads() {
        var state = ChannelToastState(initialUnreadCountInChannel: 42)
        var next = inputs(atBottom: true, unread: 3)
        next.startFromNewest = true
        state.update(next)
        #expect(state.visible?.count == 42)
        var plain = ChannelToastState(initialUnreadCountInChannel: 42)
        plain.update(inputs(atBottom: false, unread: 3))
        #expect(plain.visible?.count == 3)
    }

    @Test func startFromNewestNeedsALastViewedTime() {
        var state = ChannelToastState()
        var next = inputs(atBottom: true, lastViewedAt: 0)
        next.startFromNewest = true
        state.update(next)
        #expect(state.visible == nil)
    }

    @Test func markedUnreadShowsTheUnreadToast() {
        var state = ChannelToastState()
        state.update(inputs(atBottom: true, bottom: 400))
        state.update(inputs(atBottom: false, bottom: 400))
        #expect(state.visible?.kind == .newMessages)
        var marked = inputs(atBottom: false, lastViewedAt: 50, bottom: 400)
        marked.markedUnread = true
        state.update(marked)
        #expect(state.visible?.kind == .unread)
        var newest = ChannelToastState()
        marked.startFromNewest = true
        newest.update(marked)
        #expect(newest.visible?.kind == .unread)
    }

    @Test func markedUnreadReappearsWhenTheMarkerMoves() {
        var state = ChannelToastState()
        var marked = inputs(atBottom: false)
        marked.markedUnread = true
        state.update(marked)
        state.hideUnread()
        state.update(marked)
        #expect(state.visible?.kind != .unread)
        marked.lastViewedAt = 70
        state.update(marked)
        #expect(state.visible?.kind == .unread)
    }

    @Test func escapeHidesInPriorityOrder() {
        var state = ChannelToastState()
        var next = inputs(atBottom: true, bottom: 400)
        next.startFromNewest = true
        state.update(next)
        next.atBottom = false
        next.focused = true
        next.initialOffsetFromBottom = 2000
        state.update(next)
        #expect(state.visible?.kind == .unreadWithBottomStart)
        #expect(state.showNewMessages == true)
        state.escape(lastViewedBottom: 2000)
        #expect(state.showNewMessages == false)
        #expect(state.inputs.lastViewedBottom == 2000)
        state.escape(lastViewedBottom: 2000)
        #expect(state.visible?.kind == .history)
        state.escape(lastViewedBottom: 2000)
        #expect(state.visible == nil)
        var unread = ChannelToastState()
        unread.update(inputs(atBottom: false))
        unread.escape(lastViewedBottom: 0)
        #expect(unread.showUnread == false)
    }

    @Test func hidingSomethingNotShownIsANoOp() {
        var state = ChannelToastState()
        let before = state
        state.hideUnread()
        state.hideNewMessages(lastViewedBottom: 5)
        state.hideHistory()
        state.hideUnreadWithBottomStart()
        #expect(state == before)
    }

    @Test func scrollToBottomToast() {
        var state = ChannelToastState()
        state.update(inputs(atBottom: false, unread: 0))
        state.updateScrollToBottom(offsetFromBottom: 2000, threshold: 2700)
        #expect(state.visible == nil)
        state.updateScrollToBottom(offsetFromBottom: 3000, threshold: 2700)
        #expect(state.visible == ChannelToast(kind: .scrollToBottom))
        #expect(state.visible?.kind.dismissesOnEscape == false)
        state.update(inputs(atBottom: true, unread: 0))
        state.updateScrollToBottom(offsetFromBottom: 3000, threshold: 2700)
        #expect(state.visible == nil)
        state.update(inputs(atBottom: false, unread: 0))
        state.updateScrollToBottom(offsetFromBottom: 3000, threshold: 2700)
        state.hideScrollToBottom()
        #expect(state.visible == nil)
        state.updateScrollToBottom(offsetFromBottom: 3000, threshold: 2700)
        state.dismissScrollToBottom()
        state.updateScrollToBottom(offsetFromBottom: 9000, threshold: 2700)
        #expect(state.visible == nil)
    }

    @Test func unreadToastTakesPriorityOverScrollToBottom() {
        var state = ChannelToastState()
        state.update(inputs(atBottom: false))
        state.updateScrollToBottom(offsetFromBottom: 9000, threshold: 2700)
        #expect(state.visible?.kind == .unread)
        state.hideUnread()
        #expect(state.visible?.kind == .scrollToBottom)
    }

    @Test func actionTitles() {
        #expect(ChannelToast(kind: .unread).actionTitle == "Jump to recents")
        #expect(ChannelToast(kind: .history).actionTitle == "Jump to recents")
        #expect(ChannelToast(kind: .scrollToBottom).actionTitle == "Jump to recents")
        #expect(ChannelToast(kind: .unreadWithBottomStart).actionTitle == "Jump to unreads")
        #expect(ChannelToast(kind: .newMessages).actionTitle == "Jump to new messages")
        #expect(!ChannelToast(kind: .unread).jumpsUp)
    }
}

@Suite struct ChannelToastTextTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 15))! }

    func millis(_ month: Int, _ day: Int, year: Int = 2026, hour: Int = 9) -> Int64 {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!.mattermostMillis
    }

    func text(_ count: Int, _ since: Int64, width: ToastWidth = .wide) -> String {
        ChannelToastText.newMessages(count: count, since: since, width: width, now: now, calendar: calendar)
    }

    @Test func relativeDates() {
        #expect(text(60, millis(10, 24)) == "60 new messages today")
        #expect(text(1, millis(10, 23)) == "1 new message since yesterday")
        #expect(text(3, millis(10, 21)) == "3 new messages since Wednesday")
        #expect(text(3, millis(10, 18)) == "3 new messages since Sunday")
        #expect(text(3, millis(10, 17)) == "3 new messages since October 17")
        #expect(text(3, millis(10, 5)) == "3 new messages since October 05")
        #expect(text(3, millis(12, 30, year: 2025)) == "3 new messages since December 30, 2025")
    }

    @Test func countFormattingAndNarrowWidths() {
        #expect(text(1234, millis(10, 24)) == "1,234 new messages today")
        #expect(text(5, millis(10, 1), width: .compact) == "5 new messages")
        #expect(text(1, millis(10, 1), width: .compact) == "1 new message")
        #expect(text(5, millis(10, 24), width: .medium) == "5 new messages today")
    }

    @Test func messagesPerKind() {
        #expect(ChannelToastText.message(for: ChannelToast(kind: .history), width: .wide, now: now, calendar: calendar) == "Viewing message history")
        #expect(ChannelToastText.message(for: ChannelToast(kind: .scrollToBottom), width: .compact, now: now, calendar: calendar) == "Jump to recents")
        let unread = ChannelToast(kind: .unread, count: 2, since: millis(10, 23))
        #expect(ChannelToastText.message(for: unread, width: .wide, now: now, calendar: calendar) == "2 new messages since yesterday")
    }

    @Test func widths() {
        #expect(ToastWidth(width: 500) == .compact)
        #expect(ToastWidth(width: 501) == .medium)
        #expect(ToastWidth(width: 768) == .medium)
        #expect(ToastWidth(width: 769) == .wide)
        #expect(!ToastWidth.compact.showsSince)
        #expect(ToastWidth.medium.showsSince && !ToastWidth.medium.showsActionTitle)
        #expect(ToastWidth.wide.showsActionTitle)
    }
}

@MainActor
@Suite struct UnreadScrollTargetTests {
    func row(_ id: String) -> TimelineItem {
        .post(TimelineBuilder.row(for: Post(id: id, userId: "u", channelId: "c", message: id), previous: nil, continuation: false, context: TimelineContext(myId: "me", myUsername: "me")))
    }

    @Test func alignsTheDateAboveTheSeparator() {
        let items: [TimelineItem] = [.date("Yesterday"), row("a"), .date("Today"), .newMessages, row("b")]
        #expect(UnreadScrollTarget.initial(items: items, startFromNewest: false) == .top("date:Today"))
        #expect(UnreadScrollTarget.newMessages(items: items) == .top("new-messages"))
        #expect(UnreadScrollTarget.newMessagesIndex(items) == 3)
        #expect(UnreadScrollTarget.trackedIds(items: items) == ["date:Today", "new-messages"])
        #expect(UnreadScrollTarget.trackedIds(items: [row("a")]).isEmpty)
        #expect(UnreadScrollTarget.newMessagesId == "new-messages")
    }

    @Test func alignsTheSeparatorWithoutADate() {
        let items: [TimelineItem] = [.date("Today"), row("a"), .newMessages, row("b")]
        #expect(UnreadScrollTarget.initial(items: items, startFromNewest: false) == .top("new-messages"))
        #expect(UnreadScrollTarget.initial(items: [.newMessages, row("b")], startFromNewest: false) == .top("new-messages"))
    }

    @Test func bottomWithoutUnreadOrWhenStartingFromNewest() {
        let items: [TimelineItem] = [.date("Today"), row("a"), .newMessages, row("b")]
        #expect(UnreadScrollTarget.initial(items: items, startFromNewest: true) == .bottom)
        #expect(UnreadScrollTarget.initial(items: [row("a")], startFromNewest: false) == .bottom)
        #expect(UnreadScrollTarget.newMessages(items: [row("a")]) == nil)
        #expect(UnreadScrollTarget.bottom.description == "bottom")
        #expect(UnreadScrollTarget.top("x").description == "x")
    }

    @Test func fixtureChannelTargetsTheSeparator() {
        let workspace = Fixture.workspace()
        let items = workspace.channelItems(channelId: "town")
        #expect(UnreadScrollTarget.initial(items: items, startFromNewest: false) == .top("new-messages"))
    }
}

@MainActor
@Suite struct ChannelToastModelTests {
    func workspace(collapsed: Bool = false) -> Workspace {
        let workspace = Fixture.workspace()
        workspace.session.collapsedThreads = collapsed
        return workspace
    }

    func append(_ workspace: Workspace, id: String, at minute: Double, user: String = "alice") {
        let post = Post(id: id, createAt: Fixture.minutes(minute), userId: user, channelId: "town", message: id)
        workspace.session.posts[id] = post
        workspace.session.timelines["town"]?.postIds.append(id)
    }

    @Test func unreadCountFromTheMarkerCapturedOnOpen() {
        let workspace = workspace()
        let model = workspace.channelToast
        model.begin(channelId: "town")
        #expect(model.visible == nil)
        model.positioned(atBottom: false, offsetFromBottom: 400)
        #expect(model.visible == ChannelToast(kind: .unread, count: 4, since: Fixture.minutes(15), showActions: true))
        model.positioned(atBottom: true, offsetFromBottom: 0)
        #expect(model.visible?.kind == .unread)
    }

    @Test func collapsedThreadsCountOnlyLiveRootPosts() {
        let workspace = workspace(collapsed: true)
        let model = workspace.channelToast
        model.begin(channelId: "town")
        model.positioned(atBottom: false, offsetFromBottom: 400)
        #expect(model.visible?.count == 2)
    }

    @Test func jumpToRecentsScrollsToTheBottom() {
        let workspace = workspace()
        let model = workspace.channelToast
        model.begin(channelId: "town")
        model.positioned(atBottom: false, offsetFromBottom: 400)
        #expect(model.jump())
        #expect(workspace.scrollRequest?.target == .bottom)
        #expect(model.visible == nil)
        #expect(!model.jump())
        #expect(!model.dismiss())
    }

    @Test func reachingTheBottomHidesTheUnreadToast() {
        let workspace = workspace()
        let model = workspace.channelToast
        model.begin(channelId: "town")
        model.positioned(atBottom: false, offsetFromBottom: 400)
        model.scrolled(atBottom: true, offsetFromBottom: 0)
        #expect(model.visible == nil)
    }

    @Test func dismissAndEscape() {
        let workspace = workspace()
        let model = workspace.channelToast
        model.begin(channelId: "town")
        model.escape()
        model.positioned(atBottom: false, offsetFromBottom: 400)
        #expect(model.dismiss())
        #expect(model.visible == nil)
        model.begin(channelId: "town")
        model.positioned(atBottom: false, offsetFromBottom: 400)
        model.escape()
        #expect(model.visible == nil)
    }

    @Test func newPostsWhileScrolledUpMoveTheMarker() {
        let workspace = workspace()
        let model = workspace.channelToast
        model.begin(channelId: "town")
        model.positioned(atBottom: false, offsetFromBottom: 400)
        model.dismiss()
        append(workspace, id: "n1", at: 70)
        model.postsChanged()
        #expect(workspace.session.timelines["town"]?.lastViewedAtOnOpen == Fixture.minutes(60))
        #expect(model.visible == ChannelToast(kind: .newMessages, count: 1, since: Fixture.minutes(60), showActions: true))
        append(workspace, id: "n2", at: 71)
        model.postsChanged()
        #expect(model.visible?.count == 2)
        workspace.now = { Fixture.minutes(80).mattermostDate }
        #expect(model.jump())
        #expect(workspace.scrollRequest?.target == .newMessages)
        #expect(model.visible == nil)
    }

    @Test func ownPostsDoNotMoveTheMarker() {
        let workspace = workspace()
        let model = workspace.channelToast
        model.begin(channelId: "town")
        model.positioned(atBottom: false, offsetFromBottom: 400)
        model.dismiss()
        append(workspace, id: "mine", at: 70, user: "me")
        model.postsChanged()
        #expect(workspace.session.timelines["town"]?.lastViewedAtOnOpen == Fixture.minutes(15))
    }

    @Test func postsAtTheBottomDoNotShowNewMessages() {
        let workspace = workspace()
        let model = workspace.channelToast
        model.begin(channelId: "town")
        model.positioned(atBottom: true, offsetFromBottom: 0)
        append(workspace, id: "n1", at: 70)
        model.postsChanged()
        #expect(model.visible == nil)
        #expect(workspace.session.timelines["town"]?.lastViewedAtOnOpen == Fixture.minutes(15))
    }

    @Test func postsBeforePositioningAreIgnored() {
        let workspace = workspace()
        let model = workspace.channelToast
        model.postsChanged()
        model.begin(channelId: "town")
        append(workspace, id: "n1", at: 70)
        model.postsChanged()
        model.scrolled(atBottom: false, offsetFromBottom: 400)
        model.newMessagesLineVisible()
        #expect(model.visible == nil)
    }

    @Test func dismissingNewMessagesRemembersTheBottom() {
        let workspace = workspace()
        let model = workspace.channelToast
        model.begin(channelId: "town")
        model.positioned(atBottom: false, offsetFromBottom: 400)
        model.dismiss()
        append(workspace, id: "n1", at: 70)
        model.postsChanged()
        workspace.now = { Fixture.minutes(80).mattermostDate }
        #expect(model.dismiss())
        #expect(model.visible == nil)
        append(workspace, id: "n2", at: 75)
        model.postsChanged()
        #expect(model.visible == nil)
    }

    @Test func historyToastAfterFocusingAnOldPost() {
        let workspace = workspace()
        workspace.session.timelines["town"]?.lastViewedAtOnOpen = Fixture.minutes(50)
        let model = workspace.channelToast
        model.begin(channelId: "town")
        model.focused(atBottom: false, offsetFromBottom: 1500)
        #expect(model.visible == ChannelToast(kind: .history))
        #expect(model.jump())
        #expect(workspace.scrollRequest?.target == .bottom)
        #expect(model.visible == nil)
        model.begin(channelId: "town")
        model.positioned(atBottom: false, offsetFromBottom: 400)
        model.focused(atBottom: false, offsetFromBottom: 3000)
        #expect(model.visible == ChannelToast(kind: .history))
        #expect(model.dismiss())
        #expect(model.visible == ChannelToast(kind: .scrollToBottom))
    }

    @Test func everyFocusDecidesTheHistoryToastAgain() {
        let workspace = workspace()
        workspace.session.timelines["town"]?.lastViewedAtOnOpen = Fixture.minutes(50)
        let model = workspace.channelToast
        model.begin(channelId: "town")
        model.focused(atBottom: true, offsetFromBottom: 0)
        #expect(model.visible == nil)
        model.focused(atBottom: false, offsetFromBottom: 1500)
        #expect(model.visible == ChannelToast(kind: .history))
    }

    @Test func startFromNewestJumpsToUnreads() {
        let workspace = workspace()
        workspace.session.preferences.append(Preference(userId: "me", category: "advanced_settings", name: "unread_scroll_position", value: "start_from_newest"))
        let model = workspace.channelToast
        model.begin(channelId: "town")
        #expect(model.startFromNewest)
        model.positioned(atBottom: true, offsetFromBottom: 0)
        #expect(model.visible == ChannelToast(kind: .unreadWithBottomStart, count: 4, since: Fixture.minutes(15)))
        #expect(model.jump())
        #expect(!model.startFromNewest)
        #expect(model.remountRequest == 1)
        #expect(!model.positioned)
        #expect(model.visible == nil)
    }

    @Test func reachingTheSeparatorHidesJumpToUnreads() {
        let workspace = workspace()
        workspace.session.preferences.append(Preference(userId: "me", category: "advanced_settings", name: "unread_scroll_position", value: "start_from_newest"))
        let model = workspace.channelToast
        model.begin(channelId: "town")
        model.positioned(atBottom: true, offsetFromBottom: 0)
        model.newMessagesLineVisible()
        model.newMessagesLineVisible()
        #expect(model.visible == nil)
        model.begin(channelId: "town")
        model.positioned(atBottom: true, offsetFromBottom: 0)
        #expect(model.dismiss())
        #expect(model.visible == nil)
    }

    @Test func scrollToBottomToastFarFromTheBottom() {
        let workspace = workspace()
        workspace.session.timelines["town"]?.lastViewedAtOnOpen = Fixture.minutes(50)
        let model = workspace.channelToast
        model.farFromBottomThreshold = 1000
        model.begin(channelId: "town")
        model.positioned(atBottom: false, offsetFromBottom: 400)
        #expect(model.visible == nil)
        model.scrolled(atBottom: false, offsetFromBottom: 1200)
        #expect(model.visible == ChannelToast(kind: .scrollToBottom))
        #expect(model.jump())
        #expect(workspace.scrollRequest?.target == .bottom)
        model.scrolled(atBottom: false, offsetFromBottom: 1300)
        #expect(model.visible?.kind == .scrollToBottom)
        #expect(model.dismiss())
        model.scrolled(atBottom: false, offsetFromBottom: 5000)
        #expect(model.visible == nil)
    }

    @Test func resizingChangesTheWidthClass() {
        let model = workspace().channelToast
        model.resized(width: 400)
        #expect(model.width == .compact)
        model.resized(width: 400)
        model.resized(width: 1000)
        #expect(model.width == .wide)
    }

    @Test func beginUsesTheUnreadCountCapturedOnOpen() {
        let workspace = workspace()
        workspace.session.timelines["town"]?.unreadCountOnOpen = 9
        let mount = UUID()
        workspace.channelToast.begin(channelId: "town", mountId: mount)
        #expect(workspace.channelToast.mountId == mount)
        #expect(workspace.channelToast.state.initialUnreadCountInChannel == 9)
        #expect(workspace.channelToast.channelId == "town")
    }

    @Test func toastClockFollowsTheWorkspace() {
        let workspace = workspace()
        #expect(workspace.channelToast.now() == Fixture.now)
    }
}

enum InteractiveSession {
    static let available = ProcessInfo.processInfo.environment["CI"] == nil
}

@MainActor
@Suite struct ChannelToastViewTests {
    @Test func escapeMonitorOnlyReactsToEscapeInItsWindow() {
        var calls = 0
        let coordinator = EscapeKeyMonitor.Coordinator()
        coordinator.action = { calls += 1 }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 50, height: 50), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let view = NSView()
        window.contentView = view
        coordinator.attach(to: view)
        #expect(!coordinator.handle(keyCode: 12, window: window))
        #expect(!coordinator.handle(keyCode: EscapeKeyMonitor.escapeKeyCode, window: nil))
        #expect(!coordinator.handle(keyCode: EscapeKeyMonitor.escapeKeyCode, window: NSWindow()))
        #expect(coordinator.handle(keyCode: EscapeKeyMonitor.escapeKeyCode, window: window))
        #expect(calls == 1)
        coordinator.detach()
        coordinator.detach()
        window.close()
    }

    @Test func toastBarJumpsOnlyWithActions() {
        var jumps = 0
        let passive = ChannelToastBar(toast: ChannelToast(kind: .unread, count: 1, showActions: false), message: "", width: .wide, onJump: { jumps += 1 }, onDismiss: {})
        passive.jumpIfActionable()
        #expect(jumps == 0)
        let active = ChannelToastBar(toast: ChannelToast(kind: .unread, count: 1), message: "", width: .wide, onJump: { jumps += 1 }, onDismiss: {})
        active.jumpIfActionable()
        #expect(jumps == 1)
    }

    @Test func toastSnapshots() async {
        let workspace = Fixture.workspace()
        let model = workspace.channelToast
        model.begin(channelId: "town")
        model.resized(width: 900)
        model.positioned(atBottom: false, offsetFromBottom: 400)
        let overlay = ChannelToastOverlay(model: model, now: Fixture.now, calendar: Fixture.calendar)
        let rep = await MainSnapshot.render(overlay.frame(maxHeight: .infinity, alignment: .top).background(Theme.content), size: CGSize(width: 900, height: 60), name: "toast-unread")
        #expect(MainSnapshot.distinctColors(rep) > 2)
        model.focused(atBottom: false, offsetFromBottom: 3000)
        model.dismiss()
        await MainSnapshot.render(overlay.frame(maxHeight: .infinity, alignment: .top).background(Theme.content), size: CGSize(width: 900, height: 60), name: "toast-history")
        let views = VStack(spacing: 8) {
            ChannelToastBar(toast: ChannelToast(kind: .newMessages, count: 3, since: Fixture.minutes(0)), message: "3 new messages", width: .medium, onJump: {}, onDismiss: {})
            ChannelToastBar(toast: ChannelToast(kind: .unread, count: 3, since: Fixture.minutes(0), showActions: false), message: "3 new messages today", width: .wide, onJump: {}, onDismiss: {})
            ChannelToastBar(toast: ChannelToast(kind: .unreadWithBottomStart, count: 3), message: "3 new messages", width: .wide, onJump: {}, onDismiss: {})
            ScrollToBottomToastButton(onJump: {}, onDismiss: {})
        }
        await MainSnapshot.render(views.background(Theme.content), size: CGSize(width: 600, height: 220), name: "toast-variants")
        model.farFromBottomThreshold = 100
        model.scrolled(atBottom: false, offsetFromBottom: 500)
        await MainSnapshot.render(overlay.frame(maxHeight: .infinity, alignment: .top).background(Theme.content), size: CGSize(width: 900, height: 60))
    }

    func host(_ workspace: Workspace, size: CGSize = CGSize(width: 900, height: 300)) -> NSWindow {
        let hosting = NSHostingView(rootView: MessageListView(workspace: workspace, channelId: "town").frame(width: size.width, height: size.height).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        return window
    }

    @discardableResult
    func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            MainSnapshot.pump(0.02)
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    func settle(_ duration: Duration = .milliseconds(600)) async {
        let deadline = ContinuousClock.now + duration
        while ContinuousClock.now < deadline {
            MainSnapshot.pump(0.02)
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test(.enabled(if: InteractiveSession.available)) func messageListShowsTheUnreadToast() async throws {
        let workspace = Fixture.workspace()
        let window = host(workspace)
        #expect(await waitUntil { workspace.scrollReport.positioned })
        #expect(workspace.scrollReport.initialTarget == "new-messages")
        #expect(workspace.channelToast.channelId == "town")
        #expect(workspace.channelToast.visible?.kind == .unread)
        let top = try #require(workspace.scrollReport.newMessagesLineTop)
        #expect(abs(top - UnreadScrollTarget.toastClearance) < 2)
        window.contentView = nil
        window.close()
        await MainSnapshot.render(MessageListView(workspace: workspace, channelId: "town").background(Theme.content), size: CGSize(width: 900, height: 300), name: "toast-message-list", settle: .milliseconds(1200))
    }

    @Test(.enabled(if: InteractiveSession.available)) func alignsTheSeparatorWhenRowHeightEstimatesAreWrong() async {
        let workspace = Fixture.workspace()
        let session = workspace.session
        var posts: [Post] = []
        for index in 0..<15 {
            posts.append(Post(id: "e\(index)", createAt: Fixture.minutes(Double(index) * 0.1), userId: "alice", channelId: "town", message: "Earlier message \(index)"))
        }
        posts.append(Post(id: "mine", createAt: Fixture.minutes(2), userId: "me", channelId: "town", message: "Boltun replying"))
        for index in 0..<60 {
            posts.append(Post(id: "u\(index)", createAt: Fixture.minutes(10 + Double(index) * 0.01), userId: "alice", channelId: "town", message: "New unread message \(index + 1) of 60"))
        }
        session.posts = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
        var timeline = ChannelTimeline()
        timeline.postIds = posts.map(\.id)
        timeline.loaded = true
        timeline.hasMoreOlder = false
        timeline.lastViewedAtOnOpen = Fixture.minutes(5)
        session.timelines = ["town": timeline]
        let window = host(workspace, size: CGSize(width: 750, height: 628))
        #expect(await waitUntil { workspace.scrollReport.positioned })
        #expect(abs((workspace.scrollReport.newMessagesLineTop ?? -1) - UnreadScrollTarget.toastClearance) < 2, "\(workspace.scrollReport)")
        #expect(workspace.channelToast.visible?.count == 60)
        window.contentView = nil
        window.close()
    }

    @Test(.enabled(if: InteractiveSession.available)) func messageListFollowsScrollRequests() async throws {
        let workspace = Fixture.workspace()
        let window = host(workspace)
        #expect(await waitUntil { workspace.scrollReport.positioned })
        #expect(workspace.channelToast.jump())
        #expect(await waitUntil { workspace.scrollReport.distanceFromBottom < 12 }, "\(workspace.scrollReport)")
        #expect(workspace.channelToast.visible == nil)
        workspace.requestScroll(.newMessages)
        #expect(await waitUntil { abs((workspace.scrollReport.newMessagesLineTop ?? -1) - UnreadScrollTarget.toastClearance) < 2 })
        workspace.requestScroll(.top)
        #expect(await waitUntil { workspace.scrollReport.distanceFromTop < 1 })
        workspace.requestScroll(.post("p2"))
        #expect(await waitUntil { workspace.scrollReport.distanceFromTop > 0 }, "\(workspace.scrollReport)")
        workspace.requestScroll(.bottom)
        #expect(await waitUntil { workspace.scrollReport.distanceFromBottom < 12 }, "\(workspace.scrollReport)")
        await settle()
        let post = Post(id: "n1", createAt: Fixture.minutes(70), userId: "alice", channelId: "town", message: "fresh")
        workspace.session.posts["n1"] = post
        workspace.session.timelines["town"]?.postIds.append("n1")
        await settle()
        #expect(workspace.scrollReport.distanceFromBottom < 12, "\(workspace.scrollReport)")
        window.contentView = nil
        window.close()
    }

    @Test func requestsDuringInitialPositioningCancelIt() async {
        let workspace = Fixture.workspace()
        let window = host(workspace)
        workspace.requestScroll(.bottom)
        #expect(await waitUntil { workspace.scrollReport.positioned })
        #expect(await waitUntil { workspace.scrollReport.distanceFromBottom < 12 }, "\(workspace.scrollReport)")
        window.contentView = nil
        window.close()
    }

    @Test func jumpToUnreadsRepositionsAtTheSeparator() async {
        let workspace = Fixture.workspace()
        workspace.session.preferences.append(Preference(userId: "me", category: "advanced_settings", name: "unread_scroll_position", value: "start_from_newest"))
        let window = host(workspace)
        #expect(await waitUntil { workspace.scrollReport.positioned })
        #expect(workspace.scrollReport.initialTarget == "bottom")
        #expect(workspace.channelToast.visible?.kind == .unreadWithBottomStart)
        #expect(workspace.channelToast.jump())
        #expect(await waitUntil { workspace.scrollReport.positioned && workspace.scrollReport.initialTarget == "new-messages" })
        #expect(await waitUntil { abs((workspace.scrollReport.newMessagesLineTop ?? -1) - UnreadScrollTarget.toastClearance) < 2 })
        window.contentView = nil
        window.close()
    }
}

@MainActor
struct ChannelToastAutomationTests {
    func command(_ string: String) -> DebugCommand? {
        DebugCommand(url: URL(string: string)!)
    }

    @Test func parsesToastCommands() {
        #expect(command("boltun://debug/toast?action=jump") == .toast(action: .jump))
        #expect(command("boltun://debug/toast?action=dismiss") == .toast(action: .dismiss))
        #expect(command("boltun://debug/toast?action=escape") == .toast(action: .escape))
        #expect(command("boltun://debug/toast?action=bogus") == nil)
        #expect(command("boltun://debug/toast") == nil)
    }

    func make() async throws -> (Harness, DebugAutomation, LogSink, Workspace) {
        var routes = FakeTransport.standardRoutes
        routes["GET channels/c1/posts"] = .init(status: 200, body: """
        {"order":["c","b","a"],"posts":{
          "a":{"id":"a","channel_id":"c1","user_id":"me","message":"mine","create_at":10},
          "b":{"id":"b","channel_id":"c1","user_id":"u2","message":"first unread","create_at":20},
          "c":{"id":"c","channel_id":"c1","user_id":"u2","message":"second unread","create_at":30}}}
        """)
        let server = Harness.server()
        let harness = Harness(servers: [server], tokens: [server.id: "token"], transport: FakeTransport(routes: routes))
        await harness.model.startAll()
        let sink = LogSink()
        let router = AppRouter(model: harness.model)
        let automation = DebugAutomation(router: router, host: FakeAutomationHost(), isEnabled: { true }) { sink.lines.append($0) }
        let session = try #require(harness.model.selectedSession)
        #expect(await eventually { session.posts["c"] != nil })
        let workspace = try automation.currentWorkspace()
        return (harness, automation, sink, workspace)
    }

    func state(_ automation: DebugAutomation) async throws -> AutomationUIState? {
        let path = "/tmp/boltun-tests-\(UUID().uuidString).json"
        await automation.handle(URL(string: "boltun://debug/state?path=\(path)")!)
        defer { try? FileManager.default.removeItem(atPath: path) }
        return try JSONDecoder().decode(AutomationState.self, from: Data(contentsOf: URL(fileURLWithPath: path))).ui
    }

    @Test func toastCommandsAndState() async throws {
        let (harness, automation, sink, workspace) = try await make()
        _ = harness
        await automation.handle(URL(string: "boltun://debug/toast?action=jump")!)
        #expect(sink.lines.last == "error /toast no toast")
        workspace.session.timelines["c1"]?.lastViewedAtOnOpen = 15
        workspace.now = { Date(timeIntervalSince1970: 0) }
        workspace.channelToast.begin(channelId: "c1")
        workspace.channelToast.resized(width: 1000)
        workspace.channelToast.positioned(atBottom: false, offsetFromBottom: 600)
        var ui = try #require(try await state(automation))
        #expect(ui.toast == AutomationUIState.ToastSummary(kind: "unread", message: "2 new messages today", action: "Jump to recents", showActions: true, count: 2, since: 15))
        #expect(ui.lastViewedAtOnOpen == 15)
        await automation.handle(URL(string: "boltun://debug/toast?action=dismiss")!)
        #expect(sink.lines.last == "ok /toast none")
        await automation.handle(URL(string: "boltun://debug/toast?action=dismiss")!)
        #expect(sink.lines.last == "error /toast no toast")
        await automation.handle(URL(string: "boltun://debug/toast?action=escape")!)
        #expect(sink.lines.last == "ok /toast none")
        workspace.channelToast.begin(channelId: "c1")
        workspace.channelToast.positioned(atBottom: false, offsetFromBottom: 600)
        await automation.handle(URL(string: "boltun://debug/toast?action=jump")!)
        #expect(sink.lines.last == "ok /toast none")
        #expect(workspace.scrollRequest?.target == .bottom)
        ui = try #require(try await state(automation))
        #expect(ui.toast == nil)
        workspace.channelToast.begin(channelId: "c1")
        workspace.channelToast.resized(width: 600)
        workspace.channelToast.positioned(atBottom: false, offsetFromBottom: 600)
        ui = try #require(try await state(automation))
        #expect(ui.toast?.action == nil)
        #expect(ui.toast?.message == "2 new messages today")
    }
}
