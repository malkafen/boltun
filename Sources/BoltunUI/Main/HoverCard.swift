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

struct HoverCardHoverState: Equatable {
    enum Action: Equatable {
        case keep
        case hideNow
        case hideAfterGrace
    }

    var interactive = false
    var overAnchor = false
    var overCard = false

    var isHovered: Bool { overAnchor || (interactive && overCard) }

    var action: Action {
        if isHovered { return .keep }
        return interactive ? .hideAfterGrace : .hideNow
    }

    mutating func pointer(overAnchor inside: Bool) -> Action {
        overAnchor = inside
        return action
    }

    mutating func pointer(overCard inside: Bool) -> Action {
        overCard = inside
        return action
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

final class HoverCardHostingView: NSHostingView<AnyView> {
    var onPointerInside: ((Bool) -> Void)?
    private lazy var pointerArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if !trackingAreas.contains(pointerArea) { addTrackingArea(pointerArea) }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea === pointerArea { onPointerInside?(true) }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === pointerArea { onPointerInside?(false) }
    }
}

@MainActor
final class HoverCardPanel {
    static let shared = HoverCardPanel()
    static let grace: Duration = .milliseconds(250)

    private(set) var owner: UUID?
    private(set) var hover = HoverCardHoverState()
    private(set) var pendingHide: Task<Void, Never>?
    private let grace: Duration
    private var anchor: CGRect = .zero
    private var visible: CGRect = .zero
    private let hosting = HoverCardHostingView(rootView: AnyView(EmptyView()))
    private lazy var panel = makePanel()

    init(grace: Duration = HoverCardPanel.grace) {
        self.grace = grace
        hosting.onPointerInside = { [weak self] inside in self?.pointer(overCard: inside) }
    }

    var isVisible: Bool { owner != nil }
    var isInteractive: Bool { !panel.ignoresMouseEvents }
    var frame: CGRect { panel.frame }

    func show(_ content: some View, owner: UUID, anchor: CGRect, visible: CGRect?, interactive: Bool = false) {
        cancelPendingHide()
        self.owner = owner
        self.anchor = anchor
        self.visible = visible ?? NSScreen.main?.visibleFrame ?? CGRect(origin: .zero, size: CGSize(width: 10_000, height: 10_000))
        hover = HoverCardHoverState(interactive: interactive, overAnchor: true)
        panel.ignoresMouseEvents = !interactive
        present(content)
        panel.orderFrontRegardless()
    }

    func update(_ content: some View, owner: UUID) {
        guard self.owner == owner else { return }
        present(content)
    }

    func pointer(overAnchor inside: Bool, owner: UUID) {
        guard self.owner == owner else { return }
        apply(hover.pointer(overAnchor: inside))
    }

    func pointer(overCard inside: Bool) {
        guard owner != nil else { return }
        apply(hover.pointer(overCard: inside))
    }

    func hide(owner: UUID) {
        guard self.owner == owner else { return }
        cancelPendingHide()
        panel.orderOut(nil)
        panel.ignoresMouseEvents = true
        hosting.rootView = AnyView(EmptyView())
        self.owner = nil
        hover = HoverCardHoverState()
    }

    func close() {
        guard let owner else { return }
        hide(owner: owner)
    }

    private func present(_ content: some View) {
        hosting.rootView = AnyView(content.preferredColorScheme(.dark))
        panel.setFrame(HoverCardPlacement.frame(size: hosting.fittingSize, anchor: anchor, visible: visible), display: true)
    }

    private func apply(_ action: HoverCardHoverState.Action) {
        switch action {
        case .keep: cancelPendingHide()
        case .hideNow: close()
        case .hideAfterGrace: scheduleHide()
        }
    }

    private func scheduleHide() {
        guard pendingHide == nil, let owner else { return }
        let grace = grace
        pendingHide = Task { @MainActor [weak self] in
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled else { return }
            self?.hideIfIdle(owner: owner)
        }
    }

    private func hideIfIdle(owner: UUID) {
        pendingHide = nil
        guard !hover.isHovered else { return }
        hide(owner: owner)
    }

    private func cancelPendingHide() {
        pendingHide?.cancel()
        pendingHide = nil
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
    var interactive = false
    let card: () -> Card
    @Environment(\.fontScale) private var fontScale
    @State private var owner = UUID()
    @State private var anchor = HoverCardAnchor()
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .background(HoverCardAnchorView(anchor: anchor))
            .onHover { inside in inside ? enter() : leave() }
            .onDisappear(perform: dismiss)
            .onChange(of: value) { HoverCardPanel.shared.update(styledCard, owner: owner) }
    }

    private var styledCard: some View {
        card().environment(\.fontScale, fontScale)
    }

    private func enter() {
        if HoverCardPanel.shared.owner == owner {
            HoverCardPanel.shared.pointer(overAnchor: true, owner: owner)
        } else {
            schedule()
        }
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled, let rect = anchor.screenRect else { return }
            HoverCardPanel.shared.show(styledCard, owner: owner, anchor: rect, visible: anchor.visibleFrame, interactive: interactive)
        }
    }

    private func leave() {
        cancelPending()
        HoverCardPanel.shared.pointer(overAnchor: false, owner: owner)
    }

    private func dismiss() {
        cancelPending()
        HoverCardPanel.shared.hide(owner: owner)
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }
}

extension View {
    func hoverCard<Value: Equatable, Card: View>(value: Value, interactive: Bool = false, @ViewBuilder card: @escaping () -> Card) -> some View {
        modifier(HoverCardModifier(value: value, interactive: interactive, card: card))
    }
}
