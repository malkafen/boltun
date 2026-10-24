import AppKit
import BoltunKit
import SwiftUI

struct ScrollFollowState: Equatable {
    var isAtBottom = true
    var lastPostId: String?
    var settled = false

    mutating func scrolled(atBottom: Bool) {
        isAtBottom = atBottom
        if atBottom { settled = true }
    }

    mutating func postsChanged(postIds: [String], lastIsMine: Bool) -> Bool {
        let newLast = postIds.last
        let previous = lastPostId
        lastPostId = newLast
        guard let newLast, newLast != previous else { return false }
        guard previous != nil else { return true }
        return isAtBottom || lastIsMine
    }

    mutating func jumpedToBottom() {
        isAtBottom = true
    }
}

struct ScrollMetrics: Equatable {
    var distanceFromTop: CGFloat
    var distanceFromBottom: CGFloat
    var contentHeight: CGFloat = 0
    var containerHeight: CGFloat = 0
    var containerWidth: CGFloat = 0

    static let bottomThreshold: CGFloat = 100
    static let loadOlderThreshold: CGFloat = 600

    var isAtBottom: Bool { distanceFromBottom <= Self.bottomThreshold }
    var shouldLoadOlder: Bool { distanceFromTop < Self.loadOlderThreshold }
    var zone: ScrollZone { ScrollZone(atBottom: isAtBottom, nearTop: shouldLoadOlder) }

    func isVisible(_ frame: CGRect) -> Bool {
        frame.maxY > 0 && frame.minY < containerHeight
    }
}

struct ScrollZone: Equatable {
    var atBottom = true
    var nearTop = false

    static func shouldLoadOlder(zone: ScrollZone, timeline: ChannelTimeline) -> Bool {
        zone.nearTop && timeline.loaded && timeline.hasMoreOlder && !timeline.isLoading
    }
}

extension ScrollPosition {
    mutating func forceScroll(to edge: Edge, edgeItemId: String?) {
        if self.edge == edge, let edgeItemId {
            scrollTo(id: edgeItemId, anchor: edge == .top ? .top : .bottom)
        } else {
            scrollTo(edge: edge)
        }
    }
}

struct TimelineHead: Equatable {
    var firstPostId: String?
    var isLoading = false
    var hasMoreOlder = true

    init(_ timeline: ChannelTimeline) {
        firstPostId = timeline.postIds.first
        isLoading = timeline.isLoading
        hasMoreOlder = timeline.hasMoreOlder
    }
}

struct TimelineReadiness: Equatable {
    var loaded: Bool
    var isLoading: Bool

    init(_ timeline: ChannelTimeline) {
        loaded = timeline.loaded
        isLoading = timeline.isLoading
    }

    var isReady: Bool { loaded && !isLoading }
}

struct ToastSignature: Equatable {
    var postCount: Int
    var lastPostId: String?
    var lastViewedAt: Int64

    init(_ timeline: ChannelTimeline) {
        postCount = timeline.postIds.count
        lastPostId = timeline.postIds.last
        lastViewedAt = timeline.lastViewedAtOnOpen
    }
}

enum InitialPositioning: Equatable {
    case pending
    case positioning
    case done
}

@MainActor
final class ScrollTracker {
    var head: TimelineHead?
    var metrics = ScrollMetrics(distanceFromTop: 0, distanceFromBottom: 0)
    var newMessagesLineVisible = false
    var frames: [String: CGRect] = [:]
    var visibleIds: [String] = []

    nonisolated static let searchStride: CGFloat = 0.8

    func compensation(head newHead: TimelineHead, old: ScrollMetrics, new: ScrollMetrics, settled: Bool) -> CGFloat? {
        let previous = head
        head = newHead
        guard settled, let previous, previous != newHead, new.contentHeight != old.contentHeight, !old.isAtBottom else { return nil }
        return Self.compensatedOffset(preserving: old.distanceFromBottom, in: new)
    }

    nonisolated static func compensatedOffset(preserving distance: CGFloat, in metrics: ScrollMetrics) -> CGFloat? {
        guard abs(metrics.distanceFromBottom - distance) > 1 else { return nil }
        return max(0, metrics.contentHeight - metrics.containerHeight - distance)
    }

    func liveFrame(of id: String) -> CGRect? {
        visibleIds.isEmpty || visibleIds.contains(id) ? frames[id] : nil
    }

    func visibleRange(in items: [TimelineItem]) -> ClosedRange<Int>? {
        let visible = Set(visibleIds)
        let indices = items.indices.filter { visible.contains(items[$0].id) }
        guard let first = indices.first, let last = indices.last else { return nil }
        return first...last
    }

    nonisolated static func alignmentStep(
        frame: CGRect?,
        metrics: ScrollMetrics,
        targetIndex: Int? = nil,
        visible: ClosedRange<Int>? = nil,
        clearance: CGFloat = UnreadScrollTarget.toastClearance
    ) -> AlignmentStep {
        guard let frame else {
            guard let targetIndex, let visible else { return .scrollToItem }
            let stride = max(metrics.containerHeight * searchStride, 1)
            if targetIndex < visible.lowerBound { return .scroll(max(0, metrics.distanceFromTop - stride)) }
            if targetIndex > visible.upperBound { return .scroll(metrics.distanceFromTop + min(stride, max(metrics.distanceFromBottom, 0))) }
            return .scrollToItem
        }
        let delta = frame.minY - clearance
        if abs(delta) <= 1 { return .done }
        if delta > 0 && metrics.distanceFromBottom <= 1 { return .done }
        if delta < 0 && metrics.distanceFromTop <= 0 { return .done }
        return .scroll(max(0, metrics.distanceFromTop + delta))
    }
}

enum AlignmentStep: Equatable {
    case scrollToItem
    case scroll(CGFloat)
    case done
}

struct MessageListView: View {
    let workspace: Workspace
    let channelId: String
    @State private var follow = ScrollFollowState()
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var focusPostId: String?
    @State private var alignTargetId: String?
    @State private var bottomTargetId: String?
    @State private var initial = InitialPositioning.pending
    @State private var tracker = ScrollTracker()
    @State private var mountId = UUID()

    var body: some View {
        let session = workspace.session
        let items = workspace.channelItems(channelId: channelId)
        let tracked = UnreadScrollTarget.trackedIds(items: items)
        let timeline = session.timelines[channelId] ?? ChannelTimeline()
        let lastPost = timeline.postIds.last.flatMap { session.posts[$0] }
        let highlighted = workspace.highlightedPostId
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if timeline.loaded && !timeline.hasMoreOlder {
                    ChannelIntro(workspace: workspace, channelId: channelId)
                } else if timeline.isLoading || !timeline.loaded {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                ForEach(items) { item in
                    TimelineItemView(item: item, workspace: workspace, highlightedPostId: highlighted, onFrame: frameHandler(tracked: tracked.contains(item.id)))
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, 10)
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($position)
        .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.01) { ids in
            tracker.visibleIds = ids
        }
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                distanceFromTop: geometry.contentOffset.y + geometry.contentInsets.top,
                distanceFromBottom: geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height,
                contentHeight: geometry.contentSize.height,
                containerHeight: geometry.containerSize.height,
                containerWidth: geometry.containerSize.width
            )
        } action: { old, metrics in
            scrolled(old: old, metrics: metrics)
        }
        .onChange(of: lastPost?.id, initial: true) {
            postsChanged()
        }
        .onChange(of: ToastSignature(timeline)) {
            toast?.postsChanged()
        }
        .onChange(of: TimelineReadiness(timeline), initial: true) {
            startInitialPositioning()
        }
        .onChange(of: workspace.channelToast.remountRequest) {
            initial = .pending
            workspace.scrollReport.positioned = false
            startInitialPositioning()
        }
        .onChange(of: workspace.scrollRequest, initial: true) { _, request in
            apply(request)
        }
        .overlay(alignment: .top) {
            if toast != nil {
                ChannelToastOverlay(model: workspace.channelToast, now: workspace.now(), calendar: workspace.calendar)
            }
        }
    }

    private var toast: ChannelToastModel? {
        workspace.channelToast.mountId == mountId ? workspace.channelToast : nil
    }

    private var isSettled: Bool {
        follow.settled && initial == .done && focusPostId == nil && alignTargetId == nil && bottomTargetId == nil
    }

    private func prepareToast() {
        let model = workspace.channelToast
        guard model.mountId != mountId else { return }
        model.farFromBottomThreshold = Double(NSScreen.main?.frame.height ?? 900) * 3
        model.begin(channelId: channelId, mountId: mountId)
    }

    private func scrolled(old: ScrollMetrics, metrics: ScrollMetrics) {
        tracker.metrics = metrics
        toast?.resized(width: metrics.containerWidth)
        let session = workspace.session
        let current = session.timelines[channelId] ?? ChannelTimeline()
        if let offset = tracker.compensation(head: TimelineHead(current), old: old, new: metrics, settled: isSettled) {
            position.scrollTo(y: offset)
            return
        }
        guard initial == .done else {
            report(metrics, loadOlder: false)
            return
        }
        follow.scrolled(atBottom: metrics.isAtBottom)
        let loadOlder = follow.settled && ScrollZone.shouldLoadOlder(zone: metrics.zone, timeline: current)
        report(metrics, loadOlder: loadOlder)
        toast?.scrolled(atBottom: metrics.isAtBottom, offsetFromBottom: metrics.distanceFromBottom)
        if loadOlder {
            Task { await session.loadOlder(channelId: channelId) }
        }
    }

    private func postsChanged() {
        let session = workspace.session
        let postIds = session.timelines[channelId]?.postIds ?? []
        let lastIsMine = postIds.last.flatMap { session.posts[$0] }?.userId == session.myId
        let follows = follow.postsChanged(postIds: postIds, lastIsMine: lastIsMine)
        guard follows, initial == .done, focusPostId == nil, alignTargetId == nil else { return }
        scrollToBottom(lastItemId: workspace.channelItems(channelId: channelId).last?.id, animated: true)
    }

    private func startInitialPositioning() {
        prepareToast()
        guard initial == .pending else { return }
        let timeline = workspace.session.timelines[channelId] ?? ChannelTimeline()
        guard TimelineReadiness(timeline).isReady else { return }
        let items = workspace.channelItems(channelId: channelId)
        let target = UnreadScrollTarget.initial(items: items, startFromNewest: workspace.channelToast.startFromNewest)
        workspace.scrollReport.channelId = channelId
        workspace.scrollReport.initialTarget = target.description
        switch target {
        case .bottom:
            initial = .done
            position.forceScroll(to: .bottom, edgeItemId: items.last?.id)
            Task { @MainActor in
                try? await Task.sleep(for: Self.settleDelay)
                finishInitialPositioning()
            }
        case .top(let id):
            initial = .positioning
            alignTop(id) {
                initial = .done
                follow.settled = true
                finishInitialPositioning()
            }
        }
    }

    private func finishInitialPositioning() {
        let metrics = tracker.metrics
        follow.scrolled(atBottom: metrics.isAtBottom)
        workspace.scrollReport.positioned = true
        toast?.positioned(atBottom: metrics.isAtBottom, offsetFromBottom: metrics.distanceFromBottom, newMessagesLineVisible: tracker.newMessagesLineVisible)
    }

    private func cancelInitialPositioning() {
        alignTargetId = nil
        bottomTargetId = nil
        guard initial != .done else { return }
        let wasPositioning = initial == .positioning
        initial = .done
        if wasPositioning { finishInitialPositioning() }
    }

    private func alignTop(_ id: String, completion: @escaping @MainActor () -> Void) {
        bottomTargetId = nil
        alignTargetId = id
        Task { @MainActor in
            for pass in 0..<Self.alignPassLimit {
                try? await Task.sleep(for: Self.settleDelay)
                guard alignTargetId == id else { return }
                let items = workspace.channelItems(channelId: channelId)
                let searching = pass > 0
                let step = ScrollTracker.alignmentStep(
                    frame: tracker.liveFrame(of: id),
                    metrics: tracker.metrics,
                    targetIndex: searching ? items.firstIndex { $0.id == id } : nil,
                    visible: searching ? tracker.visibleRange(in: items) : nil
                )
                switch step {
                case .scrollToItem:
                    position.scrollTo(id: id, anchor: pass.isMultiple(of: 2) ? .top : .topLeading)
                case .scroll(let offset):
                    position.scrollTo(y: offset)
                case .done:
                    alignTargetId = nil
                    completion()
                    return
                }
            }
            guard alignTargetId == id else { return }
            alignTargetId = nil
            completion()
        }
    }

    private func frameHandler(tracked: Bool) -> ((String, CGRect?) -> Void)? {
        tracked ? { itemFrameChanged($0, $1) } : nil
    }

    private func itemFrameChanged(_ id: String, _ frame: CGRect?) {
        tracker.frames[id] = frame
        guard id == UnreadScrollTarget.newMessagesId else { return }
        guard let frame else {
            tracker.newMessagesLineVisible = false
            workspace.scrollReport.newMessagesLineTop = nil
            return
        }
        let visible = tracker.metrics.isVisible(frame)
        tracker.newMessagesLineVisible = visible
        workspace.scrollReport.newMessagesLineTop = frame.minY
        if visible { toast?.newMessagesLineVisible() }
    }

    private func report(_ metrics: ScrollMetrics, loadOlder: Bool) {
        var report = workspace.scrollReport
        if report.channelId != channelId { report = ScrollReport(channelId: channelId) }
        report.distanceFromTop = metrics.distanceFromTop
        report.distanceFromBottom = metrics.distanceFromBottom
        report.contentHeight = metrics.contentHeight
        report.containerHeight = metrics.containerHeight
        if loadOlder { report.loadOlderRequests += 1 }
        workspace.scrollReport = report
    }

    private func apply(_ request: ScrollRequest?) {
        guard let request, request.channelId == channelId, request.sequence > workspace.handledScrollSequence else { return }
        workspace.handledScrollSequence = request.sequence
        switch request.target {
        case .top:
            cancelInitialPositioning()
            follow.settled = true
            position.forceScroll(to: .top, edgeItemId: workspace.channelItems(channelId: channelId).first?.id)
        case .bottom:
            cancelInitialPositioning()
            follow.jumpedToBottom()
            scrollToBottom(lastItemId: workspace.channelItems(channelId: channelId).last?.id)
        case .newMessages:
            guard initial == .done, case .top(let id)? = UnreadScrollTarget.newMessages(items: workspace.channelItems(channelId: channelId)) else { return }
            alignTop(id) {}
        case .post(let postId):
            focus(postId)
        }
    }

    private func scrollToBottom(lastItemId: String?, animated: Bool = false) {
        guard let lastItemId else {
            position.scrollTo(edge: .bottom)
            return
        }
        alignTargetId = nil
        bottomTargetId = lastItemId
        Task { @MainActor in
            for (pass, delay) in Self.alignPasses.enumerated() {
                try? await Task.sleep(for: delay)
                guard bottomTargetId == lastItemId else { return }
                withAnimation(animated && pass == 0 ? .easeOut(duration: 0.15) : nil) {
                    position.scrollTo(id: lastItemId, anchor: pass.isMultiple(of: 2) ? .bottom : .bottomLeading)
                }
            }
            try? await Task.sleep(for: Self.settleDelay)
            if bottomTargetId == lastItemId { bottomTargetId = nil }
        }
    }

    private func focus(_ postId: String) {
        alignTargetId = nil
        bottomTargetId = nil
        if initial != .done { initial = .done }
        focusPostId = postId
        follow.scrolled(atBottom: false)
        Task { @MainActor in
            for delay in Self.focusPasses {
                try? await Task.sleep(for: delay)
                guard focusPostId == postId else { return }
                position.scrollTo(id: postId, anchor: .center)
            }
            try? await Task.sleep(for: Self.settleDelay)
            guard focusPostId == postId else { return }
            follow.settled = true
            focusPostId = nil
            let metrics = tracker.metrics
            workspace.scrollReport.positioned = true
            toast?.focused(atBottom: metrics.isAtBottom, offsetFromBottom: metrics.distanceFromBottom)
        }
    }

    static let focusPasses: [Duration] = [.milliseconds(30), .milliseconds(120), .milliseconds(300)]
    static let alignPasses: [Duration] = [.zero, .milliseconds(30), .milliseconds(120), .milliseconds(300)]
    static let alignPassLimit = 100
    static let settleDelay: Duration = .milliseconds(40)
}

struct ChannelIntro: View {
    let workspace: Workspace
    let channelId: String

    var body: some View {
        let session = workspace.session
        if let channel = session.channels[channelId] {
            let name = session.displayName(channel: channel)
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .scaledFont(22, weight: .bold)
                    .foregroundStyle(Theme.textPrimary)
                Text(ChannelIntro.text(for: channel, name: name))
                    .scaledFont(13)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 12)
        }
    }

    static func text(for channel: Channel, name: String) -> String {
        switch channel.type {
        case .direct: return "This is the start of your conversation with \(name)."
        case .group: return "This is the start of your group conversation."
        case .open, .private:
            let purpose = channel.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
            return purpose.isEmpty ? "This is the start of ~\(name)." : "This is the start of ~\(name). \(purpose)"
        }
    }
}
