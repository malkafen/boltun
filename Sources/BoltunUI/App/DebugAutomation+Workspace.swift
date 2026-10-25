import AppKit
import BoltunKit
import Foundation

struct AutomationUIState: Codable, Equatable, Sendable {
    struct BurnOnReadSummary: Codable, Equatable, Sendable {
        var isSender: Bool
        var revealed: Bool
        var expireAt: Int64
        var readBy: Int
        var recipients: Int?
    }

    struct PostSummary: Codable, Equatable, Sendable {
        var id: String
        var user: String
        var message: String
        var rootId: String
        var reactions: [String]
        var reactedBy: [String: [String]] = [:]
        var files: Int
        var edited: Bool
        var replyCount: Int = 0
        var following: Bool?
        var status: String?
        var priority: String?
        var requestedAck: Bool = false
        var acknowledgedBy: [String] = []
        var burnOnRead: BurnOnReadSummary?
        var readStatus: String?
        var seenBy: [String] = []
        var readIndicator = false
    }

    struct ReadStatusTracking: Codable, Equatable, Sendable {
        var enabled: Bool
        var tracked: Bool
        var polling: Bool
        var total: Int
        var unseenByMember: [String: Int]
    }

    struct Composer: Codable, Equatable, Sendable {
        var text: String
        var editingPostId: String?
        var suggestions: [String]
        var selectedSuggestion: Int
        var uploads: [String]
        var height: Double
        var priority: String = ""
        var requestedAck = false
        var persistentNotifications = false
        var burnOnRead = false
    }

    struct ToastSummary: Codable, Equatable, Sendable {
        var kind: String
        var message: String
        var action: String?
        var showActions: Bool
        var count: Int
        var since: Int64
    }

    struct ReadInfoFeatures: Codable, Equatable, Sendable {
        var postPriority: Bool
        var acknowledgements: Bool
        var persistentNotifications: Bool
        var burnOnRead: Bool
        var licenseSku: String
    }

    var windowTitle: String
    var firstResponder: String?
    var rightPane: String?
    var threadPosts: [PostSummary]
    var quickSwitcher: Bool
    var quickSwitcherResults: [String]
    var searchResults: [String]
    var highlightedPostId: String?
    var scroll: ScrollReport
    var timelineCount: Int
    var timelineUniqueCount: Int
    var hasMoreOlder: Bool
    var timelineLoading: Bool
    var recentPosts: [PostSummary]
    var composer: Composer?
    var threadComposer: Composer?
    var typing: [String]
    var unreadChannels: [String]
    var mentionChannels: [String: Int]
    var mutedChannels: [String]
    var favorites: [String]
    var collapsedCategories: [String]
    var sheets: [String]
    var error: String?
    var workspaces: Int
    var cachedSessionPosts: Int
    var editors: [Editor] = []
    var collapsedThreads = false
    var myStatus: String?
    var threadFollowing: Bool?
    var readInfo: ReadInfoFeatures?
    var readStatus: ReadStatusTracking?
    var sidebar: [SidebarCategorySummary] = []
    var toast: ToastSummary?
    var lastViewedAtOnOpen: Int64 = 0
    var profile: ProfileSummary?
    var members: MembersSummary?
    var channelFiles: ChannelFilesSummary?

    struct Editor: Codable, Equatable, Sendable {
        var spellChecking: Bool
        var fontSize: Double
    }
}

extension DebugAutomation {
    func currentWorkspace() throws -> Workspace {
        guard let server = model.selectedServer, let session = model.session(for: server.id) else {
            throw AutomationError.failed("no active session")
        }
        return router.workspaces.workspace(for: session, serverURL: server.url)
    }

    func composer(_ workspace: Workspace, thread: Bool) throws -> ComposerState {
        if thread {
            guard let rootId = workspace.threadRootId, let root = workspace.session.posts[rootId] else { throw AutomationError.failed("no open thread") }
            return workspace.composer(for: ComposerTarget(channelId: root.channelId, rootId: rootId))
        }
        guard let channelId = workspace.session.currentChannelId else { throw AutomationError.failed("no channel") }
        return workspace.composer(for: ComposerTarget(channelId: channelId))
    }

    func post(_ workspace: Workspace, fromEnd index: Int) throws -> Post {
        guard let channelId = workspace.session.currentChannelId else { throw AutomationError.failed("no channel") }
        let posts = workspace.session.timelinePosts(channelId: channelId).filter { !$0.isDeleted && !$0.isSystemMessage }
        guard posts.indices.contains(posts.count - 1 - index) else { throw AutomationError.failed("no post at index \(index)") }
        return posts[posts.count - 1 - index]
    }

    func performInteraction(_ command: DebugCommand) async throws -> String {
        let workspace = try currentWorkspace()
        let session = workspace.session
        switch command {
        case .send(let text, let thread):
            let state = try composer(workspace, thread: thread)
            state.replaceText(text)
            guard let task = state.submit() else { throw AutomationError.failed("cannot send") }
            await task.value
            return session.lastError.map { "error: \($0)" } ?? ""
        case .type(let text, let thread):
            let state = try composer(workspace, thread: thread)
            state.replaceText(text)
            state.requestFocus()
            if !text.isEmpty { session.userTyping(channelId: state.target.channelId, parentId: state.target.rootId) }
            return ""
        case .key(let name, let modifiers, let thread):
            let state = try composer(workspace, thread: thread)
            let key: ComposerKey = ["enter": .enter, "up": .up, "down": .down, "tab": .tab, "escape": .escape][name] ?? .enter
            let command = ComposerKeyRouter.command(for: key, modifiers: Self.modifiers(modifiers), context: state.keyContext)
            if command == .insertNewline { state.insert("\n") }
            let handled = state.perform(command)
            if command == .send { try? await Task.sleep(for: .milliseconds(300)) }
            return "\(command) handled=\(handled)"
        case .openThread(let index, let postId):
            let rootId = try postId ?? post(workspace, fromEnd: index).threadId
            await workspace.openThread(rootId: rootId)
            return rootId
        case .closePane:
            workspace.closeRightPane()
            return ""
        case .react(let index, let emoji):
            let target = try post(workspace, fromEnd: index)
            await workspace.toggleReaction(postId: target.id, emojiName: emoji)
            return target.id
        case .editLast(let text):
            let state = try composer(workspace, thread: false)
            guard state.editLastPost() else { throw AutomationError.failed("no own post") }
            let postId = state.editingPostId ?? ""
            state.replaceText(text)
            await state.send()
            return postId
        case .deleteLast:
            guard let target = try composer(workspace, thread: false).lastOwnPost() else { throw AutomationError.failed("no own post") }
            workspace.requestDelete(target)
            await workspace.confirmDelete()
            return target.id
        case .scroll(let target):
            switch target {
            case "top": workspace.requestScroll(.top)
            case "bottom": workspace.requestScroll(.bottom)
            default: workspace.requestScroll(.post(target))
            }
            return ""
        case .quickSwitch(let query, let choose, let close):
            if close {
                workspace.showQuickSwitcher = false
                return ""
            }
            workspace.openQuickSwitcher(query: query)
            guard choose else { return "" }
            guard let first = QuickSwitcher.results(workspace.quickSwitchItems(), query: query).first else { throw AutomationError.failed("no match") }
            workspace.showQuickSwitcher = false
            await workspace.select(channelId: first.channelId)
            return first.title
        case .search(let terms):
            workspace.searchQuery = terms
            await workspace.search()
            return "\(workspace.searchResults.count)"
        case .jump(let index):
            guard workspace.searchResults.indices.contains(index) else { throw AutomationError.failed("no result \(index)") }
            await workspace.jump(to: workspace.searchResults[index])
            return workspace.searchResults[index].id
        case .command(let name, let number):
            return try await runCommand(name, number: number, workspace: workspace)
        case .upload(let path, let thread):
            let state = try composer(workspace, thread: thread)
            state.attach(fileURLs: [URL(fileURLWithPath: path)])
            return ""
        case .join(let name):
            let channels = await session.browsePublicChannels()
            guard let channel = channels.first(where: { $0.name == name || $0.displayName == name }) else { throw AutomationError.failed("no channel \(name)") }
            await session.join(channel: channel)
            return channel.id
        case .leave:
            guard let channelId = session.currentChannelId else { throw AutomationError.failed("no channel") }
            await session.leave(channelId: channelId)
            return channelId
        case .favorite(let on):
            guard let channelId = session.currentChannelId else { throw AutomationError.failed("no channel") }
            await session.setFavorite(channelId: channelId, favorite: on)
            return ""
        case .collapse(let title, let collapsed):
            guard let section = session.sidebar.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) else { throw AutomationError.failed("no category \(title)") }
            await session.setCategoryCollapsed(section.id, collapsed: collapsed)
            return section.id
        case .link(let url):
            await workspace.handle(link: url)
            return ""
        case .follow(let on, let postId):
            guard let rootId = postId ?? workspace.threadRootId else { throw AutomationError.failed("no thread") }
            await workspace.setFollowing(threadId: rootId, on)
            return "\(session.isFollowing(threadId: rootId))"
        case .setStatus(let status):
            await session.setStatus(status)
            return session.statuses[session.myId]?.rawValue ?? ""
        case .mute(let on):
            let channelId = try currentChannelId(session)
            guard await session.setMuted(channelId: channelId, on) else {
                throw AutomationError.failed(session.lastError ?? "could not change mute state")
            }
            return "\(session.isMuted(channelId: channelId))"
        case .notifyPrefs(let mute, let desktop, let threads, let ignore):
            let channelId = try currentChannelId(session)
            var settings = session.notifySettings(channelId: channelId)
            if let mute { settings.muted = mute }
            if let desktop { settings.desktop = desktop }
            if let threads { settings.desktopThreads = threads ? .all : .mention }
            if let ignore { settings.ignoreChannelMentions = ignore ? .on : .off }
            guard await session.applyNotifySettings(settings, channelId: channelId) else {
                throw AutomationError.failed(session.lastError ?? "could not save notification preferences")
            }
            return Self.describe(session.notifySettings(channelId: channelId))
        case .teamMute(let name, let on):
            let team = try team(named: name, in: session)
            session.setMuted(teamId: team.id, on)
            return session.teamLayout.muted.joined(separator: ",")
        case .acknowledge(let index, let postId):
            let target = try postId ?? post(workspace, fromEnd: index).id
            await workspace.toggleAcknowledgement(postId: target)
            return "\(session.posts[target]?.acknowledgements.count ?? 0)"
        case .priority(let priority):
            let state = try composer(workspace, thread: false)
            guard state.supportsPriority else { throw AutomationError.failed("message priority disabled") }
            state.apply(priority: priority)
            return "\(state.priority.priority.rawValue):\(state.priority.requestedAck):\(state.priority.persistentNotifications)"
        case .burnOnRead(let on):
            let state = try composer(workspace, thread: false)
            guard !on || state.supportsBurnOnRead else { throw AutomationError.failed("burn on read disabled") }
            state.setBurnOnRead(on)
            return "\(state.burnOnRead)"
        case .reveal(let index, let postId):
            let target = try postId ?? post(workspace, fromEnd: index).id
            await workspace.revealBurnOnRead(postId: target)
            return session.posts[target].map { "\($0.isBurnOnReadRevealed(by: session.myId))" } ?? "gone"
        case .burn(let index, let postId):
            let target = try postId ?? post(workspace, fromEnd: index).id
            guard let post = session.posts[target] else { throw AutomationError.failed("no post \(target)") }
            workspace.pendingBurn = post
            await workspace.confirmBurn()
            return target
        case .teamFavorite(let name, let on):
            let team = try team(named: name, in: session)
            session.setFavorite(teamId: team.id, favorite: on)
            return session.orderedTeams.map(\.name).joined(separator: ",")
        case .teamMove(let name, let target):
            let team = try team(named: name, in: session)
            switch target {
            case .team(let targetName): session.moveTeam(team.id, onto: .team(try self.team(named: targetName, in: session).id))
            case .endOfFavorites: session.moveTeam(team.id, onto: .endOfFavorites)
            case .endOfOthers: session.moveTeam(team.id, onto: .endOfOthers)
            }
            return session.orderedTeams.map(\.name).joined(separator: ",")
        case .channelMove, .categoryMove, .categorySort:
            return try await performSidebarOrder(command, session: session)
        case .toast(let action):
            return try performToast(action, workspace: workspace)
        case .members, .membersSearch, .membersMore, .memberMessage, .profile, .profileMessage:
            return try await performProfile(command, workspace: workspace)
        case .channelFiles, .channelFilesFilter, .channelFilesSearch, .channelFilesMore, .channelFile, .quickLookClose:
            return try await performChannelFiles(command, workspace: workspace)
        default:
            throw AutomationError.invalidCommand
        }
    }

    func performToast(_ action: DebugCommand.ToastAction, workspace: Workspace) throws -> String {
        let model = workspace.channelToast
        guard model.channelId != nil, model.channelId == workspace.session.currentChannelId else { throw AutomationError.failed("no toast") }
        switch action {
        case .jump:
            guard model.jump() else { throw AutomationError.failed("no toast") }
        case .dismiss:
            guard model.dismiss() else { throw AutomationError.failed("no toast") }
        case .escape:
            model.escape()
        }
        return model.visible?.kind.rawValue ?? "none"
    }

    static func toastSummary(_ workspace: Workspace) -> AutomationUIState.ToastSummary? {
        let model = workspace.channelToast
        guard model.channelId == workspace.session.currentChannelId, let toast = model.visible else { return nil }
        return AutomationUIState.ToastSummary(
            kind: toast.kind.rawValue,
            message: ChannelToastText.message(for: toast, width: model.width, now: workspace.now(), calendar: workspace.calendar),
            action: toast.showActions && (toast.kind == .scrollToBottom || model.width.showsActionTitle) ? toast.actionTitle : nil,
            showActions: toast.showActions,
            count: toast.count,
            since: toast.since
        )
    }

    func team(named name: String, in session: ServerSession) throws -> Team {
        guard let team = session.team(named: name) else { throw AutomationError.failed("no team \(name)") }
        return team
    }

    func currentChannelId(_ session: ServerSession) throws -> String {
        guard let channelId = session.currentChannelId else { throw AutomationError.failed("no channel") }
        return channelId
    }

    static func describe(_ settings: ChannelNotifySettings) -> String {
        [
            "muted=\(settings.muted)",
            "desktop=\(settings.desktop.rawValue)",
            "threads=\(settings.desktopThreads.rawValue)",
            "ignore=\(settings.ignoreChannelMentions.rawValue)",
        ].joined(separator: " ")
    }

    func runCommand(_ name: String, number: Int?, workspace: Workspace) async throws -> String {
        switch name {
        case "focus-search": router.focusSearch()
        case "focus-composer": router.focusComposer()
        case "quick-switcher": router.focusQuickSwitcher()
        case "toggle-sidebar": router.toggleSidebar()
        case "toggle-pane": router.toggleThreadPane()
        case "zoom-in": router.zoomIn()
        case "zoom-out": router.zoomOut()
        case "zoom-reset": router.resetZoom()
        case "next-server": await router.selectNextServer()
        case "previous-server": await router.selectPreviousServer()
        case "server": await router.selectServer(number: number ?? 1)
        case "next-channel": await workspace.navigate(offset: 1)
        case "previous-channel": await workspace.navigate(offset: -1)
        case "next-unread": await workspace.navigateUnread(forward: true)
        case "browse": workspace.showBrowseChannels = true
        case "direct-messages": workspace.showDirectMessages = true
        case "close-sheets":
            workspace.showBrowseChannels = false
            workspace.showDirectMessages = false
            workspace.previewFile = nil
        case "preview-last-image":
            guard let channelId = workspace.session.currentChannelId,
                  let file = workspace.session.timelinePosts(channelId: channelId).reversed().lazy.flatMap(\.metadata.files).first(where: \.isImage)
            else { throw AutomationError.failed("no image") }
            workspace.previewFile = file
        default:
            throw AutomationError.failed("unknown command \(name)")
        }
        return ""
    }

    static func modifiers(_ raw: String) -> ComposerKeyModifiers {
        var result: ComposerKeyModifiers = []
        for part in raw.lowercased().split(separator: ",") {
            switch part {
            case "shift": result.insert(.shift)
            case "option", "alt": result.insert(.option)
            case "command", "cmd": result.insert(.command)
            case "control", "ctrl": result.insert(.control)
            default: break
            }
        }
        return result
    }

    func uiState() -> AutomationUIState? {
        guard let workspace = try? currentWorkspace() else { return nil }
        let session = workspace.session
        let channelId = session.currentChannelId ?? ""
        let timeline = session.timelines[channelId] ?? ChannelTimeline()
        let rows = session.sidebar.flatMap(\.channelIds).compactMap { id in session.channels[id].map { (id, $0) } }
        var mentions: [String: Int] = [:]
        var unread: [String] = []
        var muted: [String] = []
        for (id, channel) in rows {
            let value = session.unread(channelId: id)
            if value.mentions > 0 { mentions[session.displayName(channel: channel)] = value.mentions }
            if value.unread { unread.append(session.displayName(channel: channel)) }
            if session.isMuted(channelId: id) { muted.append(session.displayName(channel: channel)) }
        }
        var sheets: [String] = []
        if workspace.showBrowseChannels { sheets.append("browse") }
        if workspace.showDirectMessages { sheets.append("direct-messages") }
        if workspace.previewFile != nil { sheets.append("image-preview") }
        if workspace.pendingDeletion != nil { sheets.append("delete-confirmation") }
        if workspace.notificationPreferences != nil { sheets.append("notification-preferences") }
        if workspace.pendingBurn != nil { sheets.append("burn-confirmation") }
        let timelinePosts = session.timelinePosts(channelId: channelId)
        let readStates = session.readStates(channelId: channelId)
        let readIndicators = ReadStatusPlacement.postIds(posts: timelinePosts, states: readStates, myId: session.myId)
        let threadComposer = workspace.threadRootId.flatMap { rootId in
            session.posts[rootId].map { workspace.composer(for: ComposerTarget(channelId: $0.channelId, rootId: rootId)) }
        }
        return AutomationUIState(
            windowTitle: host?.mainWindow?.title ?? "",
            firstResponder: Self.describeResponder(host?.mainWindow?.firstResponder),
            rightPane: workspace.rightPane.map { pane in
                switch pane {
                case .thread(let id): return "thread:\(id)"
                case .search: return "search"
                case .members: return "members"
                case .channelFiles(let id): return "channel-files:\(id)"
                }
            },
            threadPosts: workspace.threadRootId.map { session.threadPosts(rootId: $0).map { Self.summary($0, session: session) } } ?? [],
            quickSwitcher: workspace.showQuickSwitcher,
            quickSwitcherResults: workspace.showQuickSwitcher ? QuickSwitcher.results(workspace.quickSwitchItems(), query: workspace.quickSwitcherQuery).prefix(8).map(\.title) : [],
            searchResults: workspace.searchResults.prefix(20).map { "\($0.id): \($0.message.prefix(60))" },
            highlightedPostId: workspace.highlightedPostId,
            scroll: workspace.scrollReport,
            timelineCount: timeline.postIds.count,
            timelineUniqueCount: Set(timeline.postIds).count,
            hasMoreOlder: timeline.hasMoreOlder,
            timelineLoading: timeline.isLoading,
            recentPosts: timelinePosts.suffix(12).map { Self.summary($0, session: session, readStates: readStates, readIndicators: readIndicators) },
            composer: channelId.isEmpty ? nil : Self.summary(workspace.composer(for: ComposerTarget(channelId: channelId))),
            threadComposer: threadComposer.map(Self.summary),
            typing: session.typingUsers(channelId: channelId),
            unreadChannels: unread,
            mentionChannels: mentions,
            mutedChannels: muted,
            favorites: session.sidebar.first { $0.type == .favorites }?.channelIds.compactMap { session.channels[$0].map(session.displayName(channel:)) } ?? [],
            collapsedCategories: session.sidebar.filter(\.collapsed).map(\.title),
            sheets: sheets,
            error: workspace.visibleError,
            workspaces: router.workspaces.count,
            cachedSessionPosts: session.posts.count,
            editors: Self.editors(in: host?.mainWindow?.contentView),
            collapsedThreads: session.collapsedThreads,
            myStatus: session.statuses[session.myId]?.rawValue,
            threadFollowing: workspace.threadFollowing,
            readInfo: AutomationUIState.ReadInfoFeatures(
                postPriority: session.postPriorityEnabled,
                acknowledgements: session.acknowledgementsEnabled,
                persistentNotifications: session.persistentNotificationsEnabled,
                burnOnRead: session.burnOnReadEnabled,
                licenseSku: session.license.skuShortName
            ),
            readStatus: Self.readStatusTracking(session: session, channelId: channelId),
            sidebar: Self.sidebarSummary(session),
            toast: Self.toastSummary(workspace),
            lastViewedAtOnOpen: timeline.lastViewedAtOnOpen,
            profile: Self.profileSummary(workspace),
            members: Self.membersSummary(workspace),
            channelFiles: Self.channelFilesSummary(workspace, quickLook: QuickLookPanel.shared.visibleURL)
        )
    }

    static func readStatusTracking(session: ServerSession, channelId: String) -> AutomationUIState.ReadStatusTracking {
        let total = session.channels[channelId].map { ReadStatus.total(of: $0, collapsedThreads: session.collapsedThreads) } ?? 0
        let members = session.tracksReadStatus(channelId: channelId) ? session.readCounts[channelId] ?? [] : []
        let unseen = members.map { member in
            (session.displayName(userId: member.userId), max(0, total - member.viewedCount(collapsedThreads: session.collapsedThreads)))
        }
        return AutomationUIState.ReadStatusTracking(
            enabled: session.readStatusEnabled,
            tracked: session.tracksReadStatus(channelId: channelId),
            polling: session.isPollingReadStatus,
            total: total,
            unseenByMember: Dictionary(unseen, uniquingKeysWith: { a, _ in a })
        )
    }

    static func describe(_ state: PostReadState?) -> String? {
        switch state {
        case .sent: return "sent"
        case .seen: return "seen"
        case .partiallySeen(_, let total): return "partially-seen/\(total)"
        case nil: return nil
        }
    }

    static func seenBy(_ state: PostReadState?, session: ServerSession) -> [String] {
        switch state {
        case .partiallySeen(let ids, _): return ids.map { session.displayName(userId: $0) }
        case .seen: return session.readCounts[session.currentChannelId ?? ""]?.map { session.displayName(userId: $0.userId) } ?? []
        default: return []
        }
    }

    static func editors(in view: NSView?) -> [AutomationUIState.Editor] {
        guard let view else { return [] }
        if let editor = view as? ComposerNSTextView {
            return [AutomationUIState.Editor(spellChecking: editor.isContinuousSpellCheckingEnabled, fontSize: Double(editor.font?.pointSize ?? 0))]
        }
        return view.subviews.flatMap { editors(in: $0) }
    }

    static func summary(
        _ post: Post,
        session: ServerSession,
        readStates: [String: PostReadState] = [:],
        readIndicators: Set<String> = []
    ) -> AutomationUIState.PostSummary {
        AutomationUIState.PostSummary(
            id: post.id,
            user: session.displayName(for: post),
            message: post.isDeleted ? "(deleted)" : String(post.message.prefix(80)),
            rootId: post.rootId,
            reactions: post.reactionSummary.map { "\($0.emojiName):\($0.count)" },
            reactedBy: Dictionary(post.reactionSummary.map { ($0.emojiName, $0.userIds.map(session.displayName(userId:))) }, uniquingKeysWith: { first, _ in first }),
            files: post.metadata.files.count,
            edited: post.isEdited,
            replyCount: post.replyCount,
            following: post.isReply ? nil : session.isFollowing(threadId: post.id),
            status: session.statuses[post.userId]?.rawValue,
            priority: post.priorityLevel.isLabelled ? post.priorityLevel.rawValue : nil,
            requestedAck: post.requestsAcknowledgement,
            acknowledgedBy: post.acknowledgements.map { session.displayName(userId: $0.userId) },
            burnOnRead: burnOnReadSummary(post, session: session),
            readStatus: describe(readStates[post.id]),
            seenBy: seenBy(readStates[post.id], session: session),
            readIndicator: readIndicators.contains(post.id)
        )
    }

    static func burnOnReadSummary(_ post: Post, session: ServerSession) -> AutomationUIState.BurnOnReadSummary? {
        guard post.isBurnOnRead else { return nil }
        return AutomationUIState.BurnOnReadSummary(
            isSender: post.userId == session.myId,
            revealed: post.isBurnOnReadRevealed(by: session.myId),
            expireAt: post.burnOnReadExpireAt,
            readBy: post.burnOnReadRevealedBy.count,
            recipients: session.burnOnReadReceipt(postId: post.id)?.totalRecipients
        )
    }

    static func summary(_ composer: ComposerState) -> AutomationUIState.Composer {
        AutomationUIState.Composer(
            text: composer.text,
            editingPostId: composer.editingPostId,
            suggestions: composer.suggestions.map(\.title),
            selectedSuggestion: composer.selectedIndex,
            uploads: composer.uploads.map { upload in
                switch upload.state {
                case .uploading: return "\(upload.filename):uploading"
                case .uploaded: return "\(upload.filename):uploaded"
                case .failed: return "\(upload.filename):failed"
                }
            },
            height: Double(composer.editorHeight),
            priority: composer.priority.priority.rawValue,
            requestedAck: composer.priority.requestedAck,
            persistentNotifications: composer.priority.persistentNotifications,
            burnOnRead: composer.burnOnRead
        )
    }

    static func describeResponder(_ responder: NSResponder?) -> String? {
        guard let responder else { return nil }
        if responder is ComposerNSTextView { return "composer" }
        if let text = responder as? NSTextView, text.isFieldEditor {
            let field = text.delegate as? NSTextField
            return "field:\(field?.placeholderString ?? "")"
        }
        return String(describing: type(of: responder))
    }
}
