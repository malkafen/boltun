import Foundation

public extension CategoryType {
    func accepts(isDirect: Bool) -> Bool {
        switch self {
        case .favorites, .custom: return true
        case .channels: return !isDirect
        case .directMessages: return isDirect
        }
    }

    var supportsManualOrder: Bool { self != .directMessages }

    var sortingOptions: [CategorySorting] {
        supportsManualOrder ? [.alphabetical, .recent, .manual] : [.alphabetical, .recent]
    }
}

public extension CategorySorting {
    func resolved(for type: CategoryType) -> CategorySorting {
        guard self == .default else { return self }
        switch type {
        case .directMessages: return .recent
        case .custom: return .manual
        case .channels, .favorites: return .alphabetical
        }
    }
}

public enum SidebarOrdering {
    public static func moveChannel(
        _ channelId: String,
        isDirect: Bool,
        to categoryId: String,
        index: Int?,
        in categories: [ChannelCategory],
        displayed: [String: [String]]
    ) -> [ChannelCategory]? {
        guard let target = categories.firstIndex(where: { $0.id == categoryId }),
              categories[target].type.accepts(isDirect: isDirect)
        else { return nil }
        let category = categories[target]
        let sameCategory = category.channelIds.contains(channelId)
        guard !sameCategory || category.type.supportsManualOrder else { return nil }
        let shown = displayed[categoryId] ?? category.channelIds
        var ids = baseOrder(category, shown: shown).filter { $0 != channelId }
        ids.insert(channelId, at: insertionPoint(in: ids, anchors: shown.filter { $0 != channelId }, index: index))
        var result = categories
        for other in result.indices where other != target {
            result[other].channelIds.removeAll { $0 == channelId }
        }
        result[target].channelIds = ids
        result[target].sorting = sortingAfterMove(type: category.type, sorting: category.sorting, sameCategory: sameCategory)
        return result == categories ? nil : result
    }

    public static func moveCategory(_ categoryId: String, to index: Int, in categories: [ChannelCategory]) -> [ChannelCategory]? {
        guard let from = categories.firstIndex(where: { $0.id == categoryId }) else { return nil }
        let to = min(max(index, 0), categories.count - 1)
        guard from != to else { return nil }
        var result = categories
        result.insert(result.remove(at: from), at: to)
        return result
    }

    public static func setSorting(
        _ sorting: CategorySorting,
        categoryId: String,
        in categories: [ChannelCategory],
        displayed: [String: [String]]
    ) -> [ChannelCategory]? {
        guard let index = categories.firstIndex(where: { $0.id == categoryId }),
              categories[index].type.sortingOptions.contains(sorting)
        else { return nil }
        let category = categories[index]
        guard category.sorting.resolved(for: category.type) != sorting else { return nil }
        var result = categories
        if sorting == .manual {
            result[index].channelIds = baseOrder(category, shown: displayed[categoryId] ?? category.channelIds)
        }
        result[index].sorting = sorting
        return result
    }

    public static func changed(from old: [ChannelCategory], to new: [ChannelCategory]) -> [ChannelCategory] {
        let previous = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return new.filter { previous[$0.id] != $0 }
    }

    static func insertionPoint(in ids: [String], anchors: [String], index: Int?) -> Int {
        if let index, anchors.indices.contains(max(index, 0)), let position = ids.firstIndex(of: anchors[max(index, 0)]) {
            return position
        }
        guard let last = anchors.last, let position = ids.firstIndex(of: last) else { return ids.count }
        return position + 1
    }

    static func baseOrder(_ category: ChannelCategory, shown: [String]) -> [String] {
        var seen = Set<String>()
        let source = category.sorting.resolved(for: category.type) == .manual ? category.channelIds : shown + category.channelIds
        return source.filter { seen.insert($0).inserted }
    }

    public static func keepsDropPosition(type: CategoryType, sorting: CategorySorting, sameCategory: Bool) -> Bool {
        type.supportsManualOrder && sortingAfterMove(type: type, sorting: sorting, sameCategory: sameCategory).resolved(for: type) == .manual
    }

    static func sortingAfterMove(type: CategoryType, sorting: CategorySorting, sameCategory: Bool) -> CategorySorting {
        guard type.supportsManualOrder else { return sorting }
        if sameCategory || sorting == .default { return .manual }
        return sorting
    }
}
