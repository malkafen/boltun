import AppKit
import Quartz
import Synchronization

@MainActor
final class QuickLookPanel: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPanel()

    private let current = Mutex<URL?>(nil)

    nonisolated var url: URL? { current.withLock { $0 } }

    var visibleURL: URL? {
        guard QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared()?.isVisible == true else { return nil }
        return url
    }

    func preview(_ url: URL) {
        current.withLock { $0 = url }
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        panel.orderOut(nil)
    }

    func attach(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    func detach(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        url.map { $0 as NSURL }
    }
}
