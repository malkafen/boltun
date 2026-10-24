import AppKit
import Foundation
import SwiftUI
import Testing
@testable import BoltunKit
@testable import BoltunUI

@MainActor
@Suite struct MainSidebarOrderTests {
    func orderTransport() -> RoutedTransport {
        let transport = Fixture.transport()
        transport.on("PUT", "users/me/teams/t1/channels/categories", json: "[]")
        transport.on("PUT", "users/me/teams/t1/channels/categories/order", json: "[]")
        return transport
    }

    func section(_ id: String, _ type: CategoryType, _ ids: [String], sorting: CategorySorting = .default) -> SidebarSection {
        SidebarSection(id: id, title: id.capitalized, type: type, collapsed: false, channelIds: ids, sorting: sorting)
    }

    @Test func fixtureSidebarOrder() {
        let sections = Fixture.session().sidebar
        #expect(sections.map(\.id) == ["fav", "chan", "dms"])
        #expect(sections.map(\.channelIds) == [["offtopic"], ["muted", "secret", "town"], ["dm-alice", "gm", "dm-bob"]])
    }

    @Test func channelMenuEnablesMovesInsideBounds() {
        let sections = Fixture.session().sidebar
        let favorites = SidebarMoveTarget(id: "fav", title: "Favorites")
        let channels = SidebarMoveTarget(id: "chan", title: "Channels")
        #expect(SidebarChannelMenuModel.make(channelId: "town", isDirect: false, sections: sections) == SidebarChannelMenuModel(sectionId: "chan", upIndex: 1, downIndex: nil, targets: [favorites]))
        #expect(SidebarChannelMenuModel.make(channelId: "muted", isDirect: false, sections: sections) == SidebarChannelMenuModel(sectionId: "chan", upIndex: nil, downIndex: 1, targets: [favorites]))
        #expect(SidebarChannelMenuModel.make(channelId: "secret", isDirect: false, sections: sections) == SidebarChannelMenuModel(sectionId: "chan", upIndex: 0, downIndex: 2, targets: [favorites]))
        #expect(SidebarChannelMenuModel.make(channelId: "offtopic", isDirect: false, sections: sections) == SidebarChannelMenuModel(sectionId: "fav", upIndex: nil, downIndex: nil, targets: [channels]))
        #expect(SidebarChannelMenuModel.make(channelId: "gm", isDirect: true, sections: sections) == SidebarChannelMenuModel(sectionId: "dms", upIndex: nil, downIndex: nil, targets: [favorites]))
        #expect(SidebarChannelMenuModel.make(channelId: "missing", isDirect: false, sections: sections) == nil)
        let withCustom = sections + [section("work", .custom, [])]
        #expect(SidebarChannelMenuModel.make(channelId: "gm", isDirect: true, sections: withCustom)?.targets.map(\.id) == ["fav", "work"])
        #expect(SidebarChannelMenuModel.make(channelId: "town", isDirect: false, sections: withCustom)?.targets.map(\.id) == ["fav", "work"])
    }

    @Test func categoryMenuEnablesMovesAndSortingOptions() {
        let sections = Fixture.session().sidebar
        let order = ["fav", "chan", "dms"]
        let favorites = SidebarCategoryMenuModel.make(section: sections[0], visible: sections, order: order)
        #expect(favorites == SidebarCategoryMenuModel(categoryId: "fav", upIndex: nil, downIndex: 1, sortingOptions: [.alphabetical, .recent, .manual], sorting: .alphabetical))
        let channels = SidebarCategoryMenuModel.make(section: sections[1], visible: sections, order: order)
        #expect(channels.upIndex == 0 && channels.downIndex == 2)
        let directs = SidebarCategoryMenuModel.make(section: sections[2], visible: sections, order: order)
        #expect(directs == SidebarCategoryMenuModel(categoryId: "dms", upIndex: 1, downIndex: nil, sortingOptions: [.alphabetical, .recent], sorting: .recent))
        let withoutFavorites = SidebarCategoryMenuModel.make(section: sections[1], visible: Array(sections.dropFirst()), order: order)
        #expect(withoutFavorites.upIndex == nil && withoutFavorites.downIndex == 2)
        let synthetic = section("channels", .channels, ["x"])
        #expect(SidebarCategoryMenuModel.make(section: synthetic, visible: sections + [synthetic], order: order) == SidebarCategoryMenuModel(categoryId: "channels", upIndex: nil, downIndex: nil, sortingOptions: [], sorting: .alphabetical))
        #expect(CategorySorting.allTitles == ["Alphabetically", "By recent activity", "Manually", "Default"])
    }

    @Test func channelDropsOnRows() {
        let sections = Fixture.session().sidebar
        func plan(_ id: String, direct: Bool = false, _ target: SidebarDropTarget, in list: [SidebarSection]? = nil) -> SidebarDropPlan? {
            SidebarDropPlanner.channelPlan(id, isDirect: direct, onto: target, sections: list ?? sections)
        }
        #expect(plan("town", .channel("muted", section: "chan")) == SidebarDropPlan(action: .moveChannel("town", category: "chan", index: 0), insertion: .aboveRow("muted")))
        #expect(plan("muted", .channel("town", section: "chan")) == SidebarDropPlan(action: .moveChannel("muted", category: "chan", index: 2), insertion: .belowRow("town")))
        #expect(plan("muted", .channel("secret", section: "chan")) == SidebarDropPlan(action: .moveChannel("muted", category: "chan", index: 1), insertion: .belowRow("secret")))
        #expect(plan("offtopic", .channel("secret", section: "chan")) == SidebarDropPlan(action: .moveChannel("offtopic", category: "chan", index: 1), insertion: .aboveRow("secret")))
        #expect(plan("town", .channel("town", section: "chan")) == nil)
        #expect(plan("dm-alice", direct: true, .channel("town", section: "chan")) == nil)
        #expect(plan("town", .channel("gm", section: "dms")) == nil)
        #expect(plan("gm", direct: true, .channel("dm-alice", section: "dms")) == nil)
        #expect(plan("town", .channel("x", section: "missing")) == nil)
        #expect(plan("town", .end) == nil)
        #expect(plan("gm", direct: true, .channel("offtopic", section: "fav")) == SidebarDropPlan(action: .moveChannel("gm", category: "fav", index: 0), insertion: .aboveRow("offtopic")))
        let sorted = [section("fav", .favorites, ["offtopic"]), section("chan", .channels, ["muted", "town"], sorting: .alphabetical)]
        #expect(plan("offtopic", .channel("town", section: "chan"), in: sorted) == SidebarDropPlan(action: .moveChannel("offtopic", category: "chan", index: nil), insertion: .intoSection("chan")))
        #expect(plan("town", .channel("muted", section: "chan"), in: sorted) == SidebarDropPlan(action: .moveChannel("town", category: "chan", index: 0), insertion: .aboveRow("muted")))
        #expect(plan("offtopic", direct: true, .channel("dm-bob", section: "dms")) == SidebarDropPlan(action: .moveChannel("offtopic", category: "dms", index: nil), insertion: .intoSection("dms")))
    }

    @Test func channelDropsOnHeaders() {
        let sections = Fixture.session().sidebar
        func plan(_ id: String, direct: Bool = false, _ header: String, in list: [SidebarSection]? = nil) -> SidebarDropPlan? {
            SidebarDropPlanner.channelPlan(id, isDirect: direct, onto: .header(header), sections: list ?? sections)
        }
        #expect(plan("offtopic", "chan") == SidebarDropPlan(action: .moveChannel("offtopic", category: "chan", index: nil), insertion: .intoSection("chan")))
        #expect(plan("town", "fav") == SidebarDropPlan(action: .moveChannel("town", category: "fav", index: nil), insertion: .intoSection("fav")))
        #expect(plan("town", "chan") != nil)
        #expect(plan("muted", "chan") != nil)
        #expect(plan("gm", direct: true, "dms") == nil)
        #expect(plan("gm", direct: true, "chan") == nil)
        #expect(plan("town", "dms") == nil)
        #expect(plan("town", "missing") == nil)
        let manual = [section("chan", .channels, ["muted", "town"], sorting: .manual)]
        #expect(plan("town", "chan", in: manual) == nil)
        #expect(plan("muted", "chan", in: manual) == SidebarDropPlan(action: .moveChannel("muted", category: "chan", index: nil), insertion: .intoSection("chan")))
    }

    @Test func categoryDrops() {
        let sections = Fixture.session().sidebar
        let order = ["fav", "chan", "dms"]
        func plan(_ id: String, _ target: SidebarDropTarget, visible: [SidebarSection]? = nil) -> SidebarDropPlan? {
            SidebarDropPlanner.categoryPlan(id, onto: target, visible: visible ?? sections, order: order)
        }
        #expect(plan("dms", .header("fav")) == SidebarDropPlan(action: .moveCategory("dms", index: 0), insertion: .aboveSection("fav")))
        #expect(plan("fav", .header("chan")) == SidebarDropPlan(action: .moveCategory("fav", index: 1), insertion: .aboveSection("dms")))
        #expect(plan("fav", .header("dms")) == SidebarDropPlan(action: .moveCategory("fav", index: 2), insertion: .end))
        #expect(plan("chan", .channel("offtopic", section: "fav")) == SidebarDropPlan(action: .moveCategory("chan", index: 0), insertion: .aboveSection("fav")))
        #expect(plan("fav", .end) == SidebarDropPlan(action: .moveCategory("fav", index: 2), insertion: .end))
        #expect(plan("chan", .header("dms"), visible: []) == SidebarDropPlan(action: .moveCategory("chan", index: 2), insertion: .end))
        #expect(plan("dms", .end) == nil)
        #expect(plan("chan", .header("chan")) == nil)
        #expect(plan("chan", .header("missing")) == nil)
        #expect(plan("missing", .header("chan")) == nil)
    }

    @Test func dragStateTracksTargetAndPlan() {
        let drag = SidebarDragState()
        let plan = SidebarDropPlan(action: .moveCategory("chan", index: 0), insertion: .aboveSection("fav"))
        var planned: [SidebarDropTarget] = []
        let planner: SidebarDropPlanning = { item, target in
            planned.append(target)
            return item == .category("chan") && target == .header("fav") ? plan : nil
        }
        drag.enter(.header("fav"), planner: planner)
        #expect(drag.insertion == nil && planned.isEmpty)
        #expect(drag.drop(on: .header("fav"), planner: planner) == nil)
        let provider = drag.begin(.category("chan"))
        #expect(provider.canLoadObject(ofClass: NSString.self))
        #expect(drag.item == .category("chan"))
        drag.enter(.header("fav"), planner: planner)
        #expect(drag.insertion == .aboveSection("fav"))
        #expect(drag.operation(for: .header("fav")) == .move)
        drag.enter(.header("dms"), planner: planner)
        #expect(drag.insertion == nil)
        #expect(drag.operation(for: .header("dms")) == .forbidden)
        #expect(drag.operation(for: .end) == .move)
        drag.exit(.header("fav"))
        #expect(drag.target == .header("dms"))
        drag.exit(.header("dms"))
        #expect(drag.target == nil && drag.plan == nil)
        drag.enter(.header("fav"), planner: planner)
        #expect(drag.drop(on: .header("fav"), planner: planner) == plan)
        #expect(drag.item == nil && drag.insertion == nil)
        _ = drag.begin(.category("chan"))
        #expect(drag.drop(on: .header("fav"), planner: planner) == plan)
        #expect(planned.count == 4)
        _ = drag.begin(.channel("town"))
        #expect(drag.item == .channel("town"))
    }

    @Test func sessionPlansAndPerformsDrops() async {
        let transport = orderTransport()
        let session = Fixture.session(transport: transport)
        #expect(session.sidebarDropPlan(.channel("town"), onto: .channel("muted", section: "chan"))?.action == .moveChannel("town", category: "chan", index: 0))
        #expect(session.sidebarDropPlan(.channel("dm-bob"), onto: .header("chan")) == nil)
        #expect(session.sidebarDropPlan(.category("dms"), onto: .header("fav"))?.action == .moveCategory("dms", index: 0))
        await session.perform(.moveChannel("town", category: "chan", index: 0))
        #expect(session.sidebar[1].channelIds == ["town", "muted", "secret"])
        await session.perform(.moveCategory("dms", index: 0))
        #expect(session.sidebar.map(\.id) == ["dms", "fav", "chan"])
        #expect(transport.requests("PUT", "users/me/teams/t1/channels/categories").count == 1)
        #expect(transport.requests("PUT", "users/me/teams/t1/channels/categories/order").count == 1)
        session.currentTeamId = nil
        #expect(session.sidebarDropPlan(.category("dms"), onto: .header("fav")) == nil)
    }

    @Test func menuActionsMoveChannelsAndCategories() async {
        let transport = orderTransport()
        transport.on("PUT", "users/me/teams/t1/channels/categories/dms", json: #"{"id":"dms","type":"direct_messages","sorting":"alpha"}"#)
        let session = Fixture.session(transport: transport)
        let sections = session.sidebar
        let town = SidebarChannelMenuModel.make(channelId: "town", isDirect: false, sections: sections)!
        let items = SidebarChannelMoveItems(channelId: "town", model: town, session: session)
        items.move(index: town.downIndex)
        items.move(index: town.upIndex)
        #expect(await eventually { session.sidebar[1].channelIds == ["muted", "town", "secret"] })
        let menu = SidebarCategoryMenu(model: SidebarCategoryMenuModel.make(section: sections[2], visible: sections, order: ["fav", "chan", "dms"]), session: session)
        menu.move(index: nil)
        menu.move(index: 1)
        #expect(await eventually { session.sidebar.map(\.id) == ["fav", "dms", "chan"] })
        items.move(to: town.targets[0])
        #expect(await eventually { session.sidebar[0].channelIds == ["offtopic", "town"] })
        menu.sort(.alphabetical)
        #expect(await eventually { session.sidebar[1].effectiveSorting == .alphabetical })
        #expect(session.sidebar[1].channelIds == ["dm-alice", "gm", "dm-bob"])
    }

    @Test func rendersOrderingViews() async {
        let workspace = Fixture.workspace(transport: orderTransport())
        let session = workspace.session
        let drag = SidebarDragState()
        let sections = session.sidebar
        let move = SidebarChannelMenuModel.make(channelId: "secret", isDirect: false, sections: sections)!
        let category = SidebarCategoryMenuModel.make(section: sections[1], visible: sections, order: ["fav", "chan", "dms"])
        let view = VStack(spacing: 4) {
            SidebarRow(row: SidebarRowModel.make(channelId: "town", session: session)!, client: session.client) {}
                .overlay { SidebarRowDropIndicator(drag: drag, rowId: "town") }
            SidebarSectionHeader(section: sections[1], onToggle: {}, onAdd: {})
                .overlay { SidebarSectionDropIndicator(drag: drag, sectionId: "chan") }
            SidebarEndDropZone(drag: drag)
            SidebarChannelMoveItems(channelId: "secret", model: move, session: session)
            SidebarCategoryMenu(model: category, session: session)
            SidebarContextMenu(workspace: workspace, row: SidebarRowModel.make(channelId: "secret", session: session)!, move: move)
        }
        .frame(width: 260)
        .background(Theme.sidebar)
        let empty = await MainSnapshot.render(view, size: CGSize(width: 260, height: 520), name: "sidebar-order-idle")
        drag.insertion = .belowRow("town")
        let above = await MainSnapshot.render(view, size: CGSize(width: 260, height: 520), name: "sidebar-order-row")
        #expect(MainSnapshot.distinctColors(above) >= MainSnapshot.distinctColors(empty))
        drag.insertion = .intoSection("chan")
        await MainSnapshot.render(view, size: CGSize(width: 260, height: 520), name: "sidebar-order-section")
        drag.insertion = .end
        await MainSnapshot.render(view, size: CGSize(width: 260, height: 520))
        await MainSnapshot.render(ChannelSidebar(workspace: workspace), size: CGSize(width: 250, height: 600), name: "sidebar-order")
    }
}

extension CategorySorting {
    static var allTitles: [String] {
        [CategorySorting.alphabetical, .recent, .manual, .default].map(\.menuTitle)
    }
}
