import BoltunKit
import Foundation

extension Workspace {
    func perform(_ command: AppCommand, router: AppRouter?) async {
        switch command {
        case .focusQuickSwitcher:
            showQuickSwitcher = true
        case .focusSearch:
            rightPane = .search
        case .toggleThreadPane:
            if rightPane != nil {
                closeRightPane()
            } else {
                rightPane = .search
            }
        case .openThread:
            if let rootId = router?.consumePendingThreadRootId() {
                await openThread(rootId: rootId)
            }
        case .focusComposer, .toggleSidebar, .highlightPost:
            break
        }
    }
}
