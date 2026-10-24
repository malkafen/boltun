import BoltunKit
import Foundation

extension AppRouter {
    @discardableResult
    public func open(url: URL) async -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        guard let match = link.match(in: model.servers) else {
            if link.isWeb { openExternalURL(url) }
            reportRouteError(link.isWeb ? nil : "No server matches \(link.host)")
            return false
        }
        return await route(match)
    }

    @discardableResult
    public func route(_ match: DeepLinkMatch) async -> Bool {
        showMainWindow()
        reportRouteError(nil)
        let serverId = match.server.id
        if model.selectedServerId != serverId { await model.select(serverId: serverId) }
        guard let session = await connectedSession(serverId) else { return false }
        let opened: Bool
        switch match.route {
        case .server:
            opened = true
        case .team(let team):
            opened = await session.open(teamName: team)
        case .channel(let team, let name), .groupMessage(let team, let name):
            opened = await session.open(teamName: team, channelName: name)
        case .direct(let team, let username):
            opened = await session.openDirect(username: username, teamName: team)
        case .permalink(_, let postId):
            opened = await openPermalink(postId, in: session)
        case .thread(_, let rootId):
            opened = await openPermalink(rootId, in: session, forceThread: true)
        }
        if !opened { reportRouteError(session.lastError ?? "Could not open link") }
        return opened
    }

    func openPermalink(_ postId: String, in session: ServerSession, forceThread: Bool = false) async -> Bool {
        guard let post = await session.openPermalink(postId: postId) else { return false }
        send(.highlightPost(postId: post.id))
        if forceThread || !post.rootId.isEmpty {
            send(.openThread(rootId: post.rootId.isEmpty ? post.id : post.rootId))
        }
        return true
    }
}
