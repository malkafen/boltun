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

    @ObservationIgnored public var onNotification: ((MentionNotification) -> Void)?
    @ObservationIgnored public var onUnauthorized: (() -> Void)?
    @ObservationIgnored public var onSelectionChange: ((String?, String?) -> Void)?
    @ObservationIgnored public var isAppActive: () -> Bool = { true }
    @ObservationIgnored public var now: () -> Date = Date.init
    @ObservationIgnored let realtimeFactory: (URL, String) -> RealtimeClient
    @ObservationIgnored var realtime: RealtimeClient?
    @ObservationIgnored var realtimeTask: Task<Void, Never>?
    @ObservationIgnored var pendingUserIds = Set<String>()
    @ObservationIgnored var requestedUserIds = Set<String>()
    @ObservationIgnored var lastTypingSent: [String: Date] = [:]
    @ObservationIgnored var loadedTeams = Set<String>()
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
        let value = preferences.first { $0.category == PreferenceCategory.displaySettings && $0.name == "name_format" }?.value
        return NameDisplaySetting(preference: value ?? config.teammateNameDisplay)
    }

    public var currentTeam: Team? { teams.first { $0.id == currentTeamId } }

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
        return SidebarBuilder.unread(channel: channel, member: members[channelId])
    }

    public func teamUnread(teamId: String) -> ChannelUnread {
        if loadedTeams.contains(teamId) {
            var result = ChannelUnread()
            for (id, channel) in channels where channel.teamId == teamId {
                let unread = SidebarBuilder.unread(channel: channel, member: members[id])
                result.unread = result.unread || unread.unread
                result.mentions += unread.mentions
            }
            return result
        }
        guard let value = teamUnreads[teamId] else { return .none }
        return ChannelUnread(unread: value.msgCount > 0, mentions: value.mentionCount)
    }

    public var directUnread: ChannelUnread {
        var result = ChannelUnread()
        for (id, channel) in channels where channel.type.isDirectOrGroup {
            let unread = SidebarBuilder.unread(channel: channel, member: members[id])
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
            currentChannelId: currentChannelId
        )
    }

    public func timelinePosts(channelId: String) -> [Post] {
        (timelines[channelId]?.postIds ?? []).compactMap { posts[$0] }
    }

    public func threadPosts(rootId: String) -> [Post] {
        (threads[rootId]?.postIds ?? []).compactMap { posts[$0] }
    }

    public func typingUsers(channelId: String, parentId: String = "") -> [String] {
        let cutoff = now().addingTimeInterval(-6)
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
        connection = .connecting
        do {
            try await loadInitial()
            connection = .connected
            startRealtime(token: token)
        } catch let error as APIError where error.isUnauthorized {
            connection = .unauthorized
            onUnauthorized?()
        } catch {
            connection = .failed(APIError.wrap(error).localizedDescription)
            lastError = APIError.wrap(error).localizedDescription
        }
    }

    public func stop() {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let realtime { Task { await realtime.stop() } }
        realtime = nil
        connection = .idle
    }

    public func updateToken(_ token: String?) {
        client.token = token
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
        teams = myTeams.filter { $0.deleteAt == 0 }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        teamUnreads = Dictionary(unreads.map { ($0.teamId, $0) }, uniquingKeysWith: { a, _ in a })
        preferences = prefs
        loadedTeams.removeAll()
        if let teamId = currentTeamId, teams.contains(where: { $0.id == teamId }) {
            try await loadTeam(teamId)
        }
        if let channelId = currentChannelId, timelines[channelId]?.loaded == true {
            timelines[channelId] = nil
            await loadLatest(channelId: channelId)
        }
        Task { await self.loadCustomEmojis() }
    }

    public func selectTeam(_ teamId: String, channelId: String? = nil) async {
        guard teams.contains(where: { $0.id == teamId }) else { return }
        let previous = currentChannelId
        currentTeamId = teamId
        do {
            if !loadedTeams.contains(teamId) { try await loadTeam(teamId) }
        } catch {
            lastError = APIError.wrap(error).localizedDescription
            return
        }
        guard currentTeamId == teamId else { return }
        let target = channelId.flatMap { channels[$0] != nil ? $0 : nil } ?? defaultChannel(teamId: teamId)
        if let target {
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
        for channel in teamChannels { channels[channel.id] = channel }
        for member in teamMembers { members[member.channelId] = member }
        categories[teamId] = teamCategories.sorted
        loadedTeams.insert(teamId)
        var needed = Set<String>()
        for channel in teamChannels where channel.type == .direct {
            if let partner = channel.directPartnerId(me: myId) { needed.insert(partner) }
        }
        await ensureUsers(Array(needed))
        await refreshStatuses(Array(needed))
    }

    public func selectChannel(_ channelId: String, previous: String? = nil) async {
        let previousId = previous ?? currentChannelId
        if let channel = channels[channelId], !channel.teamId.isEmpty, channel.teamId != currentTeamId {
            currentTeamId = channel.teamId
        }
        currentChannelId = channelId
        onSelectionChange?(currentTeamId, channelId)
        var timeline = timelines[channelId] ?? ChannelTimeline()
        timeline.lastViewedAtOnOpen = members[channelId]?.lastViewedAt ?? 0
        timelines[channelId] = timeline
        if timeline.loaded {
            await loadNewer(channelId: channelId)
        } else {
            await loadLatest(channelId: channelId)
        }
        await markViewed(channelId: channelId, previous: previousId ?? "")
    }

    public func markViewed(channelId: String, previous: String = "") async {
        guard let channel = channels[channelId] else { return }
        if var member = members[channelId] {
            member.msgCount = channel.totalMsgCount
            member.msgCountRoot = channel.totalMsgCountRoot
            member.mentionCount = 0
            member.mentionCountRoot = 0
            member.urgentMentionCount = 0
            member.lastViewedAt = max(member.lastViewedAt, channel.lastPostAt)
            members[channelId] = member
        }
        try? await client.viewChannel(channelId: channelId, previousChannelId: previous)
    }

    func loadLatest(channelId: String) async {
        var timeline = timelines[channelId] ?? ChannelTimeline()
        guard !timeline.isLoading else { return }
        timeline.isLoading = true
        timelines[channelId] = timeline
        do {
            let list = try await client.posts(channelId: channelId, page: .latest(perPage: pageSize))
            ingest(list)
            timeline = timelines[channelId] ?? ChannelTimeline()
            let fetched = list.order.reversed().filter { posts[$0] != nil }
            let existing = timeline.postIds.filter { id in !fetched.contains(id) && (posts[id]?.createAt ?? 0) > (list.posts[fetched.last ?? ""]?.createAt ?? Int64.max) }
            timeline.postIds = fetched + existing
            timeline.hasMoreOlder = list.order.count >= pageSize
            timeline.loaded = true
        } catch {
            lastError = APIError.wrap(error).localizedDescription
        }
        timeline.isLoading = false
        timelines[channelId] = timeline
    }

    public func loadOlder(channelId: String) async {
        guard var timeline = timelines[channelId], timeline.loaded, timeline.hasMoreOlder, !timeline.isLoading,
              let oldest = timeline.postIds.first
        else { return }
        timeline.isLoading = true
        timelines[channelId] = timeline
        do {
            let list = try await client.posts(channelId: channelId, page: .before(postId: oldest, perPage: pageSize))
            ingest(list)
            timeline = timelines[channelId] ?? timeline
            let existing = Set(timeline.postIds)
            let older = list.order.reversed().filter { !existing.contains($0) && posts[$0] != nil }
            timeline.postIds.insert(contentsOf: older, at: 0)
            timeline.hasMoreOlder = list.order.count >= pageSize
        } catch {
            lastError = APIError.wrap(error).localizedDescription
        }
        timeline.isLoading = false
        timelines[channelId] = timeline
    }

    func loadNewer(channelId: String) async {
        guard let timeline = timelines[channelId], let newest = timeline.postIds.last.flatMap({ posts[$0] }) else {
            await loadLatest(channelId: channelId)
            return
        }
        do {
            let list = try await client.posts(channelId: channelId, page: .since(newest.updateAt > 0 ? newest.updateAt : newest.createAt))
            ingest(list)
            for post in list.orderedPosts.sorted(by: { $0.createAt < $1.createAt }) {
                insertIntoTimeline(post)
            }
        } catch {
            lastError = APIError.wrap(error).localizedDescription
        }
    }

    public func openThread(rootId: String) async {
        var state = threads[rootId] ?? ThreadState(rootId: rootId)
        state.isLoading = true
        threads[rootId] = state
        do {
            let list = try await client.postThread(postId: rootId)
            ingest(list)
            state.postIds = list.posts.values.sorted { $0.createAt < $1.createAt }.map(\.id)
        } catch {
            lastError = APIError.wrap(error).localizedDescription
        }
        state.isLoading = false
        threads[rootId] = state
    }

    public func closeThread(rootId: String) {
        threads[rootId] = nil
    }

    @discardableResult
    public func send(_ message: String, channelId: String, rootId: String = "", fileIds: [String] = []) async -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !fileIds.isEmpty else { return false }
        let pendingId = "\(myId):\(now().mattermostMillis)"
        do {
            let post = try await client.createPost(channelId: channelId, message: trimmed, rootId: rootId, fileIds: fileIds, pendingPostId: pendingId)
            receive(post: post)
            return true
        } catch {
            lastError = APIError.wrap(error).localizedDescription
            return false
        }
    }

    @discardableResult
    public func edit(postId: String, message: String) async -> Bool {
        do {
            receive(post: try await client.patchPost(id: postId, message: message))
            return true
        } catch {
            lastError = APIError.wrap(error).localizedDescription
            return false
        }
    }

    public func delete(postId: String) async {
        do {
            try await client.deletePost(id: postId)
            removePost(postId)
        } catch {
            lastError = APIError.wrap(error).localizedDescription
        }
    }

    public func toggleReaction(postId: String, emojiName: String) async {
        guard let post = posts[postId] else { return }
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
            lastError = APIError.wrap(error).localizedDescription
        }
    }

    public func setPinned(postId: String, pinned: Bool) async {
        do {
            try await client.pinPost(id: postId, pinned: pinned)
            posts[postId]?.isPinned = pinned
        } catch {
            lastError = APIError.wrap(error).localizedDescription
        }
    }

    public func upload(channelId: String, filename: String, data: Data, mimeType: String) async -> FileInfo? {
        do {
            return try await client.uploadFile(channelId: channelId, filename: filename, data: data, mimeType: mimeType)
        } catch {
            lastError = APIError.wrap(error).localizedDescription
            return nil
        }
    }

    public func search(_ terms: String) async -> [Post] {
        guard let teamId = currentTeamId, !terms.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        do {
            let results = try await client.searchPosts(teamId: teamId, terms: terms)
            for post in results.posts.values { posts[post.id] = posts[post.id] ?? post }
            let found = results.orderedPosts
            await ensureUsers(found.map(\.userId))
            await ensureChannels(found.map(\.channelId))
            return found
        } catch {
            lastError = APIError.wrap(error).localizedDescription
            return []
        }
    }

    public func autocompleteUsers(_ prefix: String, channelId: String?) async -> [User] {
        do {
            let found = try await client.autocompleteUsers(name: prefix, teamId: currentTeamId, channelId: channelId)
            for user in found { users[user.id] = user }
            return found
        } catch {
            return []
        }
    }

    public func autocompleteChannels(_ prefix: String) async -> [Channel] {
        guard let teamId = currentTeamId else { return [] }
        return (try? await client.autocompleteChannels(teamId: teamId, name: prefix)) ?? []
    }

    public func browsePublicChannels() async -> [Channel] {
        guard let teamId = currentTeamId else { return [] }
        do {
            return try await client.publicChannels(teamId: teamId).filter { !$0.isArchived }
        } catch {
            lastError = APIError.wrap(error).localizedDescription
            return []
        }
    }

    public func join(channel: Channel) async {
        do {
            let member = try await client.joinChannel(channelId: channel.id, userId: myId)
            channels[channel.id] = channel
            members[channel.id] = member
            if let teamId = currentTeamId { try? await refreshCategories(teamId: teamId) }
            await selectChannel(channel.id)
        } catch {
            lastError = APIError.wrap(error).localizedDescription
        }
    }

    public func leave(channelId: String) async {
        do {
            try await client.leaveChannel(channelId: channelId, userId: myId)
            removeChannelMembership(channelId)
        } catch {
            lastError = APIError.wrap(error).localizedDescription
        }
    }

    public func openDirect(userId: String) async {
        do {
            let channel = try await client.createDirectChannel(userIds: [myId, userId])
            channels[channel.id] = channel
            if members[channel.id] == nil {
                members[channel.id] = (try? await client.channelMember(channelId: channel.id)) ?? ChannelMember(channelId: channel.id, userId: myId)
            }
            await ensureUsers([userId])
            if preferences.contains(where: { $0.category == PreferenceCategory.directChannelShow && $0.name == userId && $0.value == "false" }) {
                await savePreference(category: PreferenceCategory.directChannelShow, name: userId, value: "true")
            }
            await selectChannel(channel.id)
        } catch {
            lastError = APIError.wrap(error).localizedDescription
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
        for category in changed {
            _ = try? await client.updateCategory(category)
        }
    }

    public func setCategoryCollapsed(_ categoryId: String, collapsed: Bool) async {
        guard let teamId = currentTeamId, var list = categories[teamId],
              let index = list.firstIndex(where: { $0.id == categoryId })
        else { return }
        list[index].collapsed = collapsed
        categories[teamId] = list
        _ = try? await client.updateCategory(list[index])
    }

    public func savePreference(category: String, name: String, value: String) async {
        let preference = Preference(userId: myId, category: category, name: name, value: value)
        applyPreferences([preference])
        try? await client.savePreferences(userId: myId, [preference])
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
            lastError = APIError.wrap(error).localizedDescription
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
            if let found = try? await client.users(ids: batch) {
                for user in found { users[user.id] = user }
            } else {
                requestedUserIds.subtract(batch)
            }
        }
    }

    func ensureChannels(_ ids: [String]) async {
        for id in Set(ids) where channels[id] == nil {
            if let channel = try? await client.channel(id: id) { channels[id] = channel }
        }
    }

    public func refreshStatuses(_ ids: [String]) async {
        guard !ids.isEmpty, let found = try? await client.statuses(userIds: ids) else { return }
        for status in found { statuses[status.userId] = status.status }
    }

    func refreshCategories(teamId: String) async throws {
        categories[teamId] = try await client.myCategories(teamId: teamId).sorted
    }

    func loadCustomEmojis() async {
        guard config.enableCustomEmoji else { return }
        var page = 0
        while page < 20 {
            guard let batch = try? await client.customEmojis(page: page) else { return }
            for emoji in batch { customEmojis[emoji.name] = emoji }
            if batch.count < 200 { return }
            page += 1
        }
    }

    func ingest(_ list: PostList) {
        var userIds = Set<String>()
        for post in list.posts.values {
            posts[post.id] = post
            userIds.insert(post.userId)
            for emoji in post.metadata.emojis { customEmojis[emoji.name] = emoji }
            for reaction in post.metadata.reactions { userIds.insert(reaction.userId) }
        }
        let ids = Array(userIds)
        Task { await self.ensureUsers(ids) }
    }

    func insertIntoTimeline(_ post: Post) {
        guard var timeline = timelines[post.channelId], timeline.loaded else { return }
        guard !timeline.postIds.contains(post.id) else { return }
        if let last = timeline.postIds.last.flatMap({ posts[$0] }), last.createAt > post.createAt {
            let index = timeline.postIds.firstIndex { (posts[$0]?.createAt ?? 0) > post.createAt } ?? timeline.postIds.count
            timeline.postIds.insert(post.id, at: index)
        } else {
            timeline.postIds.append(post.id)
        }
        timelines[post.channelId] = timeline
    }

    func receive(post: Post) {
        let existed = posts[post.id] != nil
        posts[post.id] = post
        for emoji in post.metadata.emojis { customEmojis[emoji.name] = emoji }
        insertIntoTimeline(post)
        if !post.rootId.isEmpty, var thread = threads[post.rootId], !thread.postIds.contains(post.id) {
            thread.postIds.append(post.id)
            threads[post.rootId] = thread
        }
        if !existed, !post.rootId.isEmpty, var root = posts[post.rootId] {
            root.replyCount += 1
            root.lastReplyAt = max(root.lastReplyAt, post.createAt)
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

    func removePost(_ postId: String) {
        guard let post = posts[postId] else { return }
        posts[postId] = nil
        if var timeline = timelines[post.channelId] {
            timeline.postIds.removeAll { $0 == postId }
            timelines[post.channelId] = timeline
        }
        if !post.rootId.isEmpty {
            if var thread = threads[post.rootId] {
                thread.postIds.removeAll { $0 == postId }
                threads[post.rootId] = thread
            }
            if var root = posts[post.rootId] {
                root.replyCount = max(0, root.replyCount - 1)
                posts[post.rootId] = root
            }
        } else {
            threads[postId] = nil
            let replies = posts.values.filter { $0.rootId == postId }.map(\.id)
            if var timeline = timelines[post.channelId] {
                timeline.postIds.removeAll { replies.contains($0) }
                timelines[post.channelId] = timeline
            }
            for reply in replies { posts[reply] = nil }
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
            }
        }
    }
}
