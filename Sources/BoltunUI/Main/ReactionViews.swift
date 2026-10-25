import BoltunKit
import SwiftUI

struct ReactionChip: View {
    let reaction: ReactionChipModel
    let client: APIClient?
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
        .hoverCard(value: reaction) { ReactorsCard(reaction: reaction, client: client) }
        .contextMenu { ReactionMenu(reaction: reaction, action: action) }
        .accessibilityLabel(reaction.tooltip)
    }
}

struct ReactionMenu: View {
    let reaction: ReactionChipModel
    let action: () -> Void

    var body: some View {
        Button(ReactionText.toggleTitle(isMine: reaction.isMine), action: action)
        Divider()
        Section(ReactionText.reactedWith(reaction.emojiName)) {
            ForEach(reaction.people) { person in
                Text(person.displayName)
            }
        }
    }
}

struct ReactorsCard: View {
    static let maxPeople = 12

    let reaction: ReactionChipModel
    let client: APIClient?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.separator)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(reaction.people.prefix(Self.maxPeople)) { person in
                    ReactorRow(person: person, client: client)
                }
                if let more = ReactionText.overflow(count: reaction.people.count, shown: Self.maxPeople) {
                    Text(more)
                        .scaledFont(11.5)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 4)
            Divider().overlay(Theme.separator)
            Text(ReactionText.clickHint(isMine: reaction.isMine, emojiName: reaction.emojiName))
                .scaledFont(10.5)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(width: 240, alignment: .leading)
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
}

struct ReactorRow: View {
    let person: ReactionPerson
    let client: APIClient?

    var body: some View {
        HStack(spacing: 8) {
            Avatar(url: person.avatarURL, client: client, name: person.name, size: 20)
            Text(person.name)
                .scaledFont(12.5, weight: .medium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if person.isMe {
                Text("(you)")
                    .scaledFont(11.5)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}

enum ReactionText {
    static func reactedWith(_ emojiName: String) -> String { "Reacted with :\(emojiName):" }

    static func peopleCount(_ count: Int) -> String { count == 1 ? "1 person reacted" : "\(count) people reacted" }

    static func toggleTitle(isMine: Bool) -> String { isMine ? "Remove Reaction" : "Add Reaction" }

    static func clickHint(isMine: Bool, emojiName: String) -> String {
        isMine ? "Click to remove your reaction" : "Click to react with :\(emojiName):"
    }

    static func overflow(count: Int, shown: Int) -> String? {
        count > shown ? "and \(count - shown) more" : nil
    }
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
