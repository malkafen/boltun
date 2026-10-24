import Foundation
import Testing
@testable import BoltunKit

@Suite struct SidebarTests {
    func channel(_ id: String, _ display: String, type: ChannelType = .open, lastPostAt: Int64 = 0, total: Int = 0, archived: Bool = false) -> Channel {
        Channel(id: id, teamId: type.isDirectOrGroup ? "" : "t", type: type, name: id, displayName: display, lastPostAt: lastPostAt, totalMsgCount: total, deleteAt: archived ? 1 : 0)
    }

    func build(
        _ categories: [ChannelCategory],
        _ channels: [Channel],
        members: [String]? = nil,
        read: [String: Int] = [:],
        hidden: Set<String> = [],
        current: String? = nil,
        limit: Int? = SidebarBuilder.directMessageLimit
    ) -> [SidebarSection] {
        let byId = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })
        let memberIds = members ?? channels.map(\.id)
        let memberMap = Dictionary(uniqueKeysWithValues: memberIds.map { id in
            (id, ChannelMember(channelId: id, userId: "me", msgCount: read[id] ?? byId[id]?.totalMsgCount ?? 0))
        })
        return SidebarBuilder.sections(
            categories: categories,
            channels: byId,
            members: memberMap,
            hiddenDirect: hidden,
            displayName: { $0.displayName },
            currentChannelId: current,
            directMessageLimit: limit
        )
    }

    @Test func sortingModes() {
        let channels = [channel("a", "beta", lastPostAt: 1), channel("b", "Alpha", lastPostAt: 3), channel("c", "gamma", lastPostAt: 2), channel("d", "alpha", lastPostAt: 3)]
        let ids = ["a", "b", "c", "d"]
        let sections = build([
            ChannelCategory(id: "1", type: .custom, displayName: "Alpha", sorting: .alphabetical, channelIds: ids),
        ], channels)
        #expect(sections[0].channelIds == ["b", "d", "a", "c"])
        #expect(build([ChannelCategory(id: "1", type: .custom, displayName: "R", sorting: .recent, channelIds: ids)], channels)[0].channelIds == ["b", "d", "c", "a"])
        #expect(build([ChannelCategory(id: "1", type: .channels, displayName: "M", sorting: .manual, channelIds: ["c", "a", "d", "b"])], channels)[0].channelIds == ["c", "a", "d", "b"])
        #expect(build([ChannelCategory(id: "1", type: .custom, displayName: "C", channelIds: ["c", "a", "d", "b"])], channels)[0].channelIds == ["c", "a", "d", "b"])
        #expect(build([ChannelCategory(id: "1", type: .favorites, displayName: "F", channelIds: ids)], channels)[0].channelIds == ["b", "d", "a", "c"])
        #expect(build([ChannelCategory(id: "1", type: .directMessages, displayName: "D", channelIds: ids)], channels)[0].channelIds == ["b", "d", "c", "a"])
    }

    @Test func filtersArchivedHiddenAndNonMemberChannels() {
        let channels = [channel("a", "a"), channel("old", "old", archived: true), channel("dm", "dm", type: .direct), channel("guest", "guest")]
        let category = ChannelCategory(id: "1", type: .custom, displayName: "All", sorting: .manual, channelIds: ["a", "old", "dm", "guest", "ghost", "a"])
        let sections = build([category], channels, members: ["a", "old", "dm"], hidden: ["dm"])
        #expect(sections[0].channelIds == ["a"])
        let viewing = build([category], channels, members: ["a", "old", "dm"], hidden: ["dm"], current: "old")
        #expect(viewing[0].channelIds == ["a", "old"])
        #expect(build([category], channels, members: ["a"], current: "guest")[0].channelIds == ["a", "guest"])
        #expect(build([category], channels, hidden: ["dm"], current: "dm")[0].channelIds == ["a", "dm", "guest"])
    }

    @Test func firstCategoryClaimsChannel() {
        let channels = [channel("a", "a"), channel("b", "b")]
        let sections = build([
            ChannelCategory(id: "fav", type: .favorites, displayName: "Favorites", channelIds: ["b"]),
            ChannelCategory(id: "ch", type: .channels, displayName: "Channels", channelIds: ["a", "b"]),
        ], channels)
        #expect(sections.map(\.channelIds) == [["b"], ["a"]])
        #expect(sections.map(\.title) == ["Favorites", "Channels"])
    }

    @Test func orphansJoinDefaultCategoriesRespectingSorting() {
        let channels = [channel("m1", "zulu"), channel("m2", "alpha"), channel("new", "mike"), channel("dm-new", "dm", type: .direct, lastPostAt: 50), channel("dm-old", "old", type: .direct, lastPostAt: 10), channel("gone", "gone", archived: true)]
        let sections = build([
            ChannelCategory(id: "ch", type: .channels, displayName: "Channels", sorting: .manual, channelIds: ["m1", "m2"]),
            ChannelCategory(id: "dm", type: .directMessages, displayName: "DMs", channelIds: ["dm-old"]),
        ], channels)
        #expect(sections.map(\.channelIds) == [["m1", "m2", "new"], ["dm-new", "dm-old"]])
    }

    @Test func orphansCreateMissingCategories() {
        let channels = [channel("b", "bravo"), channel("a", "alpha"), channel("d", "dm", type: .group, lastPostAt: 5)]
        let sections = build([], channels)
        #expect(sections.map(\.id) == ["channels", "direct_messages"])
        #expect(sections.map(\.title) == ["Channels", "Direct Messages"])
        #expect(sections.map(\.channelIds) == [["a", "b"], ["d"]])
        #expect(sections.allSatisfy { !$0.collapsed })
    }

    @Test func directMessageLimitKeepsUnreadAndCurrent() {
        let dms = (0..<6).map { channel("d\($0)", "dm\($0)", type: .direct, lastPostAt: Int64(100 - $0), total: 1) }
        let category = ChannelCategory(id: "dm", type: .directMessages, displayName: "DMs", channelIds: dms.map(\.id))
        let limited = build([category], dms, read: ["d4": 0], current: "d5", limit: 3)
        #expect(limited[0].channelIds == ["d0", "d1", "d2", "d4", "d5"])
        #expect(build([category], dms, limit: nil)[0].channelIds.count == 6)
        let defaultLimit = (0..<45).map { channel("x\($0)", "x", type: .direct, lastPostAt: Int64(100 - $0)) }
        let defaults = build([ChannelCategory(id: "dm", type: .directMessages, displayName: "DMs", channelIds: [])], defaultLimit)
        #expect(defaults[0].channelIds.count == SidebarBuilder.directMessageLimit)
    }

    @Test func directMessageLimitPreference() {
        #expect(SidebarBuilder.directMessageLimit(preference: nil) == 40)
        #expect(SidebarBuilder.directMessageLimit(preference: "all") == nil)
        #expect(SidebarBuilder.directMessageLimit(preference: "15") == 15)
        #expect(SidebarBuilder.directMessageLimit(preference: "0") == 40)
        #expect(SidebarBuilder.directMessageLimit(preference: "lots") == 40)
    }

    @Test func unreadComputation() {
        let busy = Channel(id: "c", name: "c", totalMsgCount: 10)
        #expect(SidebarBuilder.unread(channel: busy, member: nil) == .none)
        #expect(SidebarBuilder.unread(channel: busy, member: ChannelMember(channelId: "c", userId: "u", msgCount: 10)) == .none)
        #expect(SidebarBuilder.unread(channel: busy, member: ChannelMember(channelId: "c", userId: "u", msgCount: 7, mentionCount: 2)) == ChannelUnread(unread: true, mentions: 2))
        let muted = ChannelMember(channelId: "c", userId: "u", msgCount: 7, mentionCount: 1, notifyProps: ["mark_unread": "mention"])
        #expect(SidebarBuilder.unread(channel: busy, member: muted) == ChannelUnread(unread: false, mentions: 1))
    }

    @Test func alphabeticalTiesBreakById() {
        let channels = [channel("b", "same"), channel("a", "Same")]
        #expect(build([ChannelCategory(id: "1", type: .channels, displayName: "C", channelIds: ["b", "a"])], channels)[0].channelIds == ["a", "b"])
        #expect(SidebarBuilder.sortAlphabetical(["z", "y"], channels: [:], displayName: { $0.displayName }) == ["y", "z"])
        #expect(SidebarBuilder.sortRecent(["z", "y"], channels: [:]) == ["y", "z"])
    }
}

@Suite struct NotificationPolicyTests {
    let me = User(id: "me", username: "me", notifyProps: ["desktop": "mention"])

    func post(user: String = "other", type: String = "", deleted: Bool = false, props: JSONObject = [:]) -> Post {
        Post(id: "p", deleteAt: deleted ? 1 : 0, userId: user, channelId: "c", message: "hi", type: type, props: props)
    }

    func notify(
        _ post: Post,
        type: ChannelType = .open,
        mentioned: Bool = false,
        me: User? = nil,
        member: ChannelMember? = nil,
        status: UserStatusValue? = .online,
        viewing: Bool = false
    ) -> Bool {
        NotificationPolicy.shouldNotify(post: post, channelType: type, mentioned: mentioned, me: me ?? self.me, member: member, myStatus: status, isViewingChannel: viewing)
    }

    @Test func mentionLevelDefaults() {
        #expect(notify(post(), mentioned: true))
        #expect(!notify(post()))
        #expect(notify(post(), type: .direct))
        #expect(notify(post(), type: .group))
        #expect(notify(post(), me: User(id: "me", username: "me"), member: nil) == false)
        #expect(notify(post(), mentioned: true, me: User(id: "me", username: "me")))
    }

    @Test func suppressedCases() {
        #expect(!notify(post(user: "me"), mentioned: true))
        #expect(!notify(post(type: "system_join_channel"), mentioned: true))
        #expect(!notify(post(deleted: true), mentioned: true))
        #expect(!notify(post(), mentioned: true, status: .dnd))
        #expect(!notify(post(), mentioned: true, viewing: true))
        #expect(!notify(post(props: ["from_webhook": .string("true")])))
        #expect(notify(post(props: ["from_webhook": .string("true")]), mentioned: true))
        #expect(notify(post(props: ["from_webhook": .bool(true)]), type: .direct))
    }

    @Test func channelLevelsOverrideUser() {
        let all = ChannelMember(channelId: "c", userId: "me", notifyProps: ["desktop": "all"])
        let none = ChannelMember(channelId: "c", userId: "me", notifyProps: ["desktop": "none"])
        let muted = ChannelMember(channelId: "c", userId: "me", notifyProps: ["desktop": "all", "mark_unread": "mention"])
        #expect(notify(post(), member: all))
        #expect(!notify(post(), type: .direct, member: none))
        #expect(!notify(post(), mentioned: true, member: muted))
        let userAll = User(id: "me", username: "me", notifyProps: ["desktop": "all"])
        #expect(notify(post(), me: userAll, member: ChannelMember(channelId: "c", userId: "me", notifyProps: ["desktop": "default"])))
        #expect(!notify(post(), me: User(id: "me", username: "me", notifyProps: ["desktop": "none"]), member: nil))
    }

    @Test func preview() {
        #expect(NotificationPolicy.preview("line one\r\n\nline two") == "line one line two")
        #expect(NotificationPolicy.preview("short", limit: 10) == "short")
        #expect(NotificationPolicy.preview("abcdefghij", limit: 5) == "abcd…")
        #expect(NotificationPolicy.preview("") == "")
    }
}
