import CoreGraphics
import Foundation

struct ReactionEmoji: Hashable, Sendable {
    var name: String
    var glyph: String?
    var customEmojiId: String?
}

extension ReactionChipModel {
    var emoji: ReactionEmoji { ReactionEmoji(name: emojiName, glyph: glyph, customEmojiId: customEmojiId) }
}

struct ReactorEntry: Equatable, Identifiable, Sendable {
    var person: ReactionPerson
    var emojis: [ReactionEmoji] = []

    var id: String { person.id }
}

enum ReactionTab: Hashable, Sendable {
    case all
    case emoji(String)
}

struct ReactionBreakdown: Equatable, Sendable {
    var reactions: [ReactionChipModel]

    var tabs: [ReactionTab] { [.all] + reactions.map { .emoji($0.emojiName) } }

    var totalCount: Int { reactions.reduce(0) { $0 + $1.people.count } }

    var everyone: [ReactorEntry] {
        var order: [String] = []
        var entries: [String: ReactorEntry] = [:]
        for reaction in reactions {
            for person in reaction.people {
                if entries[person.id] == nil {
                    order.append(person.id)
                    entries[person.id] = ReactorEntry(person: person)
                }
                entries[person.id]?.emojis.append(reaction.emoji)
            }
        }
        let ordered = order.compactMap { entries[$0] }
        return ordered.filter(\.person.isMe) + ordered.filter { !$0.person.isMe }
    }

    func resolved(_ tab: ReactionTab) -> ReactionTab {
        guard case .emoji(let name) = tab, reaction(named: name) == nil else { return tab }
        return .all
    }

    func count(for tab: ReactionTab) -> Int {
        switch resolved(tab) {
        case .all: totalCount
        case .emoji(let name): reaction(named: name)?.people.count ?? 0
        }
    }

    func entries(for tab: ReactionTab) -> [ReactorEntry] {
        switch resolved(tab) {
        case .all: everyone
        case .emoji(let name): reaction(named: name)?.people.map { ReactorEntry(person: $0) } ?? []
        }
    }

    private func reaction(named name: String) -> ReactionChipModel? {
        reactions.first { $0.emojiName == name }
    }
}

enum ReactorListLayout {
    static let baseRowHeight: CGFloat = 26
    static let avatarSize: CGFloat = 20

    static func rowHeight(fontScale: Double) -> CGFloat {
        max(avatarSize + 4, (baseRowHeight * fontScale).rounded())
    }

    static func visibleRows(count: Int, limit: Int) -> Int {
        min(max(count, 1), max(limit, 1))
    }

    static func height(visibleRows: Int, rowHeight: CGFloat) -> CGFloat {
        CGFloat(visibleRows) * rowHeight
    }

    static func scrolls(count: Int, visibleRows: Int) -> Bool {
        count > visibleRows
    }
}
