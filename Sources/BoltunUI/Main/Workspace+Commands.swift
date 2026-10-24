import BoltunKit
import Foundation

struct ScrollRequest: Equatable {
    enum Target: Equatable {
        case top
        case bottom
        case post(String)
    }

    var channelId: String
    var target: Target
    var sequence: Int
}

struct ScrollReport: Equatable, Codable, Sendable {
    var channelId = ""
    var distanceFromTop: Double = 0
    var distanceFromBottom: Double = 0
    var contentHeight: Double = 0
    var unseenCount = 0
    var loadOlderRequests = 0
}

extension Workspace {
    func perform(_ command: AppCommand, router: AppRouter?) async {
        switch command {
        case .focusQuickSwitcher:
            if showQuickSwitcher { showQuickSwitcher = false } else { openQuickSwitcher() }
        case .focusSearch:
            searchFocusRequest += 1
        case .focusComposer:
            focusComposer()
        case .toggleThreadPane:
            toggleRightPane()
        case .openThread, .highlightPost:
            await consumePendingRoute(router)
        case .toggleSidebar:
            break
        }
    }

    func consumePendingRoute(_ router: AppRouter?) async {
        guard let router else { return }
        let postId = router.consumePendingPostId()
        if let rootId = router.consumePendingThreadRootId() {
            await openThread(rootId: rootId)
        }
        if let postId { await highlight(postId: postId) }
    }

    func openQuickSwitcher(query: String = "") {
        quickSwitcherQuery = query
        showQuickSwitcher = true
    }

    func focusComposer() {
        guard let channelId = session.currentChannelId else { return }
        composer(for: ComposerTarget(channelId: channelId)).requestFocus()
    }

    func toggleRightPane() {
        if rightPane != nil {
            closeRightPane()
        } else if let rootId = lastThreadRootId, session.posts[rootId] != nil {
            Task { await openThread(rootId: rootId) }
        } else {
            rightPane = .search
        }
    }

    func requestScroll(_ target: ScrollRequest.Target, channelId: String? = nil) {
        guard let channelId = channelId ?? session.currentChannelId else { return }
        scrollSequence += 1
        scrollRequest = ScrollRequest(channelId: channelId, target: target, sequence: scrollSequence)
    }

    func highlight(postId: String) async {
        guard let post = session.posts[postId] else { return }
        if session.collapsedThreads && post.isReply {
            if threadRootId != post.rootId { await openThread(rootId: post.rootId) }
            let root = session.posts[post.rootId] ?? post
            await reveal(root)
            requestScroll(.post(root.id), channelId: post.channelId)
        } else {
            await reveal(post)
            requestScroll(.post(postId), channelId: post.channelId)
        }
        highlightedPostId = postId
        highlightTask?.cancel()
        let duration = highlightDuration
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.highlightedPostId == postId else { return }
            self.highlightedPostId = nil
        }
    }

    func reveal(_ post: Post, maxPages: Int = 20) async {
        var pages = 0
        var waits = 0
        while pages < maxPages, waits < 100, let timeline = session.timelines[post.channelId], timeline.loaded,
              !timeline.postIds.contains(post.id), timeline.hasMoreOlder {
            if timeline.isLoading {
                waits += 1
                try? await Task.sleep(for: .milliseconds(50))
                continue
            }
            await session.loadOlder(channelId: post.channelId)
            pages += 1
        }
    }
}
