import BoltunKit
import SwiftUI

struct ScrollFollowState: Equatable {
    var isAtBottom = true
    var unseenCount = 0
    var lastPostId: String?
    var settled = false

    mutating func scrolled(atBottom: Bool) {
        isAtBottom = atBottom
        if atBottom {
            unseenCount = 0
            settled = true
        }
    }

    mutating func postsChanged(postIds: [String], lastIsMine: Bool) -> Bool {
        let newLast = postIds.last
        let previous = lastPostId
        lastPostId = newLast
        guard let newLast, newLast != previous else { return false }
        guard let previous else { return true }
        if isAtBottom || lastIsMine {
            unseenCount = 0
            return true
        }
        let appended = postIds.lastIndex(of: previous).map { postIds.count - 1 - $0 } ?? 1
        unseenCount += max(1, appended)
        return false
    }

    mutating func jumpedToBottom() {
        unseenCount = 0
        isAtBottom = true
    }
}

struct ScrollMetrics: Equatable {
    var distanceFromTop: CGFloat
    var distanceFromBottom: CGFloat
    var contentHeight: CGFloat = 0
    var containerHeight: CGFloat = 0

    static let bottomThreshold: CGFloat = 80
    static let loadOlderThreshold: CGFloat = 600

    var isAtBottom: Bool { distanceFromBottom < Self.bottomThreshold }
    var shouldLoadOlder: Bool { distanceFromTop < Self.loadOlderThreshold }
    var zone: ScrollZone { ScrollZone(atBottom: isAtBottom, nearTop: shouldLoadOlder) }
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

@MainActor
final class ScrollTracker {
    var head: TimelineHead?

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
}

struct MessageListView: View {
    let workspace: Workspace
    let channelId: String
    @State private var follow = ScrollFollowState()
    @State private var zone = ScrollZone()
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var focusPostId: String?
    @State private var tracker = ScrollTracker()

    var body: some View {
        let session = workspace.session
        let items = workspace.channelItems(channelId: channelId)
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
                    TimelineItemView(item: item, workspace: workspace, highlightedPostId: highlighted)
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, 10)
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($position)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                distanceFromTop: geometry.contentOffset.y + geometry.contentInsets.top,
                distanceFromBottom: geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height,
                contentHeight: geometry.contentSize.height,
                containerHeight: geometry.containerSize.height
            )
        } action: { old, metrics in
            let current = session.timelines[channelId] ?? ChannelTimeline()
            if let offset = tracker.compensation(head: TimelineHead(current), old: old, new: metrics, settled: follow.settled && focusPostId == nil) {
                position.scrollTo(y: offset)
                return
            }
            follow.scrolled(atBottom: metrics.isAtBottom)
            let loadOlder = follow.settled && ScrollZone.shouldLoadOlder(zone: metrics.zone, timeline: current)
            report(metrics, loadOlder: loadOlder)
            if loadOlder {
                Task { await session.loadOlder(channelId: channelId) }
            }
        }
        .onChange(of: lastPost?.id, initial: true) {
            let postIds = session.timelines[channelId]?.postIds ?? []
            if follow.postsChanged(postIds: postIds, lastIsMine: postIds.last.flatMap { session.posts[$0] }?.userId == session.myId), focusPostId == nil {
                withAnimation(.easeOut(duration: 0.15)) { position.forceScroll(to: .bottom, edgeItemId: postIds.last) }
            }
            if workspace.scrollReport.channelId == channelId {
                workspace.scrollReport.unseenCount = follow.unseenCount
            }
        }
        .onChange(of: workspace.scrollRequest, initial: true) { _, request in
            apply(request)
        }
        .overlay(alignment: .bottom) {
            if follow.unseenCount > 0 {
                NewMessagesPill(count: follow.unseenCount) {
                    follow.jumpedToBottom()
                    withAnimation { position.forceScroll(to: .bottom, edgeItemId: items.last?.id) }
                }
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func report(_ metrics: ScrollMetrics, loadOlder: Bool) {
        var report = workspace.scrollReport
        if report.channelId != channelId { report = ScrollReport(channelId: channelId) }
        report.distanceFromTop = metrics.distanceFromTop
        report.distanceFromBottom = metrics.distanceFromBottom
        report.contentHeight = metrics.contentHeight
        report.unseenCount = follow.unseenCount
        if loadOlder { report.loadOlderRequests += 1 }
        workspace.scrollReport = report
    }

    private func apply(_ request: ScrollRequest?) {
        guard let request, request.channelId == channelId, request.sequence > workspace.handledScrollSequence else { return }
        workspace.handledScrollSequence = request.sequence
        switch request.target {
        case .top:
            follow.settled = true
            position.forceScroll(to: .top, edgeItemId: workspace.channelItems(channelId: channelId).first?.id)
        case .bottom:
            follow.jumpedToBottom()
            position.forceScroll(to: .bottom, edgeItemId: workspace.channelItems(channelId: channelId).last?.id)
        case .post(let postId):
            focusPostId = postId
            follow.scrolled(atBottom: false)
            Task { @MainActor in
                for delay in Self.focusPasses {
                    try? await Task.sleep(for: delay)
                    guard focusPostId == postId else { return }
                    position.scrollTo(id: postId, anchor: .center)
                }
                follow.settled = true
                focusPostId = nil
            }
        }
    }

    static let focusPasses: [Duration] = [.milliseconds(30), .milliseconds(120), .milliseconds(300)]
}

struct NewMessagesPill: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                Text(count == 1 ? "1 new message" : "\(count) new messages")
            }
            .scaledFont(12, weight: .semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.accent))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
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
