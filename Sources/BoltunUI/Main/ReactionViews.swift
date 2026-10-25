import BoltunKit
import SwiftUI

struct ReactionChip: View {
    let reaction: ReactionChipModel
    let client: APIClient?
    var onSelectPerson: ((ReactionPerson) -> Void)?
    var onViewAll: (() -> Void)?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                EmojiGlyphView(name: reaction.emojiName, glyph: reaction.glyph, customEmojiId: reaction.customEmojiId, client: client, size: 14)
                Text("\(reaction.count)")
                    .scaledFont(11.5, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(reaction.isMine ? Theme.link : Theme.textSecondary)
            }
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(Capsule().fill(reaction.isMine ? Theme.reactionMine : Theme.reactionBackground))
            .overlay(Capsule().strokeBorder(reaction.isMine ? Theme.reactionMineBorder : Color.clear))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .hoverCard(value: reaction, interactive: true) {
            ReactorsCard(reaction: reaction, client: client, onSelectPerson: selectPerson, onViewAll: viewAll)
        }
        .contextMenu { ReactionMenu(reaction: reaction, onViewAll: viewAll, action: action) }
        .accessibilityLabel(reaction.tooltip)
    }

    private var selectPerson: ((ReactionPerson) -> Void)? {
        onSelectPerson.map { select in
            { person in
                HoverCardPanel.shared.close()
                select(person)
            }
        }
    }

    private var viewAll: (() -> Void)? {
        onViewAll.map { open in
            {
                HoverCardPanel.shared.close()
                open()
            }
        }
    }
}

struct ReactionMenu: View {
    let reaction: ReactionChipModel
    var onViewAll: (() -> Void)?
    let action: () -> Void

    var body: some View {
        Button(ReactionText.toggleTitle(isMine: reaction.isMine), action: action)
        if let onViewAll {
            Button(ReactionText.viewAllTitle, action: onViewAll)
        }
        Divider()
        Section(ReactionText.reactedWith(reaction.emojiName)) {
            ForEach(reaction.people) { person in
                Text(person.displayName)
            }
        }
    }
}

struct ReactorsCard: View {
    static let width: CGFloat = 260
    static let maxVisibleRows = 10

    let reaction: ReactionChipModel
    let client: APIClient?
    var onSelectPerson: ((ReactionPerson) -> Void)?
    var onViewAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.separator)
            ReactorList(
                entries: reaction.people.map { ReactorEntry(person: $0) },
                client: client,
                visibleRows: ReactorListLayout.visibleRows(count: reaction.people.count, limit: Self.maxVisibleRows),
                onSelect: onSelectPerson
            )
            .padding(.vertical, 4)
            Divider().overlay(Theme.separator)
            footer
        }
        .frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.popover))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    var header: some View {
        HStack(spacing: 10) {
            EmojiGlyphView(name: reaction.emojiName, glyph: reaction.glyph, customEmojiId: reaction.customEmojiId, client: client, size: 26)
                .frame(minWidth: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(":\(reaction.emojiName):")
                    .scaledFont(12.5, weight: .semibold)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ReactionText.peopleCount(reaction.people.count))
                    .scaledFont(11)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    var footer: some View {
        HStack(spacing: 8) {
            Text(ReactionText.clickHint(isMine: reaction.isMine, emojiName: reaction.emojiName))
                .scaledFont(10.5)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let onViewAll {
                Button(ReactionText.viewAllLink, action: onViewAll)
                    .buttonStyle(.plain)
                    .scaledFont(10.5, weight: .semibold)
                    .foregroundStyle(Theme.link)
                    .pointerStyle(.link)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct ReactorList: View {
    let entries: [ReactorEntry]
    let client: APIClient?
    let visibleRows: Int
    var onSelect: ((ReactionPerson) -> Void)?
    @Environment(\.fontScale) private var fontScale

    var body: some View {
        let rowHeight = ReactorListLayout.rowHeight(fontScale: fontScale)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    ReactorRow(person: entry.person, emojis: entry.emojis, client: client, onSelect: onSelect)
                        .frame(height: rowHeight)
                }
            }
        }
        .scrollDisabled(!ReactorListLayout.scrolls(count: entries.count, visibleRows: visibleRows))
        .frame(height: ReactorListLayout.height(visibleRows: visibleRows, rowHeight: rowHeight))
    }
}

struct ReactorRow: View {
    let person: ReactionPerson
    var emojis: [ReactionEmoji] = []
    let client: APIClient?
    var onSelect: ((ReactionPerson) -> Void)?
    @State private var hovering = false

    var body: some View {
        if let onSelect {
            Button { onSelect(person) } label: {
                content
                    .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Theme.hover : .clear).padding(.horizontal, 4))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .pointerStyle(.link)
            .onHover { hovering = $0 }
            .help(ReactionText.viewProfile(person.name))
        } else {
            content
        }
    }

    var content: some View {
        HStack(spacing: 8) {
            Avatar(url: person.avatarURL, client: client, name: person.name, size: ReactorListLayout.avatarSize)
            Text(person.name)
                .scaledFont(12.5, weight: .medium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if person.isMe {
                Text(ReactionText.you)
                    .scaledFont(11.5)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            ForEach(emojis, id: \.name) { emoji in
                EmojiGlyphView(name: emoji.name, glyph: emoji.glyph, customEmojiId: emoji.customEmojiId, client: client, size: 14)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }
}

struct AllReactionsView: View {
    static let width: CGFloat = 320
    static let maxVisibleRows = 12

    let reactions: [ReactionChipModel]
    let client: APIClient?
    @State private var selection: ReactionTab

    init(reactions: [ReactionChipModel], client: APIClient?, selection: ReactionTab = .all) {
        self.reactions = reactions
        self.client = client
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let breakdown = ReactionBreakdown(reactions: reactions)
        let tab = breakdown.resolved(selection)
        let everyone = breakdown.everyone
        VStack(alignment: .leading, spacing: 0) {
            tabBar(breakdown, selected: tab)
            Divider().overlay(Theme.separator)
            ReactorList(
                entries: tab == .all ? everyone : breakdown.entries(for: tab),
                client: client,
                visibleRows: ReactorListLayout.visibleRows(count: everyone.count, limit: Self.maxVisibleRows)
            )
            .id(tab)
            .padding(.vertical, 6)
        }
        .frame(width: Self.width, alignment: .leading)
        .background(Theme.popover)
    }

    func tabBar(_ breakdown: ReactionBreakdown, selected: ReactionTab) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ReactionTabButton(count: breakdown.count(for: .all), isSelected: selected == .all) { selection = .all } label: {
                    Text(ReactionText.allTab).scaledFont(12, weight: .semibold)
                }
                ForEach(reactions) { reaction in
                    let tab = ReactionTab.emoji(reaction.emojiName)
                    ReactionTabButton(count: breakdown.count(for: tab), isSelected: selected == tab) { selection = tab } label: {
                        EmojiGlyphView(name: reaction.emojiName, glyph: reaction.glyph, customEmojiId: reaction.customEmojiId, client: client, size: 15)
                    }
                    .help(":\(reaction.emojiName):")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
    }
}

struct ReactionTabButton<Label: View>: View {
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                label()
                Text("\(count)")
                    .scaledFont(11.5, weight: .semibold)
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? Theme.link : Theme.textSecondary)
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
            .background(Capsule().fill(isSelected ? Theme.reactionMine : Theme.reactionBackground))
            .overlay(Capsule().strokeBorder(isSelected ? Theme.reactionMineBorder : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
    }
}

enum ReactionText {
    static let viewAllTitle = "View All Reactions"
    static let viewAllLink = "View all"
    static let allTab = "All"
    static let you = "(you)"

    static func reactedWith(_ emojiName: String) -> String { "Reacted with :\(emojiName):" }

    static func peopleCount(_ count: Int) -> String { count == 1 ? "1 person reacted" : "\(count) people reacted" }

    static func toggleTitle(isMine: Bool) -> String { isMine ? "Remove Reaction" : "Add Reaction" }

    static func clickHint(isMine: Bool, emojiName: String) -> String {
        isMine ? "Click to remove your reaction" : "Click to react with :\(emojiName):"
    }

    static func viewProfile(_ name: String) -> String { "View profile of \(name)" }
}

enum ReactionTooltip {
    static func text(names: [String], emojiName: String) -> String {
        let list: String
        switch names.count {
        case 0: list = "Nobody"
        case 1: list = names[0]
        case 2...5: list = names.dropLast().joined(separator: ", ") + " and " + names.last!
        default: list = names.prefix(5).joined(separator: ", ") + " and \(names.count - 5) others"
        }
        return "\(list) reacted with :\(emojiName):"
    }
}
