import BoltunKit
import SwiftUI

struct ReadStatusRowModel: Equatable, Sendable {
    enum Kind: String, Sendable {
        case sent
        case seen
        case partiallySeen
    }

    var kind: Kind
    var tooltip: String

    init(kind: Kind, tooltip: String) {
        self.kind = kind
        self.tooltip = tooltip
    }

    init(state: PostReadState, userName: (String) -> String) {
        switch state {
        case .sent: kind = .sent
        case .seen: kind = .seen
        case .partiallySeen: kind = .partiallySeen
        }
        tooltip = ReadStatusTooltip.text(for: state, userName: userName)
    }

    var checkmarks: Int { kind == .sent ? 1 : 2 }
}

enum ReadStatusTooltip {
    static let maxNames = 3

    static func text(for state: PostReadState, userName: (String) -> String) -> String {
        switch state {
        case .sent:
            return "Sent"
        case .seen:
            return "Seen"
        case .partiallySeen(let seenBy, let total):
            guard seenBy.count <= maxNames else { return "Seen by \(seenBy.count) of \(total)" }
            return "Seen by " + seenBy.map(userName).joined(separator: ", ")
        }
    }
}

enum ReadStatusPlacement {
    static func postIds(posts: [Post], states: [String: PostReadState], myId: String) -> Set<String> {
        guard !states.isEmpty else { return [] }
        var runEnds: [String] = []
        var candidate: String?
        for post in posts {
            if ReadStatus.isOwnMessage(post, myId: myId) {
                if states[post.id] != nil { candidate = post.id }
            } else if let ended = candidate {
                runEnds.append(ended)
                candidate = nil
            }
        }
        if let candidate { runEnds.append(candidate) }
        guard let latest = runEnds.last else { return [] }
        var result = Set(runEnds.filter { states[$0] != .seen })
        result.insert(latest)
        return result
    }
}

struct ReadStatusIndicator: View {
    let model: ReadStatusRowModel

    var body: some View {
        HStack(spacing: -5) {
            ForEach(0..<model.checkmarks, id: \.self) { _ in
                Image(systemName: "checkmark")
            }
        }
        .scaledFont(9.5, weight: .bold)
        .foregroundStyle(model.kind == .seen ? Theme.accent : Theme.textSecondary)
        .help(model.tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.tooltip)
    }
}
