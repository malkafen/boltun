import BoltunKit
import SwiftUI

struct ScrollFollowState: Equatable {
    var isAtBottom = true
    var unseenCount = 0
    var lastPostId: String?
    var postCount = 0

    mutating func scrolled(atBottom: Bool) {
        isAtBottom = atBottom
        if atBottom { unseenCount = 0 }
    }

    mutating func postsChanged(lastPostId newLast: String?, count: Int, lastIsMine: Bool) -> Bool {
        defer {
            lastPostId = newLast
            postCount = count
        }
        guard let newLast, newLast != lastPostId else { return false }
        guard lastPostId != nil else { return true }
        if isAtBottom || lastIsMine {
            unseenCount = 0
            return true
        }
        unseenCount += max(1, count - postCount)
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

struct MessageListView: View {
    let workspace: Workspace
    let channelId: String
    @State private var follow = ScrollFollowState()
    @State private var zone = ScrollZone()
    @State private var position = ScrollPosition(edge: .bottom)

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
                contentHeight: geometry.contentSize.height
            )
        } action: { _, metrics in
            follow.scrolled(atBottom: metrics.isAtBottom)
            let current = session.timelines[channelId] ?? ChannelTimeline()
            let loadOlder = ScrollZone.shouldLoadOlder(zone: metrics.zone, timeline: current)
            report(metrics, loadOlder: loadOlder)
            if loadOlder {
                Task { await session.loadOlder(channelId: channelId) }
            }
        }
        .onChange(of: lastPost?.id, initial: true) { _, newId in
            if follow.postsChanged(lastPostId: newId, count: timeline.postIds.count, lastIsMine: lastPost?.userId == session.myId) {
                withAnimation(.easeOut(duration: 0.15)) { position.scrollTo(edge: .bottom) }
            }
        }
        .onChange(of: workspace.scrollRequest, initial: true) { _, request in
            apply(request)
        }
        .overlay(alignment: .bottom) {
            if follow.unseenCount > 0 {
                NewMessagesPill(count: follow.unseenCount) {
                    follow.jumpedToBottom()
                    withAnimation { position.scrollTo(edge: .bottom) }
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
            position.scrollTo(edge: .top)
        case .bottom:
            follow.jumpedToBottom()
            position.scrollTo(edge: .bottom)
        case .post(let postId):
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeInOut(duration: 0.25)) { position.scrollTo(id: postId, anchor: .center) }
            }
        }
    }
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
