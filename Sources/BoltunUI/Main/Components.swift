import AppKit
import BoltunKit
import SwiftUI

struct Avatar: View {
    let url: URL?
    let client: APIClient?
    let name: String
    var size: CGFloat = 36
    var status: UserStatusValue?
    var statusRing: Color = Theme.sidebar

    static let pixelSize: CGFloat = 96

    var body: some View {
        RemoteImage(url: url, client: client, maxPixel: Self.pixelSize) {
            InitialsBadge(name: name, size: size)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            if let status {
                StatusDot(status: status, size: max(8, size * 0.36), ring: statusRing)
                    .help(status.title)
                    .offset(x: size > 24 ? 1 : 2, y: size > 24 ? 1 : 2)
            }
        }
    }
}

struct InitialsBadge: View {
    let name: String
    let size: CGFloat

    var body: some View {
        let palette = Theme.avatarPalette
        Circle()
            .fill(palette[Initials.paletteIndex(for: name, count: palette.count)])
            .overlay(
                Text(Initials.of(name).prefix(size < 24 ? 1 : 2))
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

struct StatusDot: View {
    let status: UserStatusValue
    var size: CGFloat = 9
    var ring: Color = Theme.sidebar

    var body: some View {
        ZStack {
            Circle().fill(ring)
            switch status {
            case .online: Circle().fill(Theme.online).padding(1.5)
            case .away: Circle().fill(Theme.away).padding(1.5)
            case .dnd:
                Circle().fill(Theme.dnd).padding(1.5)
                Capsule().fill(ring).frame(width: size * 0.45, height: max(1.5, size * 0.14))
            case .offline: Circle().strokeBorder(Theme.offline, lineWidth: 1.5).padding(1.5)
            }
        }
        .frame(width: size, height: size)
    }
}

extension UserStatusValue {
    static let selectable: [UserStatusValue] = [.online, .away, .dnd, .offline]

    var title: String {
        switch self {
        case .online: return "Online"
        case .away: return "Away"
        case .dnd: return "Do Not Disturb"
        case .offline: return "Offline"
        }
    }
}

struct CountBadge: View {
    let count: Int
    var color: Color = Theme.mentionBadge

    var body: some View {
        Text(BadgeText.count(count))
            .font(.system(size: 10.5, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 16)
            .background(Capsule().fill(color))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty && current.width + spacing + size.width > width {
                rows.append(current)
                current = Row()
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

struct IconButton: View {
    let systemName: String
    var help: String = ""
    var size: CGFloat = 13
    var tint: Color = Theme.textSecondary
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(hovering ? Theme.textPrimary : tint)
                .frame(width: size + 15, height: size + 15)
                .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.white.opacity(0.08) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

struct Banner: View {
    enum Style {
        case error
        case warning
    }

    let style: Style
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: style == .error ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(style == .error ? Theme.errorBanner : Theme.warningBanner)
    }
}

struct ScaledFont: ViewModifier {
    @Environment(\.fontScale) private var scale
    let size: CGFloat
    var weight: Font.Weight = .regular
    var design: Font.Design = .default

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}

struct HiddenShortcut: View {
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let action: () -> Void

    var body: some View {
        Button("", action: action)
            .keyboardShortcut(key, modifiers: modifiers)
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }
}
