import BoltunKit
import SwiftUI

struct ChannelMemberEntry: Equatable, Identifiable {
    var id: String
    var displayName: String
    var username: String
    var status: UserStatusValue?
    var isAdmin: Bool
    var lastPictureUpdate: Int64

    var showsUsername: Bool { username != displayName }
}

enum ChannelMemberListItem: Equatable, Identifiable {
    case section(String)
    case member(ChannelMemberEntry)

    var id: String {
        switch self {
        case .section(let title): return "section:\(title)"
        case .member(let entry): return entry.id
        }
    }
}

enum ChannelMemberList {
    static let adminsTitle = "CHANNEL ADMINS"
    static let membersTitle = "MEMBERS"
    static let searchThreshold = 20
    static let usernameSeparators: Set<Character> = [".", "-", "_"]

    struct Source {
        var users: [String: User]
        var membership: (String) -> ChannelMember?
        var statuses: [String: UserStatusValue] = [:]
        var nameDisplay: NameDisplaySetting = .username
    }

    static func entries(candidateIds: [String], source: Source, term: String) -> [ChannelMemberEntry] {
        var seen = Set<String>()
        var result: [ChannelMemberEntry] = []
        for id in candidateIds where seen.insert(id).inserted {
            guard let user = source.users[id], !user.isDeactivated, let member = source.membership(id) else { continue }
            guard term.isEmpty || matches(user, term: term) else { continue }
            result.append(ChannelMemberEntry(
                id: id,
                displayName: user.displayName(source.nameDisplay),
                username: user.username,
                status: source.statuses[id],
                isAdmin: member.schemeAdmin,
                lastPictureUpdate: user.lastPictureUpdate
            ))
        }
        return result.sorted(by: precedes)
    }

    static func precedes(_ lhs: ChannelMemberEntry, _ rhs: ChannelMemberEntry) -> Bool {
        if lhs.isAdmin != rhs.isAdmin { return lhs.isAdmin }
        let order = lhs.displayName.localizedCompare(rhs.displayName)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.username < rhs.username
    }

    static func items(_ entries: [ChannelMemberEntry]) -> [ChannelMemberListItem] {
        guard let first = entries.first else { return [] }
        var result: [ChannelMemberListItem] = [.section(first.isAdmin ? adminsTitle : membersTitle)]
        var inAdmins = first.isAdmin
        for entry in entries {
            if inAdmins && !entry.isAdmin {
                result.append(.section(membersTitle))
                inAdmins = false
            }
            result.append(.member(entry))
        }
        return result
    }

    static func matches(_ user: User, term: String) -> Bool {
        var trimmed = term.lowercased()
        if trimmed.hasPrefix("@") { trimmed.removeFirst() }
        guard !trimmed.isEmpty else { return true }
        return suggestions(for: user).contains { !$0.isEmpty && $0.hasPrefix(trimmed) }
    }

    static func suggestions(for user: User) -> [String] {
        let email = user.email.lowercased()
        var result = splitSuggestions(user.username.lowercased(), separators: usernameSeparators, keepSeparator: true)
        result += splitSuggestions("\(user.firstName.lowercased()) \(user.lastName.lowercased())", separators: [" "], keepSeparator: false)
        result += splitSuggestions(user.nickname.lowercased(), separators: [" "], keepSeparator: false)
        result.append(email)
        result.append(String(email.split(separator: "@", omittingEmptySubsequences: false).first ?? ""))
        return result
    }

    static func splitSuggestions(_ value: String, separators: Set<Character>, keepSeparator: Bool) -> [String] {
        var result = [value]
        for index in value.indices where separators.contains(value[index]) {
            if keepSeparator { result.append(String(value[index...])) }
            result.append(String(value[value.index(after: index)...]))
        }
        return result
    }

    static func countText(_ count: Int?) -> String {
        guard let count else { return "Members" }
        return count == 1 ? "1 member" : "\(count) members"
    }

    static func showsSearch(memberCount: Int?, term: String) -> Bool {
        (memberCount ?? 0) >= searchThreshold || !term.isEmpty
    }
}

@MainActor
@Observable
final class ChannelMembersModel {
    static let perPage = 100

    let channelId: String
    private(set) var memberIds: [String] = []
    private(set) var searchResultIds: [String] = []
    private(set) var searchTerm = ""
    private(set) var isLoading = false
    private(set) var isSearching = false
    private(set) var reachedEnd = false
    private(set) var nextPage = 0
    @ObservationIgnored private let session: ServerSession
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var generation = 0

    init(channelId: String, session: ServerSession, debounce: Duration = .milliseconds(100)) {
        self.channelId = channelId
        self.session = session
        self.debounce = debounce
    }

    var trimmedTerm: String { searchTerm.trimmingCharacters(in: .whitespacesAndNewlines) }

    var candidateIds: [String] {
        trimmedTerm.isEmpty ? memberIds : memberIds + searchResultIds
    }

    func canLoadMore(memberCount: Int?) -> Bool {
        guard started, !reachedEnd, trimmedTerm.isEmpty else { return false }
        guard let memberCount else { return true }
        return memberIds.count < memberCount
    }

    func entries() -> [ChannelMemberEntry] {
        let session = session
        let channelId = channelId
        let source = ChannelMemberList.Source(
            users: session.users,
            membership: { session.channelMembership(channelId: channelId, userId: $0) },
            statuses: session.statuses,
            nameDisplay: session.nameDisplay
        )
        return ChannelMemberList.entries(candidateIds: candidateIds, source: source, term: trimmedTerm)
    }

    func start() async {
        guard !started else { return }
        started = true
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, !reachedEnd, trimmedTerm.isEmpty else { return }
        isLoading = true
        let current = generation
        let page = nextPage
        let users = await session.loadChannelMembers(channelId: channelId, page: page, perPage: Self.perPage)
        guard current == generation else { return }
        isLoading = false
        guard let users else { return }
        nextPage = page + 1
        let known = Set(memberIds)
        memberIds += users.map(\.id).filter { !known.contains($0) }
        if users.count < Self.perPage { reachedEnd = true }
    }

    func reload() async {
        generation += 1
        memberIds = []
        nextPage = 0
        reachedEnd = false
        isLoading = false
        started = true
        await loadMore()
    }

    func search(_ term: String) {
        searchTerm = term
        searchTask?.cancel()
        let trimmed = trimmedTerm
        guard !trimmed.isEmpty else {
            searchResultIds = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            await runSearch(trimmed)
        }
    }

    func runSearch(_ term: String) async {
        let found = await session.searchChannelMembers(channelId: channelId, term: term)
        guard !Task.isCancelled, term == trimmedTerm else { return }
        searchResultIds = found?.map(\.id) ?? []
        isSearching = false
    }

    func waitForSearch() async {
        await searchTask?.value
    }
}

extension Workspace {
    var membersChannel: Channel? {
        guard let channel = session.currentChannelId.flatMap({ session.channels[$0] }), channel.type != .direct else { return nil }
        return channel
    }

    var showsMembers: Bool { rightPane == .members }

    func toggleMembers() {
        if showsMembers {
            closeRightPane()
        } else {
            openMembers()
        }
    }

    func openMembers() {
        guard let channel = membersChannel else { return }
        closeRightPane()
        rightPane = .members
        membersPanel = nil
        _ = membersModel(channelId: channel.id)
        Task { await refreshMemberCount(channelId: channel.id) }
    }

    func membersModel(channelId: String) -> ChannelMembersModel {
        if let existing = membersPanel, existing.channelId == channelId { return existing }
        let model = ChannelMembersModel(channelId: channelId, session: session, debounce: membersSearchDebounce)
        membersPanel = model
        return model
    }

    func messageMember(userId: String) async {
        profilePopover = nil
        closeRightPane()
        await session.openDirect(userId: userId)
    }

    func refreshMemberCount(channelId: String) async {
        guard let stats = try? await session.client.channelStats(channelId: channelId) else { return }
        if memberCounts[channelId] != stats.memberCount { memberCounts[channelId] = stats.memberCount }
    }
}

struct ChannelMembersPane: View {
    let workspace: Workspace

    var body: some View {
        if let channel = workspace.membersChannel {
            ChannelMembersContent(workspace: workspace, channel: channel, model: workspace.membersModel(channelId: channel.id))
                .id(channel.id)
        } else {
            Color.clear.onAppear { workspace.closeRightPane() }
        }
    }
}

struct ChannelMembersContent: View {
    let workspace: Workspace
    let channel: Channel
    let model: ChannelMembersModel

    var body: some View {
        let count = workspace.memberCounts[channel.id]
        let items = ChannelMemberList.items(model.entries())
        VStack(spacing: 0) {
            PaneHeader(title: "Members", subtitle: workspace.session.displayName(channel: channel)) { workspace.closeRightPane() }
            HStack {
                Text(ChannelMemberList.countText(count))
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            if ChannelMemberList.showsSearch(memberCount: count, term: model.searchTerm) {
                SearchField(text: Binding(get: { model.searchTerm }, set: { model.search($0) }), placeholder: "Search members", onSubmit: {})
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            list(items: items, count: count)
        }
        .task { await model.start() }
        .onChange(of: count) { old, new in
            guard let old, let new, old != new else { return }
            Task { await model.reload() }
        }
    }

    @ViewBuilder
    private func list(items: [ChannelMemberListItem], count: Int?) -> some View {
        if items.isEmpty {
            if model.isLoading || model.isSearching {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.trimmedTerm.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").scaledFont(28).foregroundStyle(Theme.textSecondary)
                    Text("No results for “\(model.trimmedTerm)”").foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        switch item {
                        case .section(let title): ChannelMemberSectionHeader(title: title)
                        case .member(let entry): ChannelMemberRow(workspace: workspace, channelId: channel.id, entry: entry)
                        }
                    }
                    if model.canLoadMore(memberCount: count) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .onAppear { Task { await model.loadMore() } }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}

struct ChannelMemberSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .scaledFont(11.5, weight: .semibold)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }
}

struct ChannelMemberRow: View {
    static let height: CGFloat = 48

    let workspace: Workspace
    let channelId: String
    let entry: ChannelMemberEntry
    @State private var hovering = false

    var body: some View {
        let client = workspace.session.client
        HStack(spacing: 8) {
            ProfilePopoverTrigger(
                workspace: workspace,
                anchor: ProfileAnchor(surface: .members, kind: .member, id: entry.id),
                request: workspace.memberProfileRequest(userId: entry.id, channelId: channelId),
                arrowEdge: .leading
            ) {
                HStack(spacing: 10) {
                    Avatar(
                        url: client.profileImageURL(userId: entry.id, lastPictureUpdate: entry.lastPictureUpdate),
                        client: client,
                        name: entry.displayName,
                        size: 32,
                        status: entry.status,
                        statusRing: hovering ? Theme.hover : Theme.content
                    )
                    HStack(spacing: 6) {
                        Text(entry.displayName)
                            .scaledFont(14, weight: .semibold)
                            .foregroundStyle(Theme.textPrimary)
                        if entry.showsUsername {
                            Text("@\(entry.username)")
                                .scaledFont(13)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            }
            if hovering {
                IconButton(systemName: "paperplane", help: "Send message") {
                    Task { await workspace.messageMember(userId: entry.id) }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Self.height)
        .background(hovering ? Theme.hover : .clear)
        .onHover { hovering = $0 }
    }
}
