import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ComposerKeyMapper {
    static func key(for selector: Selector) -> ComposerKey? {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), #selector(NSResponder.insertLineBreak(_:)):
            return .enter
        case #selector(NSResponder.moveUp(_:)): return .up
        case #selector(NSResponder.moveDown(_:)): return .down
        case #selector(NSResponder.insertTab(_:)): return .tab
        case #selector(NSResponder.cancelOperation(_:)): return .escape
        default: return nil
        }
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> ComposerKeyModifiers {
        var result: ComposerKeyModifiers = []
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }

    static func modifiers(for selector: Selector, flags: NSEvent.ModifierFlags) -> ComposerKeyModifiers {
        var result = modifiers(flags)
        if selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) { result.insert(.option) }
        if selector == #selector(NSResponder.insertLineBreak(_:)) { result.insert(.control) }
        return result
    }
}

enum PasteContent: Equatable {
    case files([URL])
    case image(Data)
    case text
}

enum PasteboardReader {
    static func content(of pasteboard: NSPasteboard) -> PasteContent {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return .files(urls)
        }
        if pasteboard.string(forType: .string) == nil {
            if let png = pasteboard.data(forType: .png) { return .image(png) }
            if let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                return .image(png)
            }
        }
        return .text
    }
}

final class ComposerNSTextView: NSTextView {
    var onFiles: (([URL]) -> Void)?
    var onImage: ((Data) -> Void)?

    override func paste(_ sender: Any?) {
        switch PasteboardReader.content(of: .general) {
        case .files(let urls): onFiles?(urls)
        case .image(let data): onImage?(data)
        case .text: pasteAsPlainText(sender)
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if case .files(let urls) = PasteboardReader.content(of: sender.draggingPasteboard) {
            onFiles?(urls)
            return true
        }
        return super.performDragOperation(sender)
    }
}

struct ComposerTextView: NSViewRepresentable {
    let state: ComposerState
    var fontSize: CGFloat = 13.5

    static let minHeight: CGFloat = 20
    static let maxHeight: CGFloat = 220

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        let textView = ComposerNSTextView(frame: .zero)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = NSColor.white.withAlphaComponent(0.92)
        textView.insertionPointColor = .white
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.string = state.text
        let state = state
        textView.onFiles = { urls in state.attach(fileURLs: urls) }
        textView.onImage = { data in state.attach(data: data, filename: "Pasted image.png", mimeType: "image/png") }
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.appliedRevision = state.textRevision
        context.coordinator.appliedFocus = state.focusRevision
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            context.coordinator.updateHeight()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let textView = coordinator.textView else { return }
        if coordinator.appliedRevision != state.textRevision {
            coordinator.appliedRevision = state.textRevision
            coordinator.isApplying = true
            textView.string = state.text
            let length = (state.text as NSString).length
            textView.setSelectedRange(NSRange(location: min(state.cursor, length), length: 0))
            coordinator.isApplying = false
            coordinator.updateHeight()
        }
        if coordinator.appliedFocus != state.focusRevision {
            coordinator.appliedFocus = state.focusRevision
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let state: ComposerState
        weak var textView: ComposerNSTextView?
        var appliedRevision = 0
        var appliedFocus = 0
        var isApplying = false

        init(state: ComposerState) {
            self.state = state
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplying, let textView else { return }
            state.userEdited(text: textView.string, cursor: textView.selectedRange().location)
            appliedRevision = state.textRevision
            updateHeight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplying, let textView else { return }
            state.userMovedCursor(textView.selectedRange().location)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let key = ComposerKeyMapper.key(for: selector) else { return false }
            let modifiers = ComposerKeyMapper.modifiers(for: selector, flags: NSApp.currentEvent?.modifierFlags ?? [])
            let command = ComposerKeyRouter.command(for: key, modifiers: modifiers, context: state.keyContext)
            if command == .insertNewline {
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            return state.perform(command)
        }

        func updateHeight() {
            guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height
            let height = min(ComposerTextView.maxHeight, max(ComposerTextView.minHeight, ceil(used)))
            if abs(state.editorHeight - height) > 0.5 { state.editorHeight = height }
        }
    }
}
