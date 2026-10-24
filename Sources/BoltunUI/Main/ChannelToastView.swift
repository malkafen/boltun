import AppKit
import SwiftUI

struct ChannelToastOverlay: View {
    let model: ChannelToastModel
    let now: Date
    let calendar: Calendar

    var body: some View {
        if let toast = model.visible {
            Group {
                if toast.kind == .scrollToBottom {
                    ScrollToBottomToastButton(onJump: { model.jump() }, onDismiss: { model.dismiss() })
                } else {
                    ChannelToastBar(
                        toast: toast,
                        message: ChannelToastText.message(for: toast, width: model.width, now: now, calendar: calendar),
                        width: model.width,
                        onJump: { model.jump() },
                        onDismiss: { model.dismiss() }
                    )
                }
            }
            .background {
                if toast.kind.dismissesOnEscape {
                    EscapeKeyMonitor { model.escape() }
                }
            }
        }
    }
}

struct ChannelToastBar: View {
    let toast: ChannelToast
    let message: String
    let width: ToastWidth
    let onJump: () -> Void
    let onDismiss: () -> Void
    @State private var hoveringMessage = false
    @State private var hoveringDismiss = false

    var body: some View {
        let history = toast.kind == .history
        HStack(spacing: 0) {
            Button(action: jumpIfActionable) {
                ZStack(alignment: .leading) {
                    Text(message)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                    if toast.showActions {
                        HStack(spacing: 5) {
                            Image(systemName: toast.jumpsUp ? "arrow.up" : "arrow.down")
                            if width.showsActionTitle {
                                Text(toast.actionTitle).lineLimit(1)
                            }
                        }
                        .padding(.leading, 10)
                    }
                }
                .frame(maxHeight: .infinity)
                .background(hoveringMessage && toast.showActions ? Color.black.opacity(0.2) : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringMessage = $0 }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .scaledFont(11, weight: .bold)
                    .frame(width: 32, height: 32)
                    .background(hoveringDismiss ? Color.black.opacity(0.2) : .clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringDismiss = $0 }
            .help(toast.showActions ? "Close (Esc)" : "")
        }
        .scaledFont(13, weight: .bold)
        .foregroundStyle(history ? Theme.toastHistoryText : Color.white)
        .frame(height: 32)
        .background(history ? Theme.toastHistory : Theme.accent)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(.horizontal, 15)
        .padding(.top, 10)
        .transition(.opacity)
    }

    func jumpIfActionable() {
        if toast.showActions { onJump() }
    }
}

struct ScrollToBottomToastButton: View {
    let onJump: () -> Void
    let onDismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onJump) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down")
                    Text("Jump to recents")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .scaledFont(11, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.64))
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .scaledFont(14, weight: .semibold)
        .foregroundStyle(Color.white)
        .padding(4)
        .padding(.leading, 8)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.accent.opacity(hovering ? 0.88 : 1)))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 4)
        .onHover { hovering = $0 }
        .padding(.top, 16)
    }
}

struct EscapeKeyMonitor: NSViewRepresentable {
    static let escapeKeyCode: UInt16 = 53

    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.action = action
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        var action: @MainActor () -> Void = {}
        private(set) weak var view: NSView?
        private var monitor: Any?

        func attach(to view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated { _ = self?.handle(keyCode: event.keyCode, window: event.window) }
                return event
            }
        }

        @discardableResult
        func handle(keyCode: UInt16, window: NSWindow?) -> Bool {
            guard keyCode == EscapeKeyMonitor.escapeKeyCode, let window, window === view?.window else { return false }
            action()
            return true
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
