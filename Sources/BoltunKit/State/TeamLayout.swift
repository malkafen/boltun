import Foundation

public struct TeamSections: Equatable, Sendable {
    public var favorites: [Team]
    public var others: [Team]

    public var all: [Team] { favorites + others }
}

public struct TeamLayout: Codable, Hashable, Sendable {
    public var order: [String]
    public var favorites: [String]

    public init(order: [String] = [], favorites: [String] = []) {
        self.order = order
        self.favorites = favorites
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = c.value(.order, default: [])
        favorites = c.value(.favorites, default: [])
    }

    public var isEmpty: Bool { order.isEmpty && favorites.isEmpty }

    public func isFavorite(_ teamId: String) -> Bool {
        favorites.contains(teamId)
    }

    public func sections(_ teams: [Team]) -> TeamSections {
        let rank = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })
        let ordered = teams.enumerated().sorted { lhs, rhs in
            switch (rank[lhs.element.id], rank[rhs.element.id]) {
            case let (l?, r?): return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
        let favoriteIds = Set(favorites)
        return TeamSections(
            favorites: ordered.filter { favoriteIds.contains($0.id) },
            others: ordered.filter { !favoriteIds.contains($0.id) }
        )
    }

    public func ordered(_ teams: [Team]) -> [Team] {
        sections(teams).all
    }

    public mutating func move(_ teamId: String, to targetId: String, in teams: [Team]) {
        guard teamId != targetId else { return }
        let current = sections(teams)
        var ids = current.all.map(\.id)
        guard let from = ids.firstIndex(of: teamId), let to = ids.firstIndex(of: targetId) else { return }
        let targetIsFavorite = isFavorite(targetId)
        let sameSection = isFavorite(teamId) == targetIsFavorite
        ids.remove(at: from)
        let targetIndex = ids.firstIndex(of: targetId) ?? to
        ids.insert(teamId, at: sameSection && from < to ? targetIndex + 1 : targetIndex)
        apply(ids: ids, teamId: teamId, favorite: targetIsFavorite)
    }

    public mutating func moveToEnd(_ teamId: String, favorite: Bool, in teams: [Team]) {
        let current = sections(teams)
        guard current.all.contains(where: { $0.id == teamId }) else { return }
        var favoriteIds = current.favorites.map(\.id).filter { $0 != teamId }
        var otherIds = current.others.map(\.id).filter { $0 != teamId }
        if favorite { favoriteIds.append(teamId) } else { otherIds.append(teamId) }
        apply(ids: favoriteIds + otherIds, teamId: teamId, favorite: favorite)
    }

    public mutating func setFavorite(_ teamId: String, _ favorite: Bool, in teams: [Team]) {
        guard isFavorite(teamId) != favorite else { return }
        let current = sections(teams)
        guard current.all.contains(where: { $0.id == teamId }) else { return }
        var favoriteIds = current.favorites.map(\.id).filter { $0 != teamId }
        var otherIds = current.others.map(\.id).filter { $0 != teamId }
        if favorite { favoriteIds.append(teamId) } else { otherIds.insert(teamId, at: 0) }
        apply(ids: favoriteIds + otherIds, teamId: teamId, favorite: favorite)
    }

    mutating func apply(ids: [String], teamId: String, favorite: Bool) {
        var favoriteIds = Set(favorites)
        if favorite { favoriteIds.insert(teamId) } else { favoriteIds.remove(teamId) }
        let known = Set(ids)
        order = ids + order.filter { !known.contains($0) }
        favorites = order.filter { favoriteIds.contains($0) }
    }
}
