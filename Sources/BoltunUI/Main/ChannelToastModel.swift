import BoltunKit
import Foundation
import Observation

@MainActor
@Observable
final class ChannelToastModel {
    private(set) var channelId: String?
    @ObservationIgnored private(set) var mountId: UUID?
    private(set) var state = ChannelToastState()
    private(set) var width = ToastWidth.wide
    private(set) var remountRequest = 0
    @ObservationIgnored private(set) var positioned = false
    @ObservationIgnored private(set) var startFromNewest = false
    @ObservationIgnored private(set) var inputs = ChannelToastInputs()
    @ObservationIgnored private var postCount = 0
    @ObservationIgnored private var newestPostId: String?
    @ObservationIgnored private var newestIsMine = false
    @ObservationIgnored var farFromBottomThreshold: Double = 2700
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored var requestScroll: (ScrollRequest.Target) -> Void = { _ in }
    @ObservationIgnored let session: ServerSession

    init(session: ServerSession) {
        self.session = session
    }

    var visible: ChannelToast? { state.visible }

    private var nowMillis: Int64 { now().mattermostMillis }

    func begin(channelId: String, mountId: UUID = UUID()) {
        self.channelId = channelId
        self.mountId = mountId
        startFromNewest = session.unreadScrollPosition == .startFromNewest
        reset(initialUnreadCount: session.timelines[channelId]?.unreadCountOnOpen ?? 0)
    }

    func positioned(atBottom: Bool, offsetFromBottom: Double, newMessagesLineVisible: Bool = false) {
        guard channelId != nil, !positioned else { return }
        positioned = true
        refreshPosts()
        inputs.newMessageLineReached = newMessagesLineVisible
        scrolled(atBottom: atBottom, offsetFromBottom: offsetFromBottom)
    }

    func scrolled(atBottom: Bool, offsetFromBottom: Double) {
        guard positioned else { return }
        if inputs.atBottom != atBottom {
            inputs.atBottom = atBottom
            inputs.lastViewedBottom = max(nowMillis, inputs.latestPostAt)
        }
        var next = state
        next.update(inputs)
        next.updateScrollToBottom(offsetFromBottom: offsetFromBottom, threshold: farFromBottomThreshold)
        assign(next)
    }

    func postsChanged() {
        guard let channelId else { return }
        let added = refreshPosts()
        guard positioned else { return }
        var next = state
        next.update(inputs)
        if added, inputs.atBottom == false, postCount > 0, next.showUnread != true, !newestIsMine {
            session.updateNewMessagesAt(channelId: channelId, lastViewedAt: inputs.lastViewedBottom)
            refreshPosts()
            next.update(inputs)
        }
        assign(next)
    }

    func newMessagesLineVisible() {
        guard positioned, !inputs.newMessageLineReached else { return }
        inputs.newMessageLineReached = true
        apply()
    }

    func focused(atBottom: Bool, offsetFromBottom: Double) {
        guard channelId != nil else { return }
        inputs.focused = true
        inputs.initialOffsetFromBottom = offsetFromBottom
        var next = state
        next.resetHistory()
        assign(next)
        if positioned {
            scrolled(atBottom: atBottom, offsetFromBottom: offsetFromBottom)
        } else {
            positioned(atBottom: atBottom, offsetFromBottom: offsetFromBottom)
        }
    }

    func resized(width newWidth: Double) {
        let next = ToastWidth(width: newWidth)
        if next != width { width = next }
    }

    @discardableResult
    func jump() -> Bool {
        guard let toast = visible else { return false }
        switch toast.kind {
        case .unread, .history, .scrollToBottom: scrollToLatestMessages()
        case .newMessages: scrollToNewMessages()
        case .unreadWithBottomStart: scrollToUnreadMessages()
        }
        return true
    }

    @discardableResult
    func dismiss() -> Bool {
        guard let toast = visible else { return false }
        var next = state
        switch toast.kind {
        case .unread: next.hideUnread()
        case .unreadWithBottomStart: next.hideUnreadWithBottomStart()
        case .newMessages: next.hideNewMessages(lastViewedBottom: nowMillis)
        case .history: next.hideHistory()
        case .scrollToBottom: next.dismissScrollToBottom()
        }
        commit(next)
        return true
    }

    func escape() {
        guard positioned else { return }
        var next = state
        next.escape(lastViewedBottom: nowMillis)
        commit(next)
    }

    func scrollToLatestMessages() {
        var next = state
        if inputs.focused { next.hideHistory() }
        requestScroll(.bottom)
        next.hideUnread()
        next.hideScrollToBottom()
        commit(next)
    }

    func scrollToNewMessages() {
        requestScroll(.newMessages)
        inputs.lastViewedBottom = nowMillis
        var next = state
        next.update(inputs)
        next.hideNewMessages(lastViewedBottom: inputs.lastViewedBottom)
        commit(next)
    }

    func scrollToUnreadMessages() {
        guard let channelId else { return }
        startFromNewest = false
        reset(initialUnreadCount: session.unreadMessageCount(channelId: channelId))
        remountRequest += 1
    }

    private func reset(initialUnreadCount: Int) {
        positioned = false
        postCount = 0
        newestPostId = nil
        newestIsMine = false
        inputs = ChannelToastInputs(lastViewedBottom: nowMillis, startFromNewest: startFromNewest)
        assign(ChannelToastState(initialUnreadCountInChannel: initialUnreadCount))
    }

    @discardableResult
    private func refreshPosts() -> Bool {
        guard let channelId else { return false }
        let posts = session.timelinePosts(channelId: channelId)
        let newest = posts.last?.id
        let added = posts.count != postCount && newest != newestPostId
        postCount = posts.count
        newestPostId = newest
        newestIsMine = posts.last?.userId == session.myId
        inputs.latestPostAt = posts.last?.createAt ?? 0
        inputs.lastViewedAt = session.timelines[channelId]?.lastViewedAtOnOpen ?? 0
        inputs.unreadCount = NewMessagesMarker.unreadCount(
            posts: posts,
            lastViewedAt: inputs.lastViewedAt,
            myId: session.myId,
            collapsedThreads: session.collapsedThreads
        )
        inputs.markedUnread = session.isManuallyUnread(channelId: channelId)
        inputs.startFromNewest = startFromNewest
        return added
    }

    private func apply() {
        var next = state
        next.update(inputs)
        assign(next)
    }

    private func commit(_ next: ChannelToastState) {
        inputs.lastViewedBottom = next.inputs.lastViewedBottom
        assign(next)
    }

    private func assign(_ next: ChannelToastState) {
        if next != state { state = next }
    }
}
