import Foundation

extension ServerSession {
    public var unreadScrollPosition: UnreadScrollPosition {
        preferenceValue(category: PreferenceCategory.advancedSettings, name: PreferenceName.unreadScrollPosition)
            .flatMap(UnreadScrollPosition.init(rawValue:)) ?? .startFromLeftOff
    }

    public func unreadMessageCount(channelId: String) -> Int {
        guard let channel = channels[channelId], let member = members[channelId] else { return 0 }
        let unread = collapsedThreads ? channel.totalMsgCountRoot - member.msgCountRoot : channel.totalMsgCount - member.msgCount
        return max(0, unread)
    }

    public func isManuallyUnread(channelId: String) -> Bool {
        manuallyUnread.contains(channelId)
    }

    public func markCurrentChannelViewedIfUnread() async {
        guard let channelId = currentChannelId, !manuallyUnread.contains(channelId), hasUnreadState(channelId: channelId) else { return }
        await markViewed(channelId: channelId)
    }

    func hasUnreadState(channelId: String) -> Bool {
        guard let channel = channels[channelId], let member = members[channelId] else { return false }
        return member.mentionCount > 0 || member.urgentMentionCount > 0 || quietMentions[channelId] != nil
            || channel.totalMsgCount > member.msgCount || channel.totalMsgCountRoot > member.msgCountRoot
    }

    public func updateNewMessagesAt(channelId: String, lastViewedAt: Int64) {
        guard timelines[channelId] != nil, timelines[channelId]?.lastViewedAtOnOpen != lastViewedAt else { return }
        timelines[channelId]?.lastViewedAtOnOpen = lastViewedAt
    }

    func loadUnreadPosts(channelId: String) async {
        var pages = 0
        while pages < unreadPageLimit, needsOlderPostsForUnread(channelId: channelId) {
            await loadOlder(channelId: channelId)
            pages += 1
        }
    }

    func needsOlderPostsForUnread(channelId: String) -> Bool {
        guard let timeline = timelines[channelId], timeline.loaded, timeline.hasMoreOlder, !timeline.isLoading,
              timeline.lastViewedAtOnOpen > 0,
              let oldest = timeline.postIds.lazy.compactMap({ self.posts[$0] }).first
        else { return false }
        return oldest.createAt > timeline.lastViewedAtOnOpen
    }
}
