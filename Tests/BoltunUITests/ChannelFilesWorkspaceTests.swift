import AppKit
@testable import BoltunKit
import Foundation
import SwiftUI
import Testing
@testable import BoltunUI

@MainActor
@Suite struct ChannelFilesWorkspaceTests {
    static let files = [
        FileInfo(id: "f-doc", postId: "p6", name: "quarterly-report.pdf", extension: "pdf", size: 2_400_000, mimeType: "application/pdf", userId: "bob", channelId: "town", createAt: Fixture.minutes(20)),
        FileInfo(id: "f-img", postId: "p6", name: "screenshot.png", extension: "png", size: 182_000, mimeType: "image/png", hasPreviewImage: true, userId: "bob", channelId: "town", createAt: Fixture.minutes(20)),
        FileInfo(id: "f-svg", postId: "p2", name: "logo.svg", extension: "svg", size: 900, mimeType: "image/svg+xml", userId: "alice", channelId: "town", createAt: Fixture.minutes(1)),
        FileInfo(id: "f-orphan", name: "orphan.txt", extension: "txt", size: 12, createAt: Fixture.minutes(-2000)),
    ]

    static func results(_ files: [FileInfo]) -> FileSearchResults {
        FileSearchResults(order: files.map(\.id), fileInfos: Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) }))
    }

    static func transport(files: [FileInfo] = files) -> RoutedTransport {
        let transport = Fixture.transport()
        transport.on("POST", "teams/t1/files/search", value: results(files))
        transport.on("GET", "files/*") { request in (200, Data("contents of \(request.url?.lastPathComponent ?? "")".utf8)) }
        return transport
    }

    static func workspace(_ transport: RoutedTransport = transport()) -> (Workspace, URL) {
        let workspace = Fixture.workspace(transport: transport)
        let directory = FileManager.default.temporaryDirectory.appending(path: "boltun-tests-\(UUID().uuidString)")
        workspace.previewDirectory = directory.appending(path: "previews")
        workspace.downloadDirectory = directory.appending(path: "downloads")
        return (workspace, directory)
    }

    @Test func togglesPaneForCurrentChannel() async {
        let transport = Self.transport()
        let (workspace, _) = Self.workspace(transport)
        #expect(workspace.isChannelFilesEnabled)
        await workspace.toggleChannelFiles()
        #expect(workspace.rightPane == .channelFiles("town"))
        #expect(workspace.channelFilesChannelId == "town")
        #expect(workspace.channelFiles.files.map(\.id) == Self.files.map(\.id))
        #expect(workspace.channelFiles.isAtEnd)
        #expect(transport.requests("POST", "teams/t1/files/search").last.map(body)?["terms"] as? String == "channel:town")
        await workspace.toggleChannelFiles()
        #expect(workspace.rightPane == nil)
        #expect(workspace.channelFilesChannelId == nil)
    }

    @Test func togglingWithoutChannelDoesNothing() async {
        let (workspace, _) = Self.workspace()
        workspace.session.currentChannelId = nil
        await workspace.toggleChannelFiles()
        #expect(workspace.rightPane == nil)
    }

    @Test func respectsDisabledAttachments() {
        let (workspace, _) = Self.workspace()
        workspace.session.config = ClientConfig(values: ["EnableFileAttachments": "false"])
        #expect(!workspace.isChannelFilesEnabled)
    }

    @Test func replacesOpenThreadAndFollowsChannelSwitches() async {
        let transport = Self.transport()
        transport.on("GET", "posts/p1/thread", value: PostList(order: ["p1"], posts: [:]))
        let (workspace, _) = Self.workspace(transport)
        await workspace.followChannelFiles(to: "secret")
        #expect(workspace.rightPane == nil)
        await workspace.openThread(rootId: "p1")
        await workspace.showChannelFiles(channelId: "town")
        #expect(workspace.rightPane == .channelFiles("town"))
        #expect(workspace.session.threads["p1"] == nil)
        await workspace.followChannelFiles(to: "town")
        await workspace.followChannelFiles(to: nil)
        #expect(transport.requests("POST", "teams/t1/files/search").count == 1)
        await workspace.followChannelFiles(to: "dm-alice")
        #expect(workspace.rightPane == .channelFiles("dm-alice"))
        #expect(transport.requests("POST", "teams/t1/files/search").last.map(body)?["terms"] as? String == "channel:dm-alice")
    }

    @Test func rowModelDescribesFiles() {
        let (workspace, _) = Self.workspace()
        let row = workspace.channelFileRow(Self.files[0])
        #expect(row.name == "quarterly-report.pdf")
        #expect(row.kind == .pdf)
        #expect(row.sizeText == "2 MB")
        #expect(row.dateText == "Today at 7:53 AM")
        #expect(row.details == "2 MB • Today at 7:53 AM")
        #expect(row.channelTag == nil)
        #expect(row.hasPost)
        let orphan = workspace.channelFileRow(Self.files[3])
        #expect(!orphan.hasPost)
        #expect(orphan.details == "12 B • Saturday at 10:13 PM")
        var dm = Self.files[0]
        dm.channelId = "dm-alice"
        #expect(workspace.channelFileRow(dm).channelTag == "Direct Message")
        dm.channelId = "gm"
        #expect(workspace.channelFileRow(dm).channelTag == "Group Message")
    }

    @Test func copiesPermalinkOfTheFilePost() {
        let (workspace, _) = Self.workspace()
        workspace.copyLink(Self.files[0])
        #expect(workspace.pasteboard.string(forType: .string) == "http://mm.test/engineering/pl/p6")
        workspace.pasteboard.clearContents()
        workspace.copyLink(Self.files[3])
        #expect(workspace.pasteboard.string(forType: .string) == nil)
    }

    @Test func opensFilePostInChannel() async {
        let (workspace, _) = Self.workspace()
        await workspace.select(channelId: "secret")
        await workspace.openInChannel(Self.files[2])
        #expect(workspace.session.currentChannelId == "town")
        #expect(workspace.highlightedPostId == "p2")
        await workspace.openInChannel(Self.files[3])
        #expect(workspace.highlightedPostId == "p2")
    }

    @Test func previewsImagesInSheetAndOthersInQuickLook() async throws {
        let transport = Self.transport()
        let (workspace, directory) = Self.workspace(transport)
        defer { try? FileManager.default.removeItem(at: directory) }
        var looked: [URL] = []
        workspace.quickLook = { looked.append($0) }
        #expect(await workspace.previewChannelFile(Self.files[1]) == .sheet)
        #expect(workspace.previewFile?.id == "f-img")
        #expect(looked.isEmpty)
        let result = await workspace.previewChannelFile(Self.files[0])
        let url = try #require(looked.last)
        #expect(result == .quickLook(url))
        #expect(url.lastPathComponent == "quarterly-report.pdf")
        #expect(url.deletingLastPathComponent().lastPathComponent == "f-doc")
        #expect(try String(contentsOf: url, encoding: .utf8) == "contents of f-doc")
        await workspace.previewChannelFile(Self.files[0])
        #expect(looked.count == 2)
        #expect(transport.requests("GET", "files/f-doc").count == 1)
        await workspace.previewChannelFile(Self.files[2])
        #expect(looked.last?.lastPathComponent == "logo.svg")
        #expect(workspace.preparingPreviews.isEmpty)
    }

    @Test func previewFailureIsReported() async {
        let transport = Self.transport()
        transport.on("GET", "files/*", status: 500, json: #"{"id":"x","message":"storage offline","status_code":500}"#)
        let (workspace, _) = Self.workspace(transport)
        var looked: [URL] = []
        workspace.quickLook = { looked.append($0) }
        await workspace.previewChannelFile(Self.files[0])
        #expect(looked.isEmpty)
        #expect(workspace.localError == "Preview failed: storage offline")
    }

    @Test func concurrentPreviewOfSameFileIsIgnored() async {
        let (workspace, directory) = Self.workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        workspace.preparingPreviews.insert("f-doc")
        #expect(await workspace.previewCopy(of: Self.files[0]) == nil)
    }

    @Test func thumbnailsUseThumbnailEndpointOrOriginalGif() {
        let client = APIClient(baseURL: Fixture.serverURL, token: "t", transport: RoutedTransport())
        #expect(ChannelFileThumbnail.thumbnailURL(for: Self.files[1], client: client)?.path == "/api/v4/files/f-img/thumbnail")
        #expect(ChannelFileThumbnail.thumbnailURL(for: Self.files[0], client: client) == nil)
        #expect(ChannelFileThumbnail.thumbnailURL(for: Self.files[2], client: client) == nil)
        let gif = FileInfo(id: "g", name: "a.gif", extension: "gif")
        #expect(ChannelFileThumbnail.thumbnailURL(for: gif, client: client)?.path == "/api/v4/files/g")
        var preview = gif
        preview.hasPreviewImage = true
        #expect(ChannelFileThumbnail.thumbnailURL(for: preview, client: client)?.path == "/api/v4/files/g/thumbnail")
    }

    @Test func everyKindHasAnIcon() {
        let kinds: [FileKind] = [.text, .image, .audio, .video, .spreadsheet, .code, .word, .presentation, .pdf, .patch, .svg, .other]
        #expect(Set(kinds.map { ChannelFileIcon.style(for: $0).symbol }).count >= 10)
    }

    @Test func quickLookDataSourceWithoutItem() {
        let panel = QuickLookPanel()
        #expect(panel.url == nil)
        #expect(panel.numberOfPreviewItems(in: nil) == 0)
        #expect(panel.previewPanel(nil, previewItemAt: 0) == nil)
        #expect(panel.visibleURL == nil)
        panel.close()
        #expect(!AppDelegate().acceptsPreviewPanelControl(nil))
    }
}

@MainActor
@Suite struct ChannelFilesViewTests {
    let size = CGSize(width: 1200, height: 720)

    @Test func rendersPaneWithFiles() async {
        let transport = ChannelFilesWorkspaceTests.transport()
        let (workspace, _) = ChannelFilesWorkspaceTests.workspace(transport)
        await workspace.showChannelFiles(channelId: "town")
        let rep = await MainSnapshot.render(WorkspaceView(workspace: workspace), size: size, name: "channel-files", settle: .milliseconds(600))
        #expect(MainSnapshot.distinctColors(rep) > 8)
        await workspace.channelFiles.select(filter: .code)
        await MainSnapshot.render(WorkspaceView(workspace: workspace), size: size, name: "channel-files-filtered")
    }

    @Test func rendersEmptyLoadingAndSearchStates() async {
        let transport = ChannelFilesWorkspaceTests.transport(files: [])
        let (workspace, _) = ChannelFilesWorkspaceTests.workspace(transport)
        await workspace.showChannelFiles(channelId: "town")
        await MainSnapshot.render(WorkspaceView(workspace: workspace), size: size, name: "channel-files-empty")
        workspace.channelFiles.searchText = "budget"
        await workspace.channelFiles.submitSearch()
        await MainSnapshot.render(WorkspaceView(workspace: workspace), size: size, name: "channel-files-no-results")
        let held = FileFetchRecorder()
        held.holdNext = true
        let model = ChannelFilesModel { await held.fetch($0, $1) }
        let loading = Task { await model.open(channelId: "town") }
        while held.gate == nil { await Task.yield() }
        let rep = await MainSnapshot.render(ChannelFilesPane(workspace: workspace, channelId: "town", model: model).background(Theme.content), size: CGSize(width: 380, height: 400), name: "channel-files-loading")
        #expect(MainSnapshot.distinctColors(rep) > 2)
        held.release()
        await loading.value
    }

    @Test func rendersRowsWithHoverActionsAndTags() async {
        let (workspace, _) = ChannelFilesWorkspaceTests.workspace()
        var dm = ChannelFilesWorkspaceTests.files[0]
        dm.channelId = "dm-alice"
        let view = VStack(spacing: 0) {
            ChannelFileRow(workspace: workspace, file: dm)
            ChannelFileRow(workspace: workspace, file: ChannelFilesWorkspaceTests.files[1])
            ChannelFileActionsMenu(workspace: workspace, file: dm)
            ChannelFilesHeaderButton(active: true) {}
            ChannelFilesHeaderButton(active: false) {}
            ChannelFileIcon(kind: .spreadsheet)
            ChannelFilesEmptyView(state: .noFilteredFiles)
        }
        .background(Theme.content)
        await MainSnapshot.render(view, size: CGSize(width: 380, height: 480), name: "channel-files-rows")
    }
}