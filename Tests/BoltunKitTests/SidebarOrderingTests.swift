import Foundation
import Testing
@testable import BoltunKit

@Suite struct SidebarOrderingTests {
    let favorites = ChannelCategory(id: "fav", teamId: "t", type: .favorites, displayName: "Favorites", channelIds: ["f1"])
    let custom = ChannelCategory(id: "work", teamId: "t", type: .custom, displayName: "Work", channelIds: ["w1", "w2"])
    let channels = ChannelCategory(id: "chan", teamId: "t", type: .channels, displayName: "Channels", channelIds: ["c3", "c1", "c2", "hidden"])
    let directs = ChannelCategory(id: "dms", teamId: "t", type: .directMessages, displayName: "Direct Messages", sorting: .recent, channelIds: ["d1", "d2"])

    var all: [ChannelCategory] { [favorites, custom, channels, directs] }

    var displayed: [String: [String]] {
        ["fav": ["f1"], "work": ["w1", "w2"], "chan": ["c1", "c2", "c3"], "dms": ["d2", "d1"]]
    }

    func move(_ id: String, direct: Bool = false, to category: String, index: Int?, in list: [ChannelCategory]? = nil, shown: [String: [String]]? = nil) -> [ChannelCategory]? {
        SidebarOrdering.moveChannel(id, isDirect: direct, to: category, index: index, in: list ?? all, displayed: shown ?? displayed)
    }

    func category(_ id: String, _ list: [ChannelCategory]?) -> ChannelCategory? {
        list?.first { $0.id == id }
    }

    @Test func reorderInsideCategoryUsesDisplayedOrderAndSwitchesToManual() {
        let result = move("c3", to: "chan", index: 0)
        #expect(category("chan", result)?.channelIds == ["c3", "c1", "c2", "hidden"])
        #expect(category("chan", result)?.sorting == .manual)
        #expect(category("chan", move("c1", to: "chan", index: 1))?.channelIds == ["c2", "c1", "c3", "hidden"])
        #expect(category("chan", move("c1", to: "chan", index: 2))?.channelIds == ["c2", "c3", "c1", "hidden"])
        #expect(SidebarOrdering.changed(from: all, to: result ?? []).map(\.id) == ["chan"])
        var alphabetical = all
        alphabetical[1].sorting = .alphabetical
        let sorted = move("w2", to: "work", index: 0, in: alphabetical)
        #expect(category("work", sorted)?.channelIds == ["w2", "w1"])
        #expect(category("work", sorted)?.sorting == .manual)
    }

    @Test func reorderInsideManualCategoryKeepsStoredOrderAndHiddenChannels() {
        var manual = all
        manual[2].sorting = .manual
        let shown = ["chan": ["c3", "c1", "c2"]]
        let result = move("c2", to: "chan", index: 0, in: manual, shown: shown)
        #expect(category("chan", result)?.channelIds == ["c2", "c3", "c1", "hidden"])
        #expect(move("c1", to: "chan", index: 1, in: manual, shown: shown) == nil)
        #expect(category("chan", move("c1", to: "chan", index: 99, in: manual, shown: shown))?.channelIds == ["c3", "c2", "c1", "hidden"])
        #expect(category("chan", move("c2", to: "chan", index: -3, in: manual, shown: shown))?.channelIds == ["c2", "c3", "c1", "hidden"])
        #expect(category("chan", move("c3", to: "chan", index: 1, in: manual, shown: [:]))?.channelIds == ["c1", "c3", "c2", "hidden"])
    }

    @Test func moveBetweenCategories() {
        let result = move("c1", to: "work", index: 1)
        #expect(category("work", result)?.channelIds == ["w1", "c1", "w2"])
        #expect(category("work", result)?.sorting == .manual)
        #expect(category("chan", result)?.channelIds == ["c3", "c2", "hidden"])
        #expect(category("chan", result)?.sorting == .default)
        #expect(SidebarOrdering.changed(from: all, to: result ?? []).map(\.id) == ["work", "chan"])
        let appended = move("w1", to: "chan", index: nil)
        #expect(category("chan", appended)?.channelIds == ["c1", "c2", "c3", "w1", "hidden"])
        #expect(category("chan", appended)?.sorting == .manual)
        #expect(category("work", appended)?.channelIds == ["w2"])
        let favorite = move("c2", to: "fav", index: 0)
        #expect(category("fav", favorite)?.channelIds == ["c2", "f1"])
        let orphan = move("new", to: "work", index: 0)
        #expect(category("work", orphan)?.channelIds == ["new", "w1", "w2"])
    }

    @Test func explicitSortingSurvivesMovesFromOtherCategories() {
        var list = all
        list[1].sorting = .alphabetical
        let result = move("c1", to: "work", index: 0, in: list)
        #expect(category("work", result)?.sorting == .alphabetical)
        #expect(category("work", result)?.channelIds.contains("c1") == true)
        list[1].sorting = .recent
        #expect(category("work", move("c1", to: "work", index: nil, in: list))?.sorting == .recent)
    }

    @Test func directAndGroupChannelsFollowCategoryConstraints() {
        #expect(move("d1", direct: true, to: "chan", index: 0) == nil)
        #expect(move("c1", to: "dms", index: 0) == nil)
        #expect(move("d1", direct: true, to: "dms", index: 0) == nil)
        let custom = move("d1", direct: true, to: "work", index: 0)
        #expect(category("work", custom)?.channelIds == ["d1", "w1", "w2"])
        #expect(category("dms", custom)?.channelIds == ["d2"])
        let favorite = move("d2", direct: true, to: "fav", index: nil)
        #expect(category("fav", favorite)?.channelIds == ["f1", "d2"])
        let back = move("f1", direct: true, to: "dms", index: 0)
        #expect(category("dms", back)?.channelIds == ["f1", "d2", "d1"])
        #expect(category("dms", back)?.sorting == .recent)
        #expect(category("fav", back)?.channelIds == [])
        #expect(move("c1", to: "missing", index: 0) == nil)
    }

    @Test func categoryRules() {
        #expect(CategoryType.favorites.accepts(isDirect: true) && CategoryType.favorites.accepts(isDirect: false))
        #expect(CategoryType.custom.accepts(isDirect: true) && CategoryType.custom.accepts(isDirect: false))
        #expect(CategoryType.channels.accepts(isDirect: false) && !CategoryType.channels.accepts(isDirect: true))
        #expect(CategoryType.directMessages.accepts(isDirect: true) && !CategoryType.directMessages.accepts(isDirect: false))
        #expect(CategoryType.directMessages.sortingOptions == [.alphabetical, .recent])
        #expect(CategoryType.custom.sortingOptions == [.alphabetical, .recent, .manual])
        #expect(CategorySorting.default.resolved(for: .directMessages) == .recent)
        #expect(CategorySorting.default.resolved(for: .custom) == .manual)
        #expect(CategorySorting.default.resolved(for: .channels) == .alphabetical)
        #expect(CategorySorting.default.resolved(for: .favorites) == .alphabetical)
        #expect(CategorySorting.recent.resolved(for: .custom) == .recent)
        #expect(SidebarOrdering.keepsDropPosition(type: .channels, sorting: .default, sameCategory: false))
        #expect(SidebarOrdering.keepsDropPosition(type: .custom, sorting: .manual, sameCategory: false))
        #expect(!SidebarOrdering.keepsDropPosition(type: .custom, sorting: .alphabetical, sameCategory: false))
        #expect(SidebarOrdering.keepsDropPosition(type: .custom, sorting: .alphabetical, sameCategory: true))
        #expect(!SidebarOrdering.keepsDropPosition(type: .directMessages, sorting: .manual, sameCategory: false))
    }

    @Test func reorderCategories() {
        #expect(SidebarOrdering.moveCategory("dms", to: 0, in: all)?.map(\.id) == ["dms", "fav", "work", "chan"])
        #expect(SidebarOrdering.moveCategory("fav", to: 2, in: all)?.map(\.id) == ["work", "chan", "fav", "dms"])
        #expect(SidebarOrdering.moveCategory("work", to: 40, in: all)?.map(\.id) == ["fav", "chan", "dms", "work"])
        #expect(SidebarOrdering.moveCategory("chan", to: -1, in: all)?.map(\.id) == ["chan", "fav", "work", "dms"])
        #expect(SidebarOrdering.moveCategory("chan", to: 2, in: all) == nil)
        #expect(SidebarOrdering.moveCategory("missing", to: 0, in: all) == nil)
    }

    @Test func changeSorting() {
        let manual = SidebarOrdering.setSorting(.manual, categoryId: "chan", in: all, displayed: displayed)
        #expect(category("chan", manual)?.sorting == .manual)
        #expect(category("chan", manual)?.channelIds == ["c1", "c2", "c3", "hidden"])
        let recent = SidebarOrdering.setSorting(.recent, categoryId: "chan", in: all, displayed: displayed)
        #expect(category("chan", recent)?.sorting == .recent)
        #expect(category("chan", recent)?.channelIds == channels.channelIds)
        #expect(SidebarOrdering.setSorting(.alphabetical, categoryId: "chan", in: all, displayed: displayed) == nil)
        #expect(SidebarOrdering.setSorting(.manual, categoryId: "work", in: all, displayed: displayed) == nil)
        #expect(SidebarOrdering.setSorting(.manual, categoryId: "dms", in: all, displayed: displayed) == nil)
        #expect(category("dms", SidebarOrdering.setSorting(.alphabetical, categoryId: "dms", in: all, displayed: displayed))?.sorting == .alphabetical)
        #expect(SidebarOrdering.setSorting(.recent, categoryId: "missing", in: all, displayed: displayed) == nil)
        #expect(category("work", SidebarOrdering.setSorting(.alphabetical, categoryId: "work", in: all, displayed: [:]))?.channelIds == ["w1", "w2"])
    }

    @Test func builderShowsManualOrderAfterMove() {
        let list = [
            Channel(id: "c1", teamId: "t", name: "alpha", displayName: "Alpha"),
            Channel(id: "c2", teamId: "t", name: "bravo", displayName: "Bravo"),
            Channel(id: "c3", teamId: "t", name: "charlie", displayName: "Charlie"),
        ]
        let byId = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        let members = Dictionary(uniqueKeysWithValues: list.map { ($0.id, ChannelMember(channelId: $0.id, userId: "me")) })
        func sections(_ categories: [ChannelCategory]) -> [SidebarSection] {
            SidebarBuilder.sections(categories: categories, channels: byId, members: members, hiddenDirect: [], displayName: { $0.displayName }, currentChannelId: nil)
        }
        let start = [ChannelCategory(id: "chan", teamId: "t", type: .channels, displayName: "Channels", channelIds: ["c3", "c2", "c1"])]
        let before = sections(start)
        #expect(before[0].channelIds == ["c1", "c2", "c3"])
        #expect(before[0].sorting == .default && before[0].effectiveSorting == .alphabetical)
        let moved = SidebarOrdering.moveChannel("c3", isDirect: false, to: "chan", index: 0, in: start, displayed: ["chan": before[0].channelIds])
        let after = sections(moved ?? [])
        #expect(after[0].channelIds == ["c3", "c1", "c2"])
        #expect(after[0].sorting == .manual && after[0].effectiveSorting == .manual)
    }
}
