import Foundation

extension ServerSession {
    public func notifySettings(channelId: String) -> ChannelNotifySettings {
        ChannelNotifySettings(member: members[channelId], user: me)
    }

    public func isMuted(channelId: String) -> Bool {
        members[channelId]?.isMuted ?? false
    }

    @discardableResult
    public func setMuted(channelId: String, _ muted: Bool) async -> Bool {
        guard isMuted(channelId: channelId) != muted else { return true }
        return await updateNotifyProps(channelId: channelId, ChannelNotifySettings.muteProps(muted))
    }

    @discardableResult
    public func toggleMuted(channelId: String) async -> Bool {
        await setMuted(channelId: channelId, !isMuted(channelId: channelId))
    }

    @discardableResult
    public func applyNotifySettings(_ settings: ChannelNotifySettings, channelId: String) async -> Bool {
        let props = settings.changes(from: notifySettings(channelId: channelId))
        guard !props.isEmpty else { return true }
        return await updateNotifyProps(channelId: channelId, props)
    }

    @discardableResult
    public func updateNotifyProps(channelId: String, _ props: [String: String]) async -> Bool {
        guard !props.isEmpty, !myId.isEmpty, let previous = members[channelId] else { return false }
        var updated = previous
        updated.notifyProps.merge(props) { _, new in new }
        guard updated != previous else { return true }
        members[channelId] = updated
        do {
            try await client.updateChannelNotifyProps(channelId: channelId, userId: myId, props: props)
            return true
        } catch {
            if members[channelId]?.notifyProps == updated.notifyProps {
                members[channelId]?.notifyProps = previous.notifyProps
            }
            report(error)
            return false
        }
    }

    public func isMuted(teamId: String) -> Bool {
        teamLayout.isMuted(teamId)
    }

    public func setMuted(teamId: String, _ muted: Bool) {
        teamLayout.setMuted(teamId, muted, in: teams)
    }

    public func toggleMuted(teamId: String) {
        setMuted(teamId: teamId, !isMuted(teamId: teamId))
    }

    func notificationsSuppressed(teamId: String, channelType: ChannelType) -> Bool {
        !channelType.isDirectOrGroup && !teamId.isEmpty && isMuted(teamId: teamId)
    }

    func followsThread(of post: Post) -> Bool {
        posts[post.threadId] == nil || isFollowing(threadId: post.threadId)
    }
}
