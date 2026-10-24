import Foundation
import Observation

public enum ConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case reconnecting
    case unauthorized
    case failed(String)
}

extension Duration {
    var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}

public struct ChannelTimeline: Equatable, Sendable {
    public var postIds: [String] = []
    public var hasMoreOlder = true
    public var isLoading = false
    public var loaded = false
    public var lastViewedAtOnOpen: Int64 = 0

    public init() {}
}

public struct ThreadState: Equatable, Sendable {
    public var rootId: String
    public var postIds: [String] = []
    public var isLoading = false

    public init(rootId: String) {
        self.rootId = rootId
    }
}

@MainActor
@Observable
public final class ServerSession {
    public let serverId: UUID
    public internal(set) var client: APIClient
    public var connection: ConnectionState = .idle
    public internal(set) var me: User?
    public internal(set) var config = ClientConfig(values: [:])
    public internal(set) var license = ClientLicense(values: [:])
    public internal(set) var teams: [Team] = []
    public internal(set) var teamUnreads: [String: TeamUnread] = [:]
    public internal(set) var currentTeamId: String?
    public internal(set) var currentChannelId: String?
    public internal(set) var channels: [String: Channel] = [:]
    public internal(set) var members: [String: ChannelMember] = [:]
    public internal(set) var categories: [String: [ChannelCategory]] = [:]
    public internal(set) var users: [String: User] = [:]
    public internal(set) var statuses: [String: UserStatusValue] = [:]
    public internal(set) var preferences: [Preference] = []
    public internal(set) var posts: [String: Post] = [:]
    public internal(set) var timelines: [String: ChannelTimeline] = [:]
    public internal(set) var threads: [String: ThreadState] = [:]
    public internal(set) var typing: [String: [String: Date]] = [:]
    public internal(set) var customEmojis: [String: CustomEmoji] = [:]
    public internal(set) var lastError: String?
    public internal(set) var pendingPostIds: Set<String> = []
    public internal(set) var collapsedThreads = false
    public internal(set) var channelMemberCounts: [String: Int] = [:]
    public internal(set) var revealingPostIds: Set<String> = []
    public var teamLayout = TeamLayout() {
        didSet { if teamLayout != oldValue { onTeamLayoutChange?(teamLayout) } }
    }

    @ObservationIgnored public var onNotification: ((MentionNotification) -> Void)?
    @ObservationIgnored public var onUnauthorized: (() -> Void)?
    @ObservationIgnored public var onSelectionChange: ((String?, String?) -> Void)?
    @ObservationIgnored public var onTeamLayoutChange: ((TeamLayout) -> Void)?
    @ObservationIgnored public var isAppActive: () -> Bool = { true }
    @ObservationIgnored public var now: () -> Date = Date.init
    @ObservationIgnored public var typingTimeout: Duration = .seconds(6)
    @ObservationIgnored public var presenceInterval: Duration = .seconds(60)
    @ObservationIgnored public var presenceRecentPostLimit = 100
    @ObservationIgnored public var presenceBatchLimit = 200
    @ObservationIgnored var presenceTask: Task<Void, Never>?
    @ObservationIgnored var burnOnReadTask: Task<Void, Never>?
    @ObservationIgnored var requestedStatsChannelIds = Set<String>()
    @ObservationIgnored var requestedStatusIds = Set<String>()
    @ObservationIgnored let realtimeFactory: (URL, String) -> RealtimeClient
    @ObservationIgnored var realtime: RealtimeClient?
    @ObservationIgnored var realtimeTask: Task<Void, Never>?
    @ObservationIgnored var pendingUserIds = Set<String>()
    @ObservationIgnored var requestedUserIds = Set<String>()
    @ObservationIgnored var lastTypingSent: [String: Date] = [:]
    @ObservationIgnored var loadedTeams = Set<String>()
    @ObservationIgnored var lastPendingMillis: Int64 = 0
    @ObservationIgnored var deletedPostIds = Set<String>()
    @ObservationIgnored var manuallyUnread = Set<String>()
    @ObservationIgnored let pageSize: Int

    public init(
        serverId: UUID,
        client: APIClient,
        pageSize: Int = 60,
        realtimeFactory: ((URL, String) -> RealtimeClient)? = nil
    ) {
        self.serverId = serverId
        self.client = client
        self.pageSize = pageSize
        self.realtimeFactory = realtimeFactory ?? { url, token in RealtimeClient(url: url, token: token) }
    }

    public var myId: String { me?.id ?? "" }

    public var nameDisplay: NameDisplaySetting {
        let value = preferences.first { $0.category == PreferenceCategory.displaySettings && $0.name == PreferenceName.nameFormat }?.value
        return NameDisplaySetting(preference: value ?? config.teammateNameDisplay)
    }

    public var currentTeam: Team? { teams.first { $0.id == currentTeamId } }

    public var teamSections: TeamSections { teamLayout.sections(teams) }

    public var orderedTeams: [Team] { teamLayout.ordered(teams) }

    public func isFavorite(teamId: String) -> Bool { teamLayout.isFavorite(teamId) }

    public func moveTeam(_ teamId: String, to targetId: String) {
        teamLayout.move(teamId, to: targetId, in: teams)
    }

    public func moveTeamToEnd(_ teamId: String, favorite: Bool) {
        teamLayout.moveToEnd(teamId, favorite: favorite, in: teams)
    }

    public func setFavorite(teamId: String, favorite: Bool) {
        teamLayout.setFavorite(teamId, favorite, in: teams)
    }

    public var currentChannel: Channel? { currentChannelId.flatMap { channels[$0] } }

    public func displayName(userId: String) -> String {
        guard let user = users[userId] else { return userId == myId ? (me?.username ?? "") : "Someone" }
        return user.displayName(nameDisplay)
    }

    public func displayName(for post: Post) -> String {
        post.overrideUsername ?? displayName(userId: post.userId)
    }

    public func displayName(channel: Channel) -> String {
        switch channel.type {
        case .direct:
            guard let partner = channel.directPartnerId(me: myId) else { return channel.displayName }
            let name = displayName(userId: partner)
            return partner == myId ? "\(name) (you)" : name
        default:
            return channel.displayName.isEmpty ? channel.name : channel.displayName
        }
    }

    public func unread(channelId: String) -> ChannelUnread {
        guard let channel = channels[channelId] else { return .none }
        return SidebarBuilder.unread(channel: channel, member: members[channelId], collapsedThreads: collapsedThreads)
    }

    public func teamUnread(teamId: String) -> ChannelUnread {
        if loadedTeams.contains(teamId) {
            var result = ChannelUnread()
            for (id, channel) in channels where channel.teamId == teamId {
                let unread = SidebarBuilder.unread(channel: channel, member: members[id], collapsedThreads: collapsedThreads)
                result.unread = result.unread || unread.unread
                result.mentions += unread.mentions
            }
            return result
        }
        guard let value = teamUnreads[teamId] else { return .none }
        return ChannelUnread(unread: (collapsedThreads ? value.msgCountRoot : value.msgCount) > 0, mentions: value.mentionCount)
    }

    public var directUnread: ChannelUnread {
        var result = ChannelUnread()
        for (id, channel) in channels where channel.type.isDirectOrGroup {
            let unread = SidebarBuilder.unread(channel: channel, member: members[id], collapsedThreads: collapsedThreads)
            result.unread = result.unread || unread.unread
            result.mentions += unread.mentions
        }
        return result
    }

    public var totalUnread: ChannelUnread {
        var result = directUnread
        for team in teams {
            let unread = teamUnread(teamId: team.id)
            result.unread = result.unread || unread.unread
            result.mentions += unread.mentions
        }
        return result
    }

    public var hiddenDirectChannelIds: Set<String> {
        var hidden = Set<String>()
        for preference in preferences where preference.value == "false" {
            if preference.category == PreferenceCategory.directChannelShow {
                for (id, channel) in channels where channel.type == .direct && channel.directPartnerId(me: myId) == preference.name {
                    hidden.insert(id)
                }
            } else if preference.category == PreferenceCategory.groupChannelShow {
                hidden.insert(preference.name)
            }
        }
        return hidden
    }

    public var sidebar: [SidebarSection] {
        guard let teamId = currentTeamId else { return [] }
        let teamChannels = channels.filter { $0.value.teamId == teamId || $0.value.type.isDirectOrGroup }
        let teamMembers = members.filter { teamChannels[$0.key] != nil }
        return SidebarBuilder.sections(
            categories: categories[teamId] ?? [],
            channels: teamChannels,
            members: teamMembers,
            hiddenDirect: hiddenDirectChannelIds,
            displayName: { [unowned self] in self.displayName(channel: $0) },
            currentChannelId: currentChannelId,
            directMessageLimit: SidebarBuilder.directMessageLimit(preference: preferenceValue(category: PreferenceCategory.sidebarSettings, name: PreferenceName.limitVisibleDirectMessages)),
            collapsedThreads: collapsedThreads
        )
    }

    public func preferenceValue(category: String, name: String) -> String? {
        preferences.last { $0.category == category && $0.name == name }?.value
    }

    public func isPending(postId: String) -> Bool { pendingPostIds.contains(postId) }

    public func timelinePosts(channelId: String) -> [Post] {
        let list = (timelines[channelId]?.postIds ?? []).compactMap { posts[$0] }
        return collapsedThreads ? list.filter { !$0.isReply } : list
    }

    func belongsInTimeline(_ post: Post) -> Bool {
        !collapsedThreads || !post.isReply
    }

    public func setCollapsedThreads(_ enabled: Bool) async {
        guard collapsedThreads != enabled else { return }
        collapsedThreads = enabled
        let current = currentChannelId
        for id in timelines.keys where id != current { timelines[id] = nil }
        guard let current, let existing = timelines[current] else { return }
        var reset = ChannelTimeline()
        reset.lastViewedAtOnOpen = existing.lastViewedAtOnOpen
        timelines[current] = reset
        await loadLatest(channelId: current)
    }

    public func threadPosts(rootId: String) -> [Post] {
        (threads[rootId]?.postIds ?? []).compactMap { posts[$0] }
    }

    public func typingUsers(channelId: String, parentId: String = "") -> [String] {
        let cutoff = now().addingTimeInterval(-typingTimeout.seconds)
        let key = typingKey(channelId: channelId, parentId: parentId)
        return (typing[key] ?? [:]).filter { $0.value > cutoff && $0.key != myId }.keys.sorted().map { displayName(userId: $0) }
    }

    func typingKey(channelId: String, parentId: String) -> String {
        parentId.isEmpty ? channelId : "\(channelId):\(parentId)"
    }

    public func isFavorite(channelId: String) -> Bool {
        guard let teamId = currentTeamId else { return false }
        return categories[teamId]?.first { $0.type == .favorites }?.channelIds.contains(channelId) ?? false
    }

    public func start() async {
        guard let token = client.token, !token.isEmpty else {
            connection = .unauthorized
            onUnauthorized?()
            return
        }
        switch connection {
        case .connecting, .connected, .reconnecting: return
        default: break
        }
        connection = .connecting
        do {
            try await loadInitial()
            guard connection == .connecting else { return }
            connection = .connected
            startRealtime(token: token)
            startPresence()
        } catch {
            guard connection == .connecting else { return }
            if APIError.isCancellation(error) {
                connection = .idle
                return
            }
            let apiError = APIError.wrap(error)
            if apiError.isUnauthorized {
                handleUnauthorized()
            } else {
                connection = .failed(apiError.localizedDescription)
                lastError = apiError.localizedDescription
            }
        }
    }

    public func stop() {
        stopRealtime()
        connection = .idle
    }

    func stopRealtime() {
        stopPresence()
        stopBurnOnReadExpiry()
        realtimeTask?.cancel()
        realtimeTask = nil
        if let realtime { Task { await realtime.stop() } }
        realtime = nil
    }

    public func updateToken(_ token: String?) {
        client.token = token
    }

    func report(_ error: Error, silently: Bool = false) {
        if APIError.isCancellation(error) { return }
        let apiError = APIError.wrap(error)
        if apiError.isUnauthorized {
            handleUnauthorized()
        } else if !silently {
            lastError = apiError.localizedDescription
        }
    }

    func handleUnauthorized() {
        guard connection != .unauthorized else { return }
        connection = .unauthorized
        stopRealtime()
        onUnauthorized?()
    }

    func quietly<T>(_ operation: () async throws -> T) async -> T? {
        do {
            return try await operation()
        } catch {
            report(error, silently: true)
            return nil
        }
    }

    nonisolated static func sortedTeams(_ list: [Team]) -> [Team] {
        list.filter { $0.deleteAt == 0 }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func loadInitial() async throws {
        async let meRequest = client.me()
        async let configRequest = client.clientConfig()
        async let teamsRequest = client.myTeams()
        async let unreadRequest = client.myTeamUnreads()
        async let preferencesRequest = client.preferences()
        let (user, clientConfig, myTeams, unreads, prefs) = try await (meRequest, configRequest, teamsRequest, unreadRequest, preferencesRequest)
        me = user
        users[user.id] = user
        config = clientConfig
        teams = Self.sortedTeams(myTeams)
        teamUnreads = Dictionary(unreads.map { ($0.teamId, $0) }, uniquingKeysWith: { a, _ in a })
        preferences = prefs
        loadedTeams.removeAll()
        Task { await self.loadLicense() }
        if let teamId = currentTeamId {
            if teams.contains(where: { $0.id == teamId }) {
                try await loadTeam(teamId)
            } else {
                currentTeamId = nil
                currentChannelId = nil
                if let first = orderedTeams.first { await selectTeam(first.id) }
            }
        }
        if let channelId = currentChannelId, timelines[channelId] != nil {
            await loadLatest(channelId: channelId)
        }
        Task { await self.loadCustomEmojis() }
    }

    public func selectTeam(_ teamId: String, channelId: String? = nil) async {
        guard teams.contains(where: { $0.id == teamId }) else { return }
        let previous = currentChannelId
        currentTeamId = teamId
        if !loadedTeams.contains(teamId) {
            do {
                try await loadTeam(teamId)
            } catch {
                report(error)
                return
            }
        }
        guard currentTeamId == teamId else { return }
        let requested = channelId.flatMap { id -> String? in
            guard let channel = channels[id], channel.teamId.isEmpty || channel.teamId == teamId else { return nil }
            return id
        }
        if let target = requested ?? defaultChannel(teamId: teamId) {
            await selectChannel(target, previous: previous)
        } else {
            currentChannelId = nil
            onSelectionChange?(currentTeamId, nil)
        }
    }

    func defaultChannel(teamId: String) -> String? {
        if let townSquare = channels.values.first(where: { $0.teamId == teamId && $0.name == "town-square" && members[$0.id] != nil }) {
            return townSquare.id
        }
        return sidebar.flatMap(\.channelIds).first
    }

    func loadTeam(_ teamId: String) async throws {
        async let channelsRequest = client.myChannels(teamId: teamId)
        async let membersRequest = client.myChannelMembers(teamId: teamId)
        async let categoriesRequest = client.myCategories(teamId: teamId)
        let (teamChannels, teamMembers, teamCategories) = try await (channelsRequest, membersRequest, categoriesRequest)
        let returned = Set(teamChannels.map(\.id))
        for (id, channel) in channels where !returned.contains(id) && (channel.teamId == teamId || channel.type.isDirectOrGroup) {
            members[id] = nil
        }
        for channel in teamChannels { channels[channel.id] = channel }
        for member in teamMembers { members[member.channelId] = member }
        categories[teamId] = teamCategories.sorted
        loadedTeams.insert(teamId)
        var needed: Set<String> = myId.isEmpty ? [] : [myId]
        for channel in teamChannels where channel.type == .direct {
            if let partner = channel.directPartnerId(me: myId) { needed.insert(partner) }
        }
        let ids = Array(needed)
        async let usersLoaded: Void = ensureUsers(ids)
        async let statusesLoaded: Void = refreshStatuses(ids)
        _ = await (usersLoaded, statusesLoaded)
    }

    public func selectChannel(_ channelId: String, previous: String? = nil) async {
        let previousId = previous ?? currentChannelId
        if let channel = channels[channelId], !channel.teamId.isEmpty, channel.teamId != currentTeamId {
            currentTeamId = channel.teamId
        }
        currentChannelId = channelId
        manuallyUnread.remove(channelId)
        onSelectionChange?(currentTeamId, channelId)
        var timeline = timelines[channelId] ?? ChannelTimeline()
        timeline.lastViewedAtOnOpen = members[channelId]?.lastViewedAt ?? 0
        timelines[channelId] = timeline
        if let teamId = currentTeamId, !loadedTeams.contains(teamId), teams.contains(where: { $0.id == teamId }) {
            do {
                try await loadTeam(teamId)
            } catch {
                report(error, silently: true)
            }
        }
        if timeline.loaded {
            await loadNewer(channelId: channelId)
        } else {
            await loadLatest(channelId: channelId)
        }
        guard currentChannelId == channelId else { return }
        let previousChannel = previousId == channelId ? "" : (previousId ?? "")
        await markViewed(channelId: channelId, previous: previousChannel)
    }

    public func markViewed(channelId: String, previous: String = "") async {
        guard channels[channelId] != nil else { return }
        manuallyUnread.remove(channelId)
        markLocallyViewed(channelId)
        do {
            try await client.viewChannel(channelId: channelId, previousChannelId: previous)
        } catch {
            report(error, silently: true)
        }
    }

    public func markUnread(postId: String) async {
        guard let post = posts[postId], !myId.isEmpty, !pendingPostIds.contains(postId) else { return }
        do {
            let unread = try await client.markPostUnread(userId: myId, postId: postId)
            manuallyUnread.insert(post.channelId)
            if var member = members[post.channelId] {
                member.msgCount = unread.msgCount
                member.msgCountRoot = unread.msgCountRoot
                member.mentionCount = unread.mentionCount
                member.mentionCountRoot = unread.mentionCountRoot
                member.urgentMentionCount = unread.urgentMentionCount
                member.lastViewedAt = unread.lastViewedAt
                members[post.channelId] = member
            }
            timelines[post.channelId]?.lastViewedAtOnOpen = unread.lastViewedAt
        } catch {
            report(error)
        }
    }

    func loadLatest(channelId: String) async {
        var timeline = timelines[channelId] ?? ChannelTimeline()
        guard !timeline.isLoading else { return }
        timeline.isLoading = true
        timelines[channelId] = timeline
        let result: Result<PostList, Error>
        do {
            result = .success(try await client.posts(channelId: channelId, page: .latest(perPage: pageSize), collapsedThreads: collapsedThreads))
        } catch {
            result = .failure(error)
        }
        guard var current = timelines[channelId] else { return }
        current.isLoading = false
        switch result {
        case .success(let list):
            ingest(list)
            let fetched = list.order.reversed().filter { id in posts[id].map(belongsInTimeline) ?? false }
            let fetchedIds = Set(fetched)
            let newestFetched = fetched.last.flatMap { posts[$0]?.createAt } ?? Int64.min
            let newer = current.postIds.filter { id in
                guard !fetchedIds.contains(id), let post = posts[id] else { return false }
                return post.createAt > newestFetched
            }
            current.postIds = fetched + newer
            current.hasMoreOlder = list.order.count >= pageSize
            current.loaded = true
        case .failure(let error):
            report(error)
        }
        timelines[channelId] = current
    }

    public func loadOlder(channelId: String) async {
        guard var timeline = timelines[channelId], timeline.loaded, timeline.hasMoreOlder, !timeline.isLoading,
              let oldest = timeline.postIds.first(where: { !pendingPostIds.contains($0) })
        else { return }
        timeline.isLoading = true
        timelines[channelId] = timeline
        let result: Result<PostList, Error>
        do {
            result = .success(try await client.posts(channelId: channelId, page: .before(postId: oldest, perPage: pageSize), collapsedThreads: collapsedThreads))
        } catch {
            result = .failure(error)
        }
        guard var current = timelines[channelId] else { return }
        current.isLoading = false
        switch result {
        case .success(let list):
            ingest(list)
            let existing = Set(current.postIds)
            let older = list.order.reversed().filter { id in !existing.contains(id) && (posts[id].map(belongsInTimeline) ?? false) }
            current.postIds.insert(contentsOf: older, at: 0)
            current.hasMoreOlder = list.order.count >= pageSize
        case .failure(let error):
            report(error)
        }
        timelines[channelId] = current
    }

    func syncedAt(channelId: String) -> Int64? {
        timelines[channelId]?.postIds
            .filter { !pendingPostIds.contains($0) }
            .compactMap { posts[$0] }
            .map { max($0.createAt, $0.updateAt, $0.editAt, $0.deleteAt) }
            .max()
    }

    func loadNewer(channelId: String) async {
        guard var timeline = timelines[channelId], timeline.loaded, let since = syncedAt(channelId: channelId), since > 0 else {
            await loadLatest(channelId: channelId)
            return
        }
        guard !timeline.isLoading else { return }
        timeline.isLoading = true
        timelines[channelId] = timeline
        let result: Result<PostList, Error>
        do {
            result = .success(try await client.posts(channelId: channelId, page: .since(since), collapsedThreads: collapsedThreads))
        } catch {
            result = .failure(error)
        }
        guard timelines[channelId] != nil else { return }
        timelines[channelId]?.isLoading = false
        switch result {
        case .success(let list):
            applyChanges(list)
        case .failure(let error):
            report(error)
        }
    }

    func applyChanges(_ list: PostList) {
        let changed = list.posts.values.sorted { $0.createAt == $1.createAt ? $0.id < $1.id : $0.createAt < $1.createAt }
        for post in changed where post.isDeleted { removePost(post.id, fallback: post) }
        let live = changed.filter { !$0.isDeleted }
        ingest(PostList(posts: Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })))
        for post in live { insertIntoTimeline(post) }
    }

    public func openThread(rootId: String) async {
        var state = threads[rootId] ?? ThreadState(rootId: rootId)
        state.isLoading = true
        threads[rootId] = state
        do {
            let list = try await client.postThread(postId: rootId, collapsedThreads: collapsedThreads)
            ingest(list)
            guard var current = threads[rootId] else { return }
            let fetched = list.posts.values.filter { $0.id == rootId || $0.rootId == rootId }.map(\.id)
            let ids = Set(fetched).union(current.postIds)
            current.postIds = ids.compactMap { posts[$0] }
                .sorted { $0.createAt == $1.createAt ? $0.id < $1.id : $0.createAt < $1.createAt }
                .map(\.id)
            current.isLoading = false
            threads[rootId] = current
        } catch {
            threads[rootId]?.isLoading = false
            report(error)
        }
    }

    public func closeThread(rootId: String) {
        threads[rootId] = nil
    }

    static func normalizedMessage(_ message: String) -> String {
        var text = Substring(message)
        while let last = text.last, last.isWhitespace { text.removeLast() }
        while let first = text.first, first.isNewline { text.removeFirst() }
        return String(text)
    }

    func nextPendingPostId() -> (id: String, millis: Int64) {
        let millis = max(now().mattermostMillis, lastPendingMillis + 1)
        lastPendingMillis = millis
        return ("\(myId):\(millis)", millis)
    }

    @discardableResult
    public func send(
        _ message: String,
        channelId: String,
        rootId: String = "",
        fileIds: [String] = [],
        priority: PostPriority? = nil,
        burnOnRead: Bool = false
    ) async -> Bool {
        let text = Self.normalizedMessage(message)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !fileIds.isEmpty else { return false }
        let sentPriority = effectivePriority(priority, rootId: rootId)
        let postType = burnOnRead && burnOnReadEnabled && rootId.isEmpty ? PostType.burnOnRead : ""
        let pending = nextPendingPostId()
        addPending(Post(
            id: pending.id,
            createAt: pending.millis,
            updateAt: pending.millis,
            userId: myId,
            channelId: channelId,
            rootId: rootId,
            message: text,
            type: postType,
            fileIds: fileIds,
            pendingPostId: pending.id,
            metadata: PostMetadata(priority: sentPriority)
        ))
        do {
            let post = try await client.createPost(
                channelId: channelId,
                message: text,
                rootId: rootId,
                fileIds: fileIds,
                pendingPostId: pending.id,
                priority: sentPriority,
                postType: postType
            )
            discardPending(pending.id)
            receive(post: post)
            if !rootId.isEmpty { markFollowing(threadId: rootId, true) }
            return true
        } catch {
            discardPending(pending.id)
            report(error)
            return false
        }
    }

    func addPending(_ post: Post) {
        pendingPostIds.insert(post.id)
        posts[post.id] = post
        insertIntoTimeline(post)
        if !post.rootId.isEmpty, var thread = threads[post.rootId] {
            thread.postIds.append(post.id)
            threads[post.rootId] = thread
        }
    }

    func discardPending(_ pendingId: String) {
        guard pendingPostIds.remove(pendingId) != nil, let pending = posts.removeValue(forKey: pendingId) else { return }
        timelines[pending.channelId]?.postIds.removeAll { $0 == pendingId }
        if !pending.rootId.isEmpty {
            threads[pending.rootId]?.postIds.removeAll { $0 == pendingId }
        }
    }

    @discardableResult
    public func edit(postId: String, message: String) async -> Bool {
        do {
            receive(post: try await client.patchPost(id: postId, message: message))
            return true
        } catch {
            report(error)
            return false
        }
    }

    public func delete(postId: String) async {
        do {
            try await client.deletePost(id: postId)
            removePost(postId)
        } catch {
            report(error)
        }
    }

    public func toggleReaction(postId: String, emojiName: String) async {
        guard let post = posts[postId], !pendingPostIds.contains(postId) else { return }
        let mine = post.metadata.reactions.contains { $0.userId == myId && $0.emojiName == emojiName }
        do {
            if mine {
                try await client.removeReaction(userId: myId, postId: postId, emojiName: emojiName)
                applyReaction(Reaction(userId: myId, postId: postId, emojiName: emojiName), added: false)
            } else {
                let reaction = try await client.addReaction(userId: myId, postId: postId, emojiName: emojiName)
                applyReaction(reaction, added: true)
            }
        } catch {
            report(error)
        }
    }

    public func setPinned(postId: String, pinned: Bool) async {
        do {
            try await client.pinPost(id: postId, pinned: pinned)
            posts[postId]?.isPinned = pinned
        } catch {
            report(error)
        }
    }

    public func upload(channelId: String, filename: String, data: Data, mimeType: String) async -> FileInfo? {
        do {
            return try await client.uploadFile(channelId: channelId, filename: filename, data: data, mimeType: mimeType)
        } catch {
            report(error)
            return nil
        }
    }

    public func search(_ terms: String) async -> [Post] {
        guard let teamId = currentTeamId, !terms.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        do {
            let results = try await client.searchPosts(teamId: teamId, terms: terms)
            for post in results.posts.values where posts[post.id] == nil { posts[post.id] = post }
            let found = results.orderedPosts
            await ensureUsers(found.map(\.userId))
            await ensureChannels(found.map(\.channelId))
            return found
        } catch {
            report(error)
            return []
        }
    }

    public func autocompleteUsers(_ prefix: String, channelId: String?) async -> [User] {
        guard let found = await quietly({ try await client.autocompleteUsers(name: prefix, teamId: currentTeamId, channelId: channelId) }) else { return [] }
        for user in found { users[user.id] = user }
        return found
    }

    public func autocompleteChannels(_ prefix: String) async -> [Channel] {
        guard let teamId = currentTeamId else { return [] }
        return await quietly { try await client.autocompleteChannels(teamId: teamId, name: prefix) } ?? []
    }

    public func browsePublicChannels() async -> [Channel] {
        guard let teamId = currentTeamId else { return [] }
        do {
            return try await client.publicChannels(teamId: teamId).filter { !$0.isArchived }
        } catch {
            report(error)
            return []
        }
    }

    public func join(channel: Channel) async {
        do {
            let member = try await client.joinChannel(channelId: channel.id, userId: myId)
            channels[channel.id] = channel
            members[channel.id] = member
            if let teamId = currentTeamId { _ = await quietly { try await refreshCategories(teamId: teamId) } }
            await selectChannel(channel.id)
        } catch {
            report(error)
        }
    }

    public func leave(channelId: String) async {
        do {
            try await client.leaveChannel(channelId: channelId, userId: myId)
            removeChannelMembership(channelId)
        } catch {
            report(error)
        }
    }

    public func openDirect(userId: String) async {
        do {
            let channel = try await client.createDirectChannel(userIds: [myId, userId])
            channels[channel.id] = channel
            if members[channel.id] == nil {
                members[channel.id] = await quietly { try await client.channelMember(channelId: channel.id) } ?? ChannelMember(channelId: channel.id, userId: myId)
            }
            await ensureUsers([userId])
            if preferences.contains(where: { $0.category == PreferenceCategory.directChannelShow && $0.name == userId && $0.value == "false" }) {
                await savePreference(category: PreferenceCategory.directChannelShow, name: userId, value: "true")
            }
            await selectChannel(channel.id)
        } catch {
            report(error)
        }
    }

    public func setFavorite(channelId: String, favorite: Bool) async {
        guard let teamId = currentTeamId, var list = categories[teamId],
              let favoritesIndex = list.firstIndex(where: { $0.type == .favorites })
        else { return }
        var changed: [ChannelCategory] = []
        if favorite {
            guard !list[favoritesIndex].channelIds.contains(channelId) else { return }
            for index in list.indices where list[index].channelIds.contains(channelId) {
                list[index].channelIds.removeAll { $0 == channelId }
                changed.append(list[index])
            }
            list[favoritesIndex].channelIds.insert(channelId, at: 0)
            changed.append(list[favoritesIndex])
        } else {
            guard list[favoritesIndex].channelIds.contains(channelId) else { return }
            list[favoritesIndex].channelIds.removeAll { $0 == channelId }
            changed.append(list[favoritesIndex])
            let targetType: CategoryType = channels[channelId]?.type.isDirectOrGroup == true ? .directMessages : .channels
            if let targetIndex = list.firstIndex(where: { $0.type == targetType }) {
                list[targetIndex].channelIds.insert(channelId, at: 0)
                changed.append(list[targetIndex])
            }
        }
        categories[teamId] = list
        var failed = false
        for category in changed where await quietly({ try await client.updateCategory(category) }) == nil {
            failed = true
        }
        if failed { _ = await quietly { try await refreshCategories(teamId: teamId) } }
    }

    public func setCategoryCollapsed(_ categoryId: String, collapsed: Bool) async {
        guard let teamId = currentTeamId, var list = categories[teamId],
              let index = list.firstIndex(where: { $0.id == categoryId })
        else { return }
        list[index].collapsed = collapsed
        categories[teamId] = list
        let category = list[index]
        _ = await quietly { try await client.updateCategory(category) }
    }

    public func savePreference(category: String, name: String, value: String) async {
        let preference = Preference(userId: myId, category: category, name: name, value: value)
        applyPreferences([preference])
        _ = await quietly { try await client.savePreferences(userId: myId, [preference]) }
    }

    public func userTyping(channelId: String, parentId: String = "") {
        let key = typingKey(channelId: channelId, parentId: parentId)
        if let last = lastTypingSent[key], now().timeIntervalSince(last) < 3 { return }
        lastTypingSent[key] = now()
        guard let realtime else { return }
        Task { await realtime.userTyping(channelId: channelId, parentId: parentId) }
    }

    public func setStatus(_ status: UserStatusValue) async {
        guard !myId.isEmpty else { return }
        do {
            try await client.setStatus(userId: myId, status: status)
            statuses[myId] = status
        } catch {
            report(error)
        }
    }

    public func clearError() {
        lastError = nil
    }

    public func ensureUsers(_ ids: [String]) async {
        let missing = Set(ids).subtracting(users.keys).subtracting(requestedUserIds).filter { !$0.isEmpty }
        guard !missing.isEmpty else { return }
        requestedUserIds.formUnion(missing)
        let sorted = missing.sorted()
        var index = 0
        while index < sorted.count {
            let batch = Array(sorted[index..<min(index + 100, sorted.count)])
            index += 100
            do {
                for user in try await client.users(ids: batch) { users[user.id] = user }
            } catch {
                requestedUserIds.subtract(batch)
                report(error, silently: true)
            }
        }
    }

    func ensureChannels(_ ids: [String]) async {
        for id in Set(ids) where channels[id] == nil && !id.isEmpty {
            if let channel = await quietly({ try await client.channel(id: id) }) { channels[id] = channel }
        }
    }

    public func refreshStatuses(_ ids: [String]) async {
        guard !ids.isEmpty, let found = await quietly({ try await client.statuses(userIds: ids) }) else { return }
        for status in found where statuses[status.userId] != status.status { statuses[status.userId] = status.status }
    }

    func refreshCategories(teamId: String) async throws {
        categories[teamId] = try await client.myCategories(teamId: teamId).sorted
    }

    func refreshTeamUnreads() async {
        guard let unreads = await quietly({ try await client.myTeamUnreads() }) else { return }
        teamUnreads = Dictionary(unreads.map { ($0.teamId, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func loadCustomEmojis() async {
        guard config.enableCustomEmoji else { return }
        var page = 0
        while page < 20 {
            guard let batch = await quietly({ try await client.customEmojis(page: page) }) else { return }
            for emoji in batch { customEmojis[emoji.name] = emoji }
            if batch.count < 200 { return }
            page += 1
        }
    }

    func store(_ post: Post) {
        guard let existing = posts[post.id] else {
            posts[post.id] = post
            return
        }
        if existing.updateAt > post.updateAt { return }
        posts[post.id] = post.mergingThreadSummary(from: existing).mergingReadInfo(from: existing)
    }

    func ingest(_ list: PostList) {
        var userIds = Set<String>()
        for post in list.posts.values where !deletedPostIds.contains(post.id) {
            store(post)
            userIds.insert(post.userId)
            userIds.formUnion(post.participantIds)
            for emoji in post.metadata.emojis { customEmojis[emoji.name] = emoji }
            for reaction in post.metadata.reactions { userIds.insert(reaction.userId) }
            for acknowledgement in post.metadata.acknowledgements { userIds.insert(acknowledgement.userId) }
            userIds.formUnion(post.metadata.recipients)
            if post.isBurnOnRead { trackBurnOnRead(posts[post.id] ?? post) }
        }
        let ids = userIds.filter { users[$0] == nil }
        if !ids.isEmpty { Task { await self.ensureUsers(Array(ids)) } }
        let authors = list.posts.values.filter { $0.overrideUsername == nil }.map(\.userId)
        if authors.contains(where: { statuses[$0] == nil }) { Task { await self.refreshMissingStatuses(authors) } }
    }

    func insertIntoTimeline(_ post: Post) {
        guard belongsInTimeline(post), var timeline = timelines[post.channelId], !timeline.postIds.contains(post.id) else { return }
        if timeline.loaded, timeline.hasMoreOlder, let first = timeline.postIds.first.flatMap({ posts[$0] }), post.createAt < first.createAt {
            return
        }
        let index = timeline.postIds.lastIndex { (posts[$0]?.createAt ?? 0) <= post.createAt }.map { $0 + 1 } ?? 0
        timeline.postIds.insert(post.id, at: index)
        timelines[post.channelId] = timeline
    }

    func receive(post: Post) {
        guard !deletedPostIds.contains(post.id) else { return }
        let existed = posts[post.id] != nil
        store(post)
        for emoji in post.metadata.emojis { customEmojis[emoji.name] = emoji }
        if post.isBurnOnRead { trackBurnOnRead(posts[post.id] ?? post) }
        insertIntoTimeline(post)
        if !post.rootId.isEmpty, var thread = threads[post.rootId], !thread.postIds.contains(post.id) {
            thread.postIds.append(post.id)
            threads[post.rootId] = thread
        }
        if !existed, !post.rootId.isEmpty, var root = posts[post.rootId] {
            root.replyCount += 1
            root.lastReplyAt = max(root.lastReplyAt, post.createAt)
            root.participantIds.removeAll { $0 == post.userId }
            root.participantIds.append(post.userId)
            posts[post.rootId] = root
        }
        if !existed, var channel = channels[post.channelId] {
            channel.lastPostAt = max(channel.lastPostAt, post.createAt)
            channel.totalMsgCount += 1
            if post.rootId.isEmpty {
                channel.totalMsgCountRoot += 1
                channel.lastRootPostAt = max(channel.lastRootPostAt, post.createAt)
            }
            channels[post.channelId] = channel
            if post.userId == myId, var member = members[post.channelId] {
                member.msgCount = channel.totalMsgCount
                member.msgCountRoot = channel.totalMsgCountRoot
                member.lastViewedAt = max(member.lastViewedAt, post.createAt)
                members[post.channelId] = member
            }
        }
        if users[post.userId] == nil {
            let id = post.userId
            Task { await self.ensureUsers([id]) }
        }
    }

    func removePost(_ postId: String, fallback: Post? = nil) {
        guard !deletedPostIds.contains(postId), let post = posts[postId] ?? fallback else { return }
        deletedPostIds.insert(postId)
        posts[postId] = nil
        timelines[post.channelId]?.postIds.removeAll { $0 == postId }
        if post.rootId.isEmpty {
            threads[postId] = nil
            let replies = Set(posts.values.filter { $0.rootId == postId }.map(\.id))
            guard !replies.isEmpty else { return }
            timelines[post.channelId]?.postIds.removeAll { replies.contains($0) }
            for reply in replies {
                posts[reply] = nil
                pendingPostIds.remove(reply)
            }
        } else {
            threads[post.rootId]?.postIds.removeAll { $0 == postId }
            if var root = posts[post.rootId] {
                root.replyCount = max(0, root.replyCount - 1)
                posts[post.rootId] = root
            }
        }
    }

    func applyReaction(_ reaction: Reaction, added: Bool) {
        guard var post = posts[reaction.postId] else { return }
        post.metadata.reactions.removeAll { $0.userId == reaction.userId && $0.emojiName == reaction.emojiName }
        if added { post.metadata.reactions.append(reaction) }
        posts[reaction.postId] = post
    }

    func applyPreferences(_ list: [Preference]) {
        for preference in list {
            preferences.removeAll { $0.category == preference.category && $0.name == preference.name }
            preferences.append(preference)
        }
    }

    func removeChannelMembership(_ channelId: String) {
        members[channelId] = nil
        timelines[channelId] = nil
        for (teamId, list) in categories {
            categories[teamId] = list.map { category in
                var category = category
                category.channelIds.removeAll { $0 == channelId }
                return category
            }
        }
        if currentChannelId == channelId, let teamId = currentTeamId {
            currentChannelId = nil
            if let next = defaultChannel(teamId: teamId) {
                Task { await self.selectChannel(next) }
            } else {
                onSelectionChange?(teamId, nil)
            }
        }
    }
}
