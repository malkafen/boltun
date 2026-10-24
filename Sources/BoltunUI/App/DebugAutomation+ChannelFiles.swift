import BoltunKit
import Foundation

extension AutomationUIState {
    struct ChannelFilesSummary: Codable, Equatable, Sendable {
        struct File: Codable, Equatable, Sendable {
            var id: String
            var name: String
            var kind: String
            var sender: String
            var size: String
            var date: String
            var tag: String?
            var postId: String
            var thumbnail: Bool
        }

        var enabled: Bool
        var open: Bool
        var channelId: String
        var channel: String
        var title: String
        var filter: String
        var filterTitle: String
        var query: String
        var terms: String
        var loading: Bool
        var loadingMore: Bool
        var atEnd: Bool
        var nextPage: Int
        var count: Int
        var empty: String?
        var emptyDetail: String?
        var files: [File]
        var preparingPreviews: [String]
        var quickLook: String?
    }
}

extension DebugAutomation {
    func performChannelFiles(_ command: DebugCommand, workspace: Workspace) async throws -> String {
        let model = workspace.channelFiles
        switch command {
        case .channelFiles(let on):
            if on {
                guard workspace.isChannelFilesEnabled else { throw AutomationError.failed("file attachments disabled") }
                await workspace.showChannelFiles(channelId: try currentChannelId(workspace.session))
            } else if workspace.channelFilesChannelId != nil {
                workspace.closeRightPane()
            }
            return "\(model.files.count)"
        case .channelFilesFilter(let filter):
            try requireChannelFilesPane(workspace)
            await model.select(filter: filter)
            return "\(model.files.count)"
        case .channelFilesSearch(let text):
            try requireChannelFilesPane(workspace)
            model.searchText = text
            if text.isEmpty {
                await model.clearSearch()
            } else {
                await model.submitSearch()
            }
            return "\(model.files.count)"
        case .channelFilesMore:
            try requireChannelFilesPane(workspace)
            await model.loadMore()
            return "\(model.files.count)"
        case .channelFile(let index, let action):
            try requireChannelFilesPane(workspace)
            guard model.files.indices.contains(index) else { throw AutomationError.failed("no file at index \(index)") }
            return try await performChannelFile(model.files[index], action: action, workspace: workspace)
        case .quickLookClose:
            QuickLookPanel.shared.close()
            return ""
        default:
            throw AutomationError.invalidCommand
        }
    }

    private func performChannelFile(_ file: FileInfo, action: DebugCommand.ChannelFileAction, workspace: Workspace) async throws -> String {
        switch action {
        case .preview:
            switch await workspace.previewChannelFile(file) {
            case .sheet: return "image-preview"
            case .quickLook(let url): return "quick-look:\(url.path)"
            case nil: throw AutomationError.failed(workspace.localError ?? "preview failed")
            }
        case .open:
            guard !file.postId.isEmpty else { throw AutomationError.failed("file has no post") }
            await workspace.openInChannel(file)
            return workspace.session.currentChannelId ?? ""
        case .download:
            guard let url = await workspace.download(file) else { throw AutomationError.failed(workspace.localError ?? "download failed") }
            return url.path
        case .copyLink:
            guard !file.postId.isEmpty else { throw AutomationError.failed("file has no post") }
            workspace.copyLink(file)
            return workspace.pasteboard.string(forType: .string) ?? ""
        }
    }

    private func requireChannelFilesPane(_ workspace: Workspace) throws {
        guard workspace.channelFilesChannelId != nil else { throw AutomationError.failed("channel files pane is closed") }
    }

    static func channelFilesSummary(_ workspace: Workspace, quickLook: URL?) -> AutomationUIState.ChannelFilesSummary {
        let model = workspace.channelFiles
        let session = workspace.session
        let channelId = workspace.channelFilesChannelId ?? model.channelId
        let empty = model.emptyState
        return AutomationUIState.ChannelFilesSummary(
            enabled: workspace.isChannelFilesEnabled,
            open: workspace.channelFilesChannelId != nil,
            channelId: channelId,
            channel: session.channels[channelId].map { session.displayName(channel: $0) } ?? "",
            title: model.title,
            filter: model.filter.rawValue,
            filterTitle: model.filter.title,
            query: model.query.trimmedText,
            terms: model.query.terms,
            loading: model.isLoading,
            loadingMore: model.isLoadingMore,
            atEnd: model.isAtEnd,
            nextPage: model.nextPage,
            count: model.files.count,
            empty: empty?.title,
            emptyDetail: empty?.subtitle,
            files: model.files.prefix(40).map { file in
                let row = workspace.channelFileRow(file)
                return AutomationUIState.ChannelFilesSummary.File(
                    id: file.id,
                    name: row.name,
                    kind: row.kind.rawValue,
                    sender: row.sender,
                    size: row.sizeText,
                    date: row.dateText,
                    tag: row.channelTag,
                    postId: file.postId,
                    thumbnail: ChannelFileThumbnail.thumbnailURL(for: file, client: session.client) != nil
                )
            },
            preparingPreviews: workspace.preparingPreviews.sorted(),
            quickLook: quickLook?.path
        )
    }
}
