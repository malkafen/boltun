import AppKit
import SwiftUI

enum HoverCardPlacement {
    static let gap: CGFloat = 6
    static let margin: CGFloat = 4

    static func frame(size: CGSize, anchor: CGRect, visible: CGRect) -> CGRect {
        let maxX = max(visible.minX + margin, visible.maxX - size.width - margin)
        let x = min(max(anchor.minX, visible.minX + margin), maxX)
        let above = anchor.maxY + gap
        let below = anchor.minY - gap - size.height
        let y = above + size.height <= visible.maxY || below < visible.minY ? above : below
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

@MainActor
final class HoverCardAnchor {
    weak var view: NSView?

    var screenRect: CGRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }

    var visibleFrame: CGRect? { view?.window?.screen?.visibleFrame }
}

struct HoverCardAnchorView: NSViewRepresentable {
    let anchor: HoverCardAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

@MainActor
final class HoverCardPanel {
    static let shared = HoverCardPanel()

    private(set) var owner: UUID?
    private var anchor: CGRect = .zero
    private var visible: CGRect = .zero
    private let hosting = NSHostingView(rootView: AnyView(EmptyView()))
    private lazy var panel = makePanel()

    var isVisible: Bool { owner != nil }
    var frame: CGRect { panel.frame }

    func show(_ content: some View, owner: UUID, anchor: CGRect, visible: CGRect?) {
        self.owner = owner
        self.anchor = anchor
        self.visible = visible ?? NSScreen.main?.visibleFrame ?? CGRect(origin: .zero, size: CGSize(width: 10_000, height: 10_000))
        present(content)
        panel.orderFrontRegardless()
    }

    func update(_ content: some View, owner: UUID) {
        guard self.owner == owner else { return }
        present(content)
    }

    private func present(_ content: some View) {
        hosting.rootView = AnyView(content.preferredColorScheme(.dark))
        panel.setFrame(HoverCardPlacement.frame(size: hosting.fittingSize, anchor: anchor, visible: visible), display: true)
    }

    func hide(owner: UUID) {
        guard self.owner == owner else { return }
        panel.orderOut(nil)
        hosting.rootView = AnyView(EmptyView())
        self.owner = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = hosting
        return panel
    }
}

struct HoverCardModifier<Value: Equatable, Card: View>: ViewModifier {
    static var delay: Duration { .milliseconds(350) }

    let value: Value
    let card: () -> Card
    @Environment(\.fontScale) private var fontScale
    @State private var owner = UUID()
    @State private var anchor = HoverCardAnchor()
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .background(HoverCardAnchorView(anchor: anchor))
            .onHover { inside in inside ? schedule() : dismiss() }
            .onDisappear(perform: dismiss)
            .onChange(of: value) { HoverCardPanel.shared.update(styledCard, owner: owner) }
    }

    private var styledCard: some View {
        card().environment(\.fontScale, fontScale)
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled, let rect = anchor.screenRect else { return }
            HoverCardPanel.shared.show(styledCard, owner: owner, anchor: rect, visible: anchor.visibleFrame)
        }
    }

    private func dismiss() {
        pending?.cancel()
        pending = nil
        HoverCardPanel.shared.hide(owner: owner)
    }
}

extension View {
    func hoverCard<Value: Equatable, Card: View>(value: Value, @ViewBuilder card: @escaping () -> Card) -> some View {
        modifier(HoverCardModifier(value: value, card: card))
    }
}
