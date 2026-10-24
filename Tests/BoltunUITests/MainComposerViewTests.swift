import AppKit
import SwiftUI
import Testing
@testable import BoltunKit
@testable import BoltunUI

@MainActor
func findSubview<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let match = view as? T { return match }
    for child in view.subviews {
        if let match = findSubview(type, in: child) { return match }
    }
    return nil
}

@Suite(.serialized) @MainActor struct MainComposerViewTests {
    func makeCoordinator() -> (ComposerState, ComposerTextView.Coordinator, ComposerNSTextView) {
        let workspace = Fixture.workspace()
        let state = workspace.composer(for: ComposerTarget(channelId: "town"))
        let coordinator = ComposerTextView.Coordinator(state: state)
        let textView = ComposerNSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        textView.delegate = coordinator
        coordinator.textView = textView
        return (state, coordinator, textView)
    }

    func type(_ text: String, into textView: NSTextView, coordinator: ComposerTextView.Coordinator) {
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification))
    }

    @Test func coordinatorRoutesKeys() {
        let (state, coordinator, textView) = makeCoordinator()
        type("hi @", into: textView, coordinator: coordinator)
        #expect(state.text == "hi @")
        #expect(state.hasSuggestions)
        #expect(coordinator.textView(textView, doCommandBy: #selector(NSResponder.moveDown(_:))))
        #expect(state.selectedIndex == 1)
        #expect(coordinator.textView(textView, doCommandBy: #selector(NSResponder.moveUp(_:))))
        #expect(coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:))))
        #expect(state.text == "hi @alice ")
        #expect(coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))))
        #expect(textView.string.hasSuffix("\n"))
        #expect(!coordinator.textView(textView, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        #expect(!coordinator.textView(textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
        #expect(state.cursor == 1)
        coordinator.isApplying = true
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
        coordinator.isApplying = false
        type("", into: textView, coordinator: coordinator)
        #expect(coordinator.textView(textView, doCommandBy: #selector(NSResponder.moveUp(_:))))
        #expect(state.editingPostId == "p4")
        #expect(coordinator.textView(textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(state.editingPostId == nil)
    }

    @Test func coordinatorGrowsHeight() {
        let (state, coordinator, textView) = makeCoordinator()
        type("one", into: textView, coordinator: coordinator)
        let single = state.editorHeight
        type((1...8).map { "line \($0)" }.joined(separator: "\n"), into: textView, coordinator: coordinator)
        #expect(state.editorHeight > single)
        type((1...80).map { "line \($0)" }.joined(separator: "\n"), into: textView, coordinator: coordinator)
        #expect(state.editorHeight == ComposerTextView.maxHeight)
    }

    @Test func pasteRoutesFilesImagesAndText() {
        let (_, _, textView) = makeCoordinator()
        let board = NSPasteboard(name: NSPasteboard.Name("boltun-composer-\(UUID().uuidString)"))
        textView.pasteboard = board
        var files: [URL] = []
        var images: [Data] = []
        textView.onFiles = { files = $0 }
        textView.onImage = { images.append($0) }
        board.clearContents()
        board.writeObjects([URL(fileURLWithPath: "/tmp/a.txt") as NSURL])
        textView.paste(nil)
        #expect(files == [URL(fileURLWithPath: "/tmp/a.txt")])
        board.clearContents()
        board.setData(TestImages.png(seed: "p", size: 4), forType: .png)
        textView.paste(nil)
        #expect(images.count == 1)
        board.clearContents()
        board.setString("plain", forType: .string)
        textView.paste(nil)
        #expect(textView.string == "plain")
    }

    @Test func representableAppliesProgrammaticChanges() async {
        let workspace = Fixture.workspace()
        let state = workspace.composer(for: ComposerTarget(channelId: "town"))
        let hosting = NSHostingView(rootView: ComposerView(state: state, workspace: workspace, placeholder: "Write").frame(width: 600, height: 140))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 140), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        Snapshot.pump(0.1)
        let textView = findSubview(ComposerNSTextView.self, in: hosting)
        #expect(textView != nil)
        state.replaceText("programmatic", cursor: 4)
        state.requestFocus()
        for _ in 0..<10 {
            Snapshot.pump(0.02)
            try? await Task.sleep(for: .milliseconds(5))
            hosting.layoutSubtreeIfNeeded()
        }
        #expect(textView?.string == "programmatic")
        #expect(textView?.selectedRange().location == 4)
        textView?.onImage?(TestImages.png(seed: "x", size: 2))
        textView?.onFiles?([URL(fileURLWithPath: "/nonexistent")])
        #expect(state.uploads.count == 1)
        window.contentView = nil
        window.close()
    }
}
