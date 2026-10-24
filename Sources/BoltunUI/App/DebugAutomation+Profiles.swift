import BoltunKit
import Foundation

extension AutomationUIState {
    struct ProfileSummary: Codable, Equatable, Sendable {
        var anchor: String
        var userId: String
        var loaded: Bool
        var username: String?
        var fullName: String?
        var role: String?
        var botDescription: String?
        var position: String?
        var email: String?
        var localTime: String?
        var customStatus: String?
        var lastOnline: String?
        var status: String?
        var disclaimer: String?
        var isSelf = false
        var button: String?
    }

    struct MembersSummary: Codable, Equatable, Sendable {
        var channel: String
        var count: Int?
        var loaded: Int
        var searchVisible: Bool
        var search: String
        var searching: Bool
        var canLoadMore: Bool
        var items: [String]
    }
}

extension DebugAutomation {
    static let membersSummaryLimit = 80

    func performProfile(_ command: DebugCommand, workspace: Workspace) async throws -> String {
        switch command {
        case .members(let on):
            if on ?? !workspace.showsMembers {
                guard workspace.membersChannel != nil else { throw AutomationError.failed("no channel with members") }
                if !workspace.showsMembers { workspace.openMembers() }
                let model = try membersModel(workspace)
                await model.start()
                await workspace.refreshMemberCount(channelId: model.channelId)
                return "\(model.entries().count)"
            }
            if workspace.showsMembers { workspace.closeRightPane() }
            return ""
        case .membersSearch(let query):
            let model = try membersModel(workspace)
            model.search(query)
            await model.waitForSearch()
            return "\(model.entries().count)"
        case .membersMore:
            let model = try membersModel(workspace)
            await model.loadMore()
            return "\(model.memberIds.count)"
        case .memberMessage(let username):
            let user = try knownUser(username, session: workspace.session)
            await workspace.messageMember(userId: user.id)
            return workspace.session.currentChannelId ?? ""
        case .profile(let target):
            guard let target else {
                workspace.hideProfile()
                return ""
            }
            let (request, anchor) = try await profileRequest(target, workspace: workspace)
            workspace.showProfile(request, anchor: anchor)
            await workspace.session.loadProfile(userId: request.userId, channelId: request.channelId)
            return request.userId
        case .profileMessage:
            guard let presentation = workspace.profilePopover else { throw AutomationError.failed("no profile popover") }
            guard workspace.profileModel(for: presentation.request)?.disclaimer == nil else { throw AutomationError.failed("no message button") }
            await workspace.messageFromProfile(presentation.request)
            return workspace.session.currentChannelId ?? ""
        default:
            throw AutomationError.invalidCommand
        }
    }

    func membersModel(_ workspace: Workspace) throws -> ChannelMembersModel {
        guard workspace.showsMembers, let channel = workspace.membersChannel else { throw AutomationError.failed("members pane is closed") }
        return workspace.membersModel(channelId: channel.id)
    }

    func knownUser(_ username: String, session: ServerSession) throws -> User {
        let lowered = username.lowercased()
        guard let user = session.users.values.first(where: { $0.username.lowercased() == lowered }) else {
            throw AutomationError.failed("unknown user \(username)")
        }
        return user
    }

    func profileRequest(_ target: ProfileTarget, workspace: Workspace) async throws -> (ProfilePopoverRequest, ProfileAnchor) {
        let session = workspace.session
        if target.surface == .members {
            let model = try membersModel(workspace)
            let user = try knownUser(target.username ?? "", session: session)
            let anchor = ProfileAnchor(surface: .members, kind: .member, id: user.id)
            return (workspace.memberProfileRequest(userId: user.id, channelId: model.channelId), anchor)
        }
        let post = try profilePost(target, workspace: workspace)
        let surface = ProfileAnchor.Surface(rawValue: target.surface.rawValue) ?? .channel
        let kind = ProfileAnchor.Kind(rawValue: target.kind.rawValue) ?? .avatar
        let anchor = ProfileAnchor(surface: surface, kind: kind, id: post.id)
        if kind == .mention {
            guard let user = await session.user(mentionName: target.username ?? "") else { throw AutomationError.failed("unknown mention") }
            return (ProfilePopoverRequest(userId: user.id, channelId: post.channelId), anchor)
        }
        guard let request = workspace.profileRequest(for: post) else { throw AutomationError.failed("no profile for post \(post.id)") }
        return (request, anchor)
    }

    func profilePost(_ target: ProfileTarget, workspace: Workspace) throws -> Post {
        let session = workspace.session
        switch target.surface {
        case .search:
            if let postId = target.postId, let post = workspace.searchResults.first(where: { $0.id == postId }) { return post }
            guard workspace.rightPane == .search, workspace.searchResults.indices.contains(target.index) else {
                throw AutomationError.failed("no search result \(target.index)")
            }
            return workspace.searchResults[target.index]
        case .thread:
            guard let rootId = workspace.threadRootId else { throw AutomationError.failed("no open thread") }
            let posts = session.threadPosts(rootId: rootId).filter { !$0.isDeleted && !$0.isSystemMessage }
            if let postId = target.postId, let post = posts.first(where: { $0.id == postId }) { return post }
            guard posts.indices.contains(posts.count - 1 - target.index) else { throw AutomationError.failed("no thread post at index \(target.index)") }
            return posts[posts.count - 1 - target.index]
        default:
            if let postId = target.postId, let post = session.posts[postId] { return post }
            return try post(workspace, fromEnd: target.index)
        }
    }

    static func profileSummary(_ workspace: Workspace) -> AutomationUIState.ProfileSummary? {
        guard let presentation = workspace.profilePopover else { return nil }
        let anchor = "\(presentation.anchor.surface.rawValue):\(presentation.anchor.kind.rawValue):\(presentation.anchor.id)"
        guard let model = workspace.profileModel(for: presentation.request) else {
            return AutomationUIState.ProfileSummary(anchor: anchor, userId: presentation.request.userId, loaded: false)
        }
        let button: String? = model.showsMessageButton ? "Message" : model.showsSelfMessageButton ? "Send yourself a message" : nil
        return AutomationUIState.ProfileSummary(
            anchor: anchor,
            userId: model.userId,
            loaded: true,
            username: model.usernameText,
            fullName: model.fullName.isEmpty ? nil : model.fullName,
            role: model.role?.rawValue,
            botDescription: model.botDescription,
            position: model.position,
            email: model.email,
            localTime: model.localTime.map { [$0.title, $0.time, $0.offset].compactMap { $0 }.joined(separator: " ") },
            customStatus: model.customStatus.map { [":\($0.emoji):", $0.text, $0.expiry].compactMap { $0 }.joined(separator: " ") },
            lastOnline: model.lastOnline,
            status: model.status?.rawValue,
            disclaimer: model.disclaimer,
            isSelf: model.isSelf,
            button: button
        )
    }

    static func membersSummary(_ workspace: Workspace) -> AutomationUIState.MembersSummary? {
        guard workspace.showsMembers, let channel = workspace.membersChannel else { return nil }
        let model = workspace.membersModel(channelId: channel.id)
        let count = workspace.memberCounts[channel.id]
        let items = ChannelMemberList.items(model.entries()).prefix(membersSummaryLimit).map { item in
            switch item {
            case .section(let title): return title
            case .member(let entry):
                let username = entry.showsUsername ? " @\(entry.username)" : ""
                return "\(entry.displayName)\(username) [\(entry.status?.rawValue ?? "-")]"
            }
        }
        return AutomationUIState.MembersSummary(
            channel: workspace.session.displayName(channel: channel),
            count: count,
            loaded: model.memberIds.count,
            searchVisible: ChannelMemberList.showsSearch(memberCount: count, term: model.searchTerm),
            search: model.searchTerm,
            searching: model.isSearching,
            canLoadMore: model.canLoadMore(memberCount: count),
            items: items
        )
    }
}
