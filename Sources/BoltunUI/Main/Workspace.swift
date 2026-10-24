import AppKit
import BoltunKit
import BoltunMarkup
import Foundation
import Observation

enum RightPane: Equatable {
    case thread(String)
    case search
}

struct ComposerTarget: Hashable, Sendable {
    var channelId: String
    var rootId: String = ""

    var isThread: Bool { !rootId.isEmpty }
}

@MainActor
final class RenderCache {
    private final class Box {
        let blocks: [MessageBlock]
        init(_ blocks: [MessageBlock]) { self.blocks = blocks }
    }

    private let cache = NSCache<NSString, Box>()
    private(set) var renders = 0

    init(limit: Int = 3000) {
        cache.countLimit = limit
    }

    func blocks(for post: Post, context: MarkupContext) -> [MessageBlock] {
        let key = "\(post.id)|\(post.message.hashValue)|\(post.message.utf16.count)" as NSString
        if let hit = cache.object(forKey: key) { return hit.blocks }
        let blocks = MessageRenderer.render(post.message, context: context)
        renders += 1
        cache.setObject(Box(blocks), forKey: key)
        return blocks
    }
}

@MainActor
@Observable
final class Workspace {
    let session: ServerSession
    let serverURL: URL
    var rightPane: RightPane?
    var searchQuery = ""
    var searchResults: [Post] = []
    var isSearching = false
    var showQuickSwitcher = false
    var showBrowseChannels = false
    var showDirectMessages = false
    var pendingDeletion: Post?
    var pendingBurn: Post?
    var previewFile: FileInfo?
    var notificationPreferences: ChannelNotificationsTarget?
    var downloading: Set<String> = []
    var recentEmojis: [String] = []
    var memberCounts: [String: Int] = [:]
    var localError: String?
    var quickSwitcherQuery = ""
    var scrollRequest: ScrollRequest?
    var highlightedPostId: String?
    var searchFocusRequest = 0
    var threadSeenAt: [String: Int64] = [:]
    @ObservationIgnored var scrollReport = ScrollReport()
    @ObservationIgnored var scrollSequence = 0
    @ObservationIgnored var handledScrollSequence = 0
    @ObservationIgnored var highlightTask: Task<Void, Never>?
    @ObservationIgnored var highlightDuration: Duration = .seconds(2.5)
    @ObservationIgnored private(set) var lastThreadRootId: String?

    var visibleError: String? { localError ?? session.lastError }

    func dismissError() {
        localError = nil
        session.clearError()
    }

    @ObservationIgnored private var composers: [ComposerTarget: ComposerState] = [:]
    @ObservationIgnored let renderCache = RenderCache()
    @ObservationIgnored private var markupKey = ""
    @ObservationIgnored private var markupValue = MarkupContext()
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored var calendar: Calendar = .current
    @ObservationIgnored var pasteboard: NSPasteboard = .general
    @ObservationIgnored var downloadDirectory: URL = DownloadDestination.downloadsDirectory
    @ObservationIgnored var openExternal: (URL) -> Void = { NSWorkspace.shared.open($0) }
    @ObservationIgnored var revealInFinder: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }

    init(session: ServerSession, serverURL: URL) {
        self.session = session
        self.serverURL = serverURL
    }

    func composer(for target: ComposerTarget) -> ComposerState {
        if let existing = composers[target] { return existing }
        let state = ComposerState(target: target, session: session)
        composers[target] = state
        return state
    }

    var composerCount: Int { composers.count }

    var threadRootId: String? {
        if case .thread(let id) = rightPane { return id }
        return nil
    }

    func openThread(rootId: String) async {
        if let previous = threadRootId, previous != rootId {
            markThreadSeen(previous)
            session.closeThread(rootId: previous)
        }
        markThreadSeen(rootId)
        rightPane = .thread(rootId)
        lastThreadRootId = rootId
        await session.openThread(rootId: rootId)
    }

    func closeRightPane() {
        if let rootId = threadRootId {
            markThreadSeen(rootId)
            session.closeThread(rootId: rootId)
        }
        rightPane = nil
    }

    func markThreadSeen(_ rootId: String) {
        let seen = max(now().mattermostMillis, session.posts[rootId]?.lastReplyAt ?? 0)
        if (threadSeenAt[rootId] ?? 0) < seen { threadSeenAt[rootId] = seen }
    }

    var threadFollowing: Bool? {
        guard session.collapsedThreads, let rootId = threadRootId, let root = session.posts[rootId], !root.isReply else { return nil }
        return session.isFollowing(threadId: rootId)
    }

    func setFollowing(threadId: String, _ following: Bool) async {
        await session.setFollowing(threadId: threadId, following)
    }

    func search() async {
        let terms = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !terms.isEmpty else { return }
        rightPane = .search
        isSearching = true
        searchResults = await session.search(terms)
        isSearching = false
    }

    func jump(to post: Post) async {
        if session.currentChannelId != post.channelId { await session.selectChannel(post.channelId) }
        await highlight(postId: post.id)
    }

    func select(channelId: String) async {
        guard channelId != session.currentChannelId else { return }
        await session.selectChannel(channelId)
    }

    var navigationOrder: [String] {
        session.sidebar.flatMap(\.channelIds)
    }

    func navigate(offset: Int) async {
        guard let target = ChannelNavigator.adjacent(in: navigationOrder, from: session.currentChannelId, offset: offset) else { return }
        await select(channelId: target)
    }

    func navigateUnread(forward: Bool) async {
        let order = navigationOrder
        let unread = Set(order.filter { id in
            let value = session.unread(channelId: id)
            return value.unread || value.mentions > 0
        })
        guard let target = ChannelNavigator.nextUnread(in: order, from: session.currentChannelId, unread: unread, forward: forward) else { return }
        await select(channelId: target)
    }

    func quickSwitchItems() -> [QuickSwitchItem] {
        var seen = Set<String>()
        var result: [QuickSwitchItem] = []
        let teamNames = Dictionary(session.teams.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        for id in navigationOrder + session.members.keys.sorted() where !seen.contains(id) {
            guard let channel = session.channels[id], !channel.isArchived else { continue }
            guard channel.type.isDirectOrGroup || channel.teamId == session.currentTeamId else { continue }
            seen.insert(id)
            let unread = session.unread(channelId: id)
            let kind: QuickSwitchItem.Kind
            switch channel.type {
            case .open: kind = .open
            case .private: kind = .private
            case .direct: kind = .direct
            case .group: kind = .group
            }
            let partner = channel.directPartnerId(me: session.myId).flatMap { session.users[$0] }
            let subtitle = partner.map { "@\($0.username)" } ?? (channel.type.isDirectOrGroup ? "" : (teamNames[channel.teamId] ?? ""))
            result.append(QuickSwitchItem(
                channelId: id,
                title: session.displayName(channel: channel),
                subtitle: subtitle,
                kind: kind,
                unread: unread.unread,
                mentions: unread.mentions,
                searchKey: partner?.username ?? channel.name
            ))
        }
        return result
    }

    func handle(link url: URL) async {
        switch LinkRouter.action(for: url) {
        case .mention(let username):
            await openDirect(username: username)
        case .channel(let name):
            if let channel = session.channels.values.first(where: { $0.name == name && ($0.teamId == session.currentTeamId || $0.teamId.isEmpty) && session.members[$0.id] != nil }) {
                await select(channelId: channel.id)
            }
        case .hashtag(let tag):
            searchQuery = "#" + tag
            await search()
        case .external(let url):
            openExternal(url)
        }
    }

    func openDirect(username: String) async {
        let lowered = username.lowercased()
        guard !["channel", "all", "here"].contains(lowered) else { return }
        var user = session.users.values.first { $0.username.lowercased() == lowered }
        if user == nil { user = try? await session.client.usersByUsernames([username]).first }
        guard let user else { return }
        await session.openDirect(userId: user.id)
    }

    func toggleReaction(postId: String, emojiName: String) async {
        recordEmoji(emojiName)
        await session.toggleReaction(postId: postId, emojiName: emojiName)
    }

    func recordEmoji(_ name: String) {
        recentEmojis.removeAll { $0 == name }
        recentEmojis.insert(name, at: 0)
        if recentEmojis.count > 24 { recentEmojis.removeLast(recentEmojis.count - 24) }
    }

    func reply(to post: Post) async {
        await openThread(rootId: post.threadId)
        composer(for: ComposerTarget(channelId: post.channelId, rootId: post.threadId)).requestFocus()
    }

    func beginEdit(_ post: Post) {
        let target = threadRootId == post.threadId && post.isReply ? ComposerTarget(channelId: post.channelId, rootId: post.threadId) : ComposerTarget(channelId: post.channelId)
        composer(for: target).beginEditing(post)
    }

    func requestDelete(_ post: Post) {
        pendingDeletion = post
    }

    func confirmDelete() async {
        guard let post = pendingDeletion else { return }
        pendingDeletion = nil
        await session.delete(postId: post.id)
        if threadRootId == post.id { rightPane = nil }
    }

    func copyText(_ post: Post) {
        pasteboard.clearContents()
        pasteboard.setString(post.message, forType: .string)
    }

    var currentTeamName: String {
        session.currentTeam?.name ?? session.teams.first?.name ?? ""
    }

    func link(for post: Post) -> String {
        let teamName = session.channels[post.channelId].flatMap { channel in session.teams.first { $0.id == channel.teamId }?.name } ?? currentTeamName
        return Permalink.post(server: serverURL, teamName: teamName, postId: post.id)
    }

    func link(for channel: Channel) -> String {
        let teamName = session.teams.first { $0.id == channel.teamId }?.name ?? currentTeamName
        return Permalink.channel(server: serverURL, teamName: teamName, channelName: channel.name)
    }

    func copyLink(_ post: Post) {
        pasteboard.clearContents()
        pasteboard.setString(link(for: post), forType: .string)
    }

    func copyLink(_ channel: Channel) {
        pasteboard.clearContents()
        pasteboard.setString(link(for: channel), forType: .string)
    }

    func togglePin(_ post: Post) async {
        await session.setPinned(postId: post.id, pinned: !post.isPinned)
    }

    func toggleAcknowledgement(postId: String) async {
        await session.toggleAcknowledgement(postId: postId)
    }

    func revealBurnOnRead(postId: String) async {
        await session.revealBurnOnRead(postId: postId)
    }

    func burnOnReadActivated(_ model: BurnOnReadRowModel) {
        if model.isSender {
            pendingBurn = session.posts[model.postId]
        } else if !model.isRevealed {
            Task { await revealBurnOnRead(postId: model.postId) }
        }
    }

    func confirmBurn() async {
        guard let post = pendingBurn else { return }
        pendingBurn = nil
        await session.burn(postId: post.id)
        if threadRootId == post.id { rightPane = nil }
    }

    @discardableResult
    func download(_ file: FileInfo) async -> URL? {
        guard !downloading.contains(file.id) else { return nil }
        downloading.insert(file.id)
        defer { downloading.remove(file.id) }
        do {
            let data = try await session.client.data(at: session.client.fileURL(id: file.id))
            let destination = DownloadDestination.uniqueURL(in: downloadDirectory, filename: file.name)
            try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            revealInFinder(destination)
            return destination
        } catch {
            localError = "Download failed: \(APIError.wrap(error).localizedDescription)"
            return nil
        }
    }

    func loadMemberCount(channelId: String) async {
        guard memberCounts[channelId] == nil, let channel = session.channels[channelId], !channel.type.isDirectOrGroup || channel.type == .group else { return }
        if let stats = try? await session.client.channelStats(channelId: channelId) {
            memberCounts[channelId] = stats.memberCount
        }
    }

    func markupContext() -> MarkupContext {
        let mentionKeys = (session.me?.notifyProps["mention_keys"] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let key = "\(session.myId)|\(session.channels.count)|\(session.customEmojis.count)|\(mentionKeys.joined(separator: ","))"
        if key == markupKey { return markupValue }
        var names: [String: String] = [:]
        for channel in session.channels.values where !channel.type.isDirectOrGroup {
            names[channel.name] = channel.displayName
        }
        markupValue = MarkupContext(
            myUsername: session.me?.username ?? "",
            mentionKeys: mentionKeys,
            channelDisplayNames: names,
            customEmojiNames: Set(session.customEmojis.keys),
            serverURL: serverURL
        )
        markupKey = key
        return markupValue
    }

    var mentionKeys: [String] { markupContext().mentionKeys }

    func timelineContext(
        lastViewedAt: Int64,
        showReplyContext: Bool,
        collapsedThreads: Bool = false,
        followThreads: Bool = false,
        readStates: [String: PostReadState] = [:]
    ) -> TimelineContext {
        let session = session
        let markup = markupContext()
        let cache = renderCache
        let seen = threadSeenAt
        let avatarURL: (String) -> URL? = { userId in
            session.client.profileImageURL(userId: userId, lastPictureUpdate: session.users[userId]?.lastPictureUpdate ?? 0)
        }
        return TimelineContext(
            myId: session.myId,
            myUsername: session.me?.username ?? "",
            mentionKeys: markup.mentionKeys,
            lastViewedAt: lastViewedAt,
            now: now(),
            calendar: calendar,
            showReplyContext: showReplyContext,
            collapsedThreads: collapsedThreads,
            followThreads: followThreads,
            postPriorityEnabled: session.postPriorityEnabled,
            acknowledgementsEnabled: session.acknowledgementsEnabled,
            burnOnReadEnabled: session.burnOnReadEnabled,
            openThreadId: threadRootId,
            readStates: readStates,
            canToggleAcknowledgement: { session.canToggleAcknowledgement(postId: $0) },
            burnOnReadReceipt: { session.burnOnReadReceipt(postId: $0) },
            isRevealing: { session.isRevealing(postId: $0) },
            displayName: { session.displayName(for: $0) },
            userName: { session.displayName(userId: $0) },
            post: { session.posts[$0] },
            avatarURL: { post in
                guard post.overrideUsername == nil else { return nil }
                return avatarURL(post.userId)
            },
            userAvatarURL: avatarURL,
            threadSeenAt: { seen[$0] ?? 0 },
            status: { session.statuses[$0] },
            isFollowing: { session.isFollowing(threadId: $0) },
            customEmojiId: { session.customEmojis[$0]?.id },
            render: { cache.blocks(for: $0, context: markup) }
        )
    }

    func channelItems(channelId: String) -> [TimelineItem] {
        let timeline = session.timelines[channelId] ?? ChannelTimeline()
        return TimelineBuilder.items(
            posts: session.timelinePosts(channelId: channelId),
            context: timelineContext(
                lastViewedAt: timeline.lastViewedAtOnOpen,
                showReplyContext: !session.collapsedThreads,
                collapsedThreads: session.collapsedThreads,
                followThreads: session.collapsedThreads,
                readStates: session.readStates(channelId: channelId)
            )
        )
    }

    func threadItems(rootId: String) -> [TimelineItem] {
        TimelineBuilder.threadItems(
            posts: session.threadPosts(rootId: rootId),
            context: timelineContext(lastViewedAt: 0, showReplyContext: false, followThreads: session.collapsedThreads)
        )
    }

    func emojiChoices(query: String, limit: Int = 120) -> [(name: String, glyph: String)] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        var result: [(name: String, glyph: String)] = []
        var seen = Set<String>()
        func add(_ name: String, _ glyph: String) {
            guard !seen.contains(name) else { return }
            seen.insert(name)
            result.append((name, glyph))
        }
        if trimmed.isEmpty {
            for name in recentEmojis { if let glyph = EmojiGlyph.glyph(for: name) { add(name, glyph) } }
            for item in EmojiGlyph.frequent { add(item.name, item.glyph) }
            for item in Emoji.search("", limit: limit) { add(item.name, item.glyph) }
        } else {
            for item in Emoji.search(trimmed, limit: limit) { add(item.name, item.glyph) }
            for item in EmojiGlyph.frequent where item.name.contains(trimmed) { add(item.name, item.glyph) }
        }
        return Array(result.prefix(limit))
    }
}
