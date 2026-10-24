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

    static let bottomThreshold: CGFloat = 80
    static let loadOlderThreshold: CGFloat = 600

    var isAtBottom: Bool { distanceFromBottom < Self.bottomThreshold }
    var shouldLoadOlder: Bool { distanceFromTop < Self.loadOlderThreshold }
}

struct MessageListView: View {
    let workspace: Workspace
    let channelId: String
    @State private var follow = ScrollFollowState()
    @State private var position = ScrollPosition(edge: .bottom)

    var body: some View {
        let session = workspace.session
        let items = workspace.channelItems(channelId: channelId)
        let timeline = session.timelines[channelId] ?? ChannelTimeline()
        let lastPost = timeline.postIds.last.flatMap { session.posts[$0] }
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
                    TimelineItemView(item: item, workspace: workspace)
                }
            }
            .padding(.bottom, 10)
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($position)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                distanceFromTop: geometry.contentOffset.y + geometry.contentInsets.top,
                distanceFromBottom: geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
            )
        } action: { _, metrics in
            follow.scrolled(atBottom: metrics.isAtBottom)
            if metrics.shouldLoadOlder && timeline.loaded && timeline.hasMoreOlder && !timeline.isLoading {
                Task { await session.loadOlder(channelId: channelId) }
            }
        }
        .onChange(of: lastPost?.id, initial: true) { _, newId in
            if follow.postsChanged(lastPostId: newId, count: timeline.postIds.count, lastIsMine: lastPost?.userId == session.myId) {
                withAnimation(.easeOut(duration: 0.15)) { position.scrollTo(edge: .bottom) }
            }
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
            .font(.system(size: 12, weight: .semibold))
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
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(ChannelIntro.text(for: channel, name: name))
                    .font(.system(size: 13))
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
