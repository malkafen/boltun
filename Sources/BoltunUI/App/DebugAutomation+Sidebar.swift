import BoltunKit
import Foundation

extension AutomationUIState {
    struct SidebarCategorySummary: Codable, Equatable, Sendable {
        var id: String
        var title: String
        var type: String
        var sorting: String
        var collapsed: Bool
        var channels: [String]
    }
}

extension DebugAutomation {
    func performSidebarOrder(_ command: DebugCommand, session: ServerSession) async throws -> String {
        switch command {
        case .channelMove(let name, let title, let index):
            let channel = try sidebarChannel(named: name, in: session)
            let section = try title.map { try sidebarSection(named: $0, in: session) } ?? channel.section
            guard await session.moveChannel(channel.id, toCategory: section.id, index: index) else {
                throw AutomationError.failed(session.lastError ?? "cannot move \(name) to \(section.title)")
            }
            return Self.channelNames(sectionId: section.id, session: session).joined(separator: ",")
        case .categoryMove(let title, let index):
            let section = try sidebarSection(named: title, in: session)
            guard await session.moveCategory(section.id, to: index) else {
                throw AutomationError.failed(session.lastError ?? "cannot move \(section.title) to \(index)")
            }
            return session.sidebar.map(\.title).joined(separator: ",")
        case .categorySort(let title, let sorting):
            let section = try sidebarSection(named: title, in: session)
            guard await session.setCategorySorting(section.id, sorting) else {
                throw AutomationError.failed(session.lastError ?? "cannot sort \(section.title) \(sorting.menuTitle.lowercased())")
            }
            return "\(sorting.rawValue) " + Self.channelNames(sectionId: section.id, session: session).joined(separator: ",")
        default:
            throw AutomationError.invalidCommand
        }
    }

    func sidebarSection(named title: String, in session: ServerSession) throws -> SidebarSection {
        guard let section = session.sidebar.first(where: { $0.id == title || $0.title.caseInsensitiveCompare(title) == .orderedSame }) else {
            throw AutomationError.failed("no category \(title)")
        }
        return section
    }

    func sidebarChannel(named name: String, in session: ServerSession) throws -> (id: String, section: SidebarSection) {
        for section in session.sidebar {
            let match = section.channelIds.first { id in
                guard let channel = session.channels[id] else { return false }
                return id == name || channel.name == name || session.displayName(channel: channel).caseInsensitiveCompare(name) == .orderedSame
            }
            if let match { return (match, section) }
        }
        throw AutomationError.failed("no channel \(name)")
    }

    static func channelNames(sectionId: String, session: ServerSession) -> [String] {
        let ids = session.sidebar.first { $0.id == sectionId }?.channelIds ?? []
        return ids.compactMap { session.channels[$0].map(session.displayName(channel:)) }
    }

    static func sidebarSummary(_ session: ServerSession) -> [AutomationUIState.SidebarCategorySummary] {
        session.sidebar.map { section in
            AutomationUIState.SidebarCategorySummary(
                id: section.id,
                title: section.title,
                type: section.type.rawValue,
                sorting: section.effectiveSorting.rawValue,
                collapsed: section.collapsed,
                channels: channelNames(sectionId: section.id, session: session)
            )
        }
    }
}
