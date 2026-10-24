import BoltunKit
import SwiftUI

struct SidebarMoveTarget: Equatable, Identifiable {
    var id: String
    var title: String
}

struct SidebarChannelMenuModel: Equatable {
    var sectionId: String
    var upIndex: Int?
    var downIndex: Int?
    var targets: [SidebarMoveTarget]

    static func make(channelId: String, isDirect: Bool, sections: [SidebarSection]) -> SidebarChannelMenuModel? {
        guard let section = sections.first(where: { $0.channelIds.contains(channelId) }),
              let position = section.channelIds.firstIndex(of: channelId)
        else { return nil }
        let reorderable = section.type.supportsManualOrder
        return SidebarChannelMenuModel(
            sectionId: section.id,
            upIndex: reorderable && position > 0 ? position - 1 : nil,
            downIndex: reorderable && position + 1 < section.channelIds.count ? position + 1 : nil,
            targets: sections
                .filter { $0.id != section.id && $0.type.accepts(isDirect: isDirect) }
                .map { SidebarMoveTarget(id: $0.id, title: $0.title) }
        )
    }
}

struct SidebarCategoryMenuModel: Equatable {
    var categoryId: String
    var upIndex: Int?
    var downIndex: Int?
    var sortingOptions: [CategorySorting]
    var sorting: CategorySorting

    static func make(section: SidebarSection, visible: [SidebarSection], order: [String]) -> SidebarCategoryMenuModel {
        let ids = visible.map(\.id).filter(order.contains)
        let position = ids.firstIndex(of: section.id)
        let previous = position.flatMap { $0 > 0 ? ids[$0 - 1] : nil }
        let next = position.flatMap { $0 + 1 < ids.count ? ids[$0 + 1] : nil }
        return SidebarCategoryMenuModel(
            categoryId: section.id,
            upIndex: previous.flatMap(order.firstIndex(of:)),
            downIndex: next.flatMap(order.firstIndex(of:)),
            sortingOptions: order.contains(section.id) ? section.type.sortingOptions : [],
            sorting: section.effectiveSorting
        )
    }
}

extension CategorySorting {
    var menuTitle: String {
        switch self {
        case .alphabetical: return "Alphabetically"
        case .recent: return "By recent activity"
        case .manual: return "Manually"
        case .default: return "Default"
        }
    }
}

enum SidebarDragItem: Equatable {
    case channel(String)
    case category(String)
}

enum SidebarDropTarget: Equatable {
    case channel(String, section: String)
    case header(String)
    case end
}

enum SidebarInsertion: Equatable {
    case aboveRow(String)
    case belowRow(String)
    case intoSection(String)
    case aboveSection(String)
    case end
}

enum SidebarDropAction: Equatable {
    case moveChannel(String, category: String, index: Int?)
    case moveCategory(String, index: Int)
}

struct SidebarDropPlan: Equatable {
    var action: SidebarDropAction
    var insertion: SidebarInsertion
}

enum SidebarDropPlanner {
    static func channelPlan(_ channelId: String, isDirect: Bool, onto target: SidebarDropTarget, sections: [SidebarSection]) -> SidebarDropPlan? {
        switch target {
        case .end:
            return nil
        case .header(let sectionId):
            guard let section = sections.first(where: { $0.id == sectionId }), section.type.accepts(isDirect: isDirect) else { return nil }
            let same = section.channelIds.contains(channelId)
            guard !same || (section.type.supportsManualOrder && (section.channelIds.last != channelId || section.effectiveSorting != .manual)) else { return nil }
            return SidebarDropPlan(action: .moveChannel(channelId, category: sectionId, index: nil), insertion: .intoSection(sectionId))
        case .channel(let rowId, let sectionId):
            guard rowId != channelId, let section = sections.first(where: { $0.id == sectionId }), section.type.accepts(isDirect: isDirect) else { return nil }
            let same = section.channelIds.contains(channelId)
            guard !same || section.type.supportsManualOrder else { return nil }
            guard SidebarOrdering.keepsDropPosition(type: section.type, sorting: section.sorting, sameCategory: same) else {
                return SidebarDropPlan(action: .moveChannel(channelId, category: sectionId, index: nil), insertion: .intoSection(sectionId))
            }
            let anchors = section.channelIds.filter { $0 != channelId }
            guard let position = anchors.firstIndex(of: rowId), let to = section.channelIds.firstIndex(of: rowId) else { return nil }
            if same, let from = section.channelIds.firstIndex(of: channelId), from < to {
                return SidebarDropPlan(action: .moveChannel(channelId, category: sectionId, index: position + 1), insertion: .belowRow(rowId))
            }
            return SidebarDropPlan(action: .moveChannel(channelId, category: sectionId, index: position), insertion: .aboveRow(rowId))
        }
    }

    static func categoryPlan(_ categoryId: String, onto target: SidebarDropTarget, visible: [SidebarSection], order: [String]) -> SidebarDropPlan? {
        guard let from = order.firstIndex(of: categoryId) else { return nil }
        let targetId: String
        switch target {
        case .end:
            guard from != order.count - 1 else { return nil }
            return SidebarDropPlan(action: .moveCategory(categoryId, index: order.count - 1), insertion: .end)
        case .header(let id), .channel(_, let id):
            targetId = id
        }
        guard targetId != categoryId, let to = order.firstIndex(of: targetId) else { return nil }
        let action = SidebarDropAction.moveCategory(categoryId, index: to)
        if from > to { return SidebarDropPlan(action: action, insertion: .aboveSection(targetId)) }
        let ids = visible.map(\.id)
        let next = ids.firstIndex(of: targetId).flatMap { $0 + 1 < ids.count ? ids[$0 + 1] : nil }
        return SidebarDropPlan(action: action, insertion: next.map(SidebarInsertion.aboveSection) ?? .end)
    }
}

extension ServerSession {
    func sidebarDropPlan(_ item: SidebarDragItem, onto target: SidebarDropTarget) -> SidebarDropPlan? {
        let sections = sidebar
        switch item {
        case .channel(let id):
            return SidebarDropPlanner.channelPlan(id, isDirect: channels[id]?.type.isDirectOrGroup ?? false, onto: target, sections: sections)
        case .category(let id):
            let order = currentTeamId.flatMap { categories[$0] }?.map(\.id) ?? []
            return SidebarDropPlanner.categoryPlan(id, onto: target, visible: ChannelSidebar.visibleSections(sections), order: order)
        }
    }

    func perform(_ action: SidebarDropAction) async {
        switch action {
        case .moveChannel(let id, let category, let index): await moveChannel(id, toCategory: category, index: index)
        case .moveCategory(let id, let index): await moveCategory(id, to: index)
        }
    }
}

@MainActor
@Observable
final class SidebarDragState {
    var insertion: SidebarInsertion?
    @ObservationIgnored var item: SidebarDragItem?
    @ObservationIgnored var target: SidebarDropTarget?
    @ObservationIgnored var plan: SidebarDropPlan?

    func begin(_ item: SidebarDragItem) -> NSItemProvider {
        self.item = item
        clearTarget()
        switch item {
        case .channel(let id), .category(let id): return NSItemProvider(object: id as NSString)
        }
    }

    func enter(_ target: SidebarDropTarget, planner: SidebarDropPlanning) {
        guard let item else { return }
        enter(target, plan: planner(item, target))
    }

    func enter(_ target: SidebarDropTarget, plan: SidebarDropPlan?) {
        self.target = target
        self.plan = plan
        if insertion != plan?.insertion { insertion = plan?.insertion }
    }

    func operation(for target: SidebarDropTarget) -> DropOperation {
        self.target == target && plan == nil ? .forbidden : .move
    }

    func exit(_ target: SidebarDropTarget) {
        guard self.target == target else { return }
        clearTarget()
    }

    func drop(on target: SidebarDropTarget, planner: SidebarDropPlanning) -> SidebarDropPlan? {
        if self.target != target { enter(target, planner: planner) }
        return finish()
    }

    func finish() -> SidebarDropPlan? {
        let result = plan
        item = nil
        clearTarget()
        return result
    }

    func clearTarget() {
        target = nil
        plan = nil
        if insertion != nil { insertion = nil }
    }
}

typealias SidebarDropPlanning = (SidebarDragItem, SidebarDropTarget) -> SidebarDropPlan?

struct SidebarDropDelegate: DropDelegate {
    let target: SidebarDropTarget
    let drag: SidebarDragState
    let planner: SidebarDropPlanning
    let perform: (SidebarDropAction) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        drag.item != nil
    }

    func dropEntered(info: DropInfo) {
        drag.enter(target, planner: planner)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: drag.operation(for: target))
    }

    func dropExited(info: DropInfo) {
        drag.exit(target)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let plan = drag.drop(on: target, planner: planner) else { return false }
        perform(plan.action)
        return true
    }
}

struct SidebarInsertionLine: View {
    let visible: Bool

    var body: some View {
        Capsule()
            .fill(Theme.accent)
            .frame(height: 2)
            .padding(.horizontal, 10)
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: visible)
    }
}

struct SidebarRowDropIndicator: View {
    let drag: SidebarDragState
    let rowId: String

    var body: some View {
        VStack(spacing: 0) {
            SidebarInsertionLine(visible: drag.insertion == .aboveRow(rowId))
            Spacer(minLength: 0)
            SidebarInsertionLine(visible: drag.insertion == .belowRow(rowId))
        }
        .allowsHitTesting(false)
    }
}

struct SidebarSectionDropIndicator: View {
    let drag: SidebarDragState
    let sectionId: String

    var body: some View {
        let into = drag.insertion == .intoSection(sectionId)
        VStack(spacing: 0) {
            SidebarInsertionLine(visible: drag.insertion == .aboveSection(sectionId))
            Spacer(minLength: 0)
        }
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.accent.opacity(into ? 0.22 : 0)).padding(.horizontal, 6))
        .animation(.easeOut(duration: 0.12), value: into)
        .allowsHitTesting(false)
    }
}

struct SidebarEndDropZone: View {
    let drag: SidebarDragState

    var body: some View {
        VStack(spacing: 0) {
            SidebarInsertionLine(visible: drag.insertion == .end)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .contentShape(Rectangle())
    }
}

struct SidebarChannelMoveItems: View {
    let channelId: String
    let model: SidebarChannelMenuModel
    let session: ServerSession

    var body: some View {
        Button("Move Up") { move(index: model.upIndex) }
            .disabled(model.upIndex == nil)
        Button("Move Down") { move(index: model.downIndex) }
            .disabled(model.downIndex == nil)
        if !model.targets.isEmpty {
            Menu("Move to") {
                ForEach(model.targets) { target in
                    Button(target.title) { move(to: target) }
                }
            }
        }
    }

    func move(index: Int?) {
        guard let index else { return }
        Task { await session.moveChannel(channelId, toCategory: model.sectionId, index: index) }
    }

    func move(to target: SidebarMoveTarget) {
        Task { await session.moveChannel(channelId, toCategory: target.id, index: nil) }
    }
}

struct SidebarCategoryMenu: View {
    let model: SidebarCategoryMenuModel
    let session: ServerSession

    var body: some View {
        Button("Move Up") { move(index: model.upIndex) }
            .disabled(model.upIndex == nil)
        Button("Move Down") { move(index: model.downIndex) }
            .disabled(model.downIndex == nil)
        if !model.sortingOptions.isEmpty {
            Menu("Sort") {
                ForEach(model.sortingOptions, id: \.self) { option in
                    Button {
                        sort(option)
                    } label: {
                        if option == model.sorting {
                            Label(option.menuTitle, systemImage: "checkmark")
                        } else {
                            Text(option.menuTitle)
                        }
                    }
                }
            }
        }
    }

    func move(index: Int?) {
        guard let index else { return }
        Task { await session.moveCategory(model.categoryId, to: index) }
    }

    func sort(_ sorting: CategorySorting) {
        Task { await session.setCategorySorting(model.categoryId, sorting) }
    }
}
