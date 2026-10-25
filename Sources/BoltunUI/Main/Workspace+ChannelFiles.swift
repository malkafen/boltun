import BoltunKit
import Foundation

enum ChannelFilePreview: Equatable {
    case sheet
    case quickLook(URL)
}

extension Workspace {
    var channelFilesChannelId: String? {
        if case .channelFiles(let channelId) = rightPane { return channelId }
        return nil
    }

    var isChannelFilesEnabled: Bool { session.config.enableFileAttachments }

    func toggleChannelFiles() async {
        if channelFilesChannelId != nil {
            closeRightPane()
            return
        }
        guard let channelId = session.currentChannelId else { return }
        await showChannelFiles(channelId: channelId)
    }

    func showChannelFiles(channelId: String) async {
        if threadRootId != nil { closeRightPane() }
        rightPane = .channelFiles(channelId)
        await channelFiles.open(channelId: channelId)
    }

    func followChannelFiles(to channelId: String?) async {
        guard let current = channelFilesChannelId, let channelId, channelId != current else { return }
        await showChannelFiles(channelId: channelId)
    }

    func channelFileRow(_ file: FileInfo) -> ChannelFileRowModel {
        ChannelFileRowModel(file: file, session: session, now: now(), calendar: calendar)
    }

    func link(for file: FileInfo) -> String {
        Permalink.post(server: serverURL, teamName: currentTeamName, postId: file.postId)
    }

    func copyLink(_ file: FileInfo) {
        guard !file.postId.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(link(for: file), forType: .string)
    }

    func openInChannel(_ file: FileInfo) async {
        guard !file.postId.isEmpty, let post = await session.openPermalink(postId: file.postId) else { return }
        await highlight(postId: post.id)
    }

    @discardableResult
    func previewChannelFile(_ file: FileInfo) async -> ChannelFilePreview? {
        if file.isImage && file.kind != .svg {
            previewImage(file, in: channelFiles.files)
            return .sheet
        }
        guard let url = await previewCopy(of: file) else { return nil }
        quickLook(url)
        return .quickLook(url)
    }

    @discardableResult
    func previewCopy(of file: FileInfo) async -> URL? {
        let folder = previewDirectory.appending(path: file.id)
        let destination = DownloadDestination.uniqueURL(in: folder, filename: file.name) { _ in false }
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        guard !preparingPreviews.contains(file.id) else { return nil }
        preparingPreviews.insert(file.id)
        defer { preparingPreviews.remove(file.id) }
        do {
            let data = try await session.client.data(at: session.client.fileURL(id: file.id))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            localError = "Preview failed: \(APIError.wrap(error).localizedDescription)"
            return nil
        }
    }
}
