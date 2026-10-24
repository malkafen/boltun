import Foundation

extension ServerSession {
    var displayedSidebar: [String: [String]] {
        Dictionary(sidebar.map { ($0.id, $0.channelIds) }, uniquingKeysWith: { a, _ in a })
    }

    @discardableResult
    public func moveChannel(_ channelId: String, toCategory categoryId: String, index: Int?) async -> Bool {
        guard let teamId = currentTeamId, let list = categories[teamId] else { return false }
        let isDirect = channels[channelId]?.type.isDirectOrGroup ?? false
        guard let updated = SidebarOrdering.moveChannel(channelId, isDirect: isDirect, to: categoryId, index: index, in: list, displayed: displayedSidebar) else {
            return false
        }
        let changed = SidebarOrdering.changed(from: list, to: updated)
        return await writeCategories(teamId: teamId, previous: list, updated: updated) {
            _ = try await client.updateCategories(teamId: teamId, changed)
        }
    }

    @discardableResult
    public func moveCategory(_ categoryId: String, to index: Int) async -> Bool {
        guard let teamId = currentTeamId, let list = categories[teamId],
              let updated = SidebarOrdering.moveCategory(categoryId, to: index, in: list)
        else { return false }
        return await writeCategories(teamId: teamId, previous: list, updated: updated) {
            _ = try await client.updateCategoryOrder(teamId: teamId, order: updated.map(\.id))
        }
    }

    @discardableResult
    public func setCategorySorting(_ categoryId: String, _ sorting: CategorySorting) async -> Bool {
        guard let teamId = currentTeamId, let list = categories[teamId],
              let updated = SidebarOrdering.setSorting(sorting, categoryId: categoryId, in: list, displayed: displayedSidebar)
        else { return false }
        let changed = SidebarOrdering.changed(from: list, to: updated)
        return await writeCategories(teamId: teamId, previous: list, updated: updated) {
            for category in changed { _ = try await client.updateCategory(category) }
        }
    }

    func writeCategories(teamId: String, previous: [ChannelCategory], updated: [ChannelCategory], _ request: () async throws -> Void) async -> Bool {
        categories[teamId] = updated
        categoryRevisions[teamId, default: 0] += 1
        categoryWrites[teamId, default: 0] += 1
        var succeeded = true
        do {
            try await request()
        } catch {
            succeeded = false
            if categories[teamId] == updated { categories[teamId] = previous }
            staleCategoryTeams.insert(teamId)
            report(error)
        }
        let remaining = (categoryWrites[teamId] ?? 1) - 1
        categoryWrites[teamId] = remaining > 0 ? remaining : nil
        if remaining <= 0, staleCategoryTeams.remove(teamId) != nil {
            await reloadCategories(teamId: teamId)
        }
        return succeeded
    }

    func reloadCategories(teamId: String) async {
        let revision = categoryRevisions[teamId, default: 0]
        guard let fetched = await quietly({ try await client.myCategories(teamId: teamId).sorted }) else { return }
        if categoryWrites[teamId] != nil {
            staleCategoryTeams.insert(teamId)
        } else if categoryRevisions[teamId, default: 0] != revision {
            await reloadCategories(teamId: teamId)
        } else {
            categories[teamId] = fetched
        }
    }

    func handleCategoryEvent(_ event: WebSocketEvent) {
        let teamId = event.broadcast.teamId.isEmpty ? (event.string("team_id") ?? "") : event.broadcast.teamId
        guard loadedTeams.contains(teamId) else { return }
        categoryRevisions[teamId, default: 0] += 1
        switch event.event {
        case WebSocketEventType.sidebarCategoryUpdated:
            if let updates = event.embedded([ChannelCategory].self, "updatedCategories"), !updates.isEmpty,
               applyUpdatedCategories(updates, teamId: teamId) { return }
        case WebSocketEventType.sidebarCategoryOrderUpdated:
            if let order = event.embedded([String].self, "order"), !order.isEmpty,
               applyCategoryOrder(order, teamId: teamId) { return }
        case WebSocketEventType.sidebarCategoryDeleted:
            if let id = event.string("category_id"), categoryWrites[teamId] == nil {
                categories[teamId]?.removeAll { $0.id == id }
            }
        default:
            break
        }
        scheduleCategoryReload(teamId: teamId)
    }

    func applyUpdatedCategories(_ updates: [ChannelCategory], teamId: String) -> Bool {
        guard let current = categories[teamId] else { return false }
        var list = current
        for update in updates {
            guard let index = list.firstIndex(where: { $0.id == update.id }) else { return false }
            list[index] = update
        }
        return replaceCategories(list, teamId: teamId)
    }

    func applyCategoryOrder(_ order: [String], teamId: String) -> Bool {
        guard let current = categories[teamId] else { return false }
        let known = Set(current.map(\.id))
        guard order.allSatisfy(known.contains) else { return false }
        return replaceCategories(OrderedChannelCategories(categories: current, order: order).sorted, teamId: teamId)
    }

    func replaceCategories(_ list: [ChannelCategory], teamId: String) -> Bool {
        guard list != categories[teamId] else { return true }
        guard categoryWrites[teamId] == nil else { return false }
        categories[teamId] = list
        return true
    }

    func scheduleCategoryReload(teamId: String) {
        if categoryWrites[teamId] != nil {
            staleCategoryTeams.insert(teamId)
        } else {
            Task { await self.reloadCategories(teamId: teamId) }
        }
    }
}
