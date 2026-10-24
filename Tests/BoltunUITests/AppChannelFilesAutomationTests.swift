import AppKit
@testable import BoltunKit
import Foundation
import Testing
@testable import BoltunUI

@MainActor
struct AppChannelFilesAutomationTests {
    static let files = #"""
    {"order":["f2","f1","f0"],"file_infos":{
      "f1":{"id":"f1","post_id":"p1","user_id":"me","channel_id":"c1","create_at":10,"name":"notes.txt","extension":"txt","size":2048},
      "f2":{"id":"f2","post_id":"p2","user_id":"me","channel_id":"c1","create_at":20,"name":"photo.png","extension":"png","size":4096,"mime_type":"image/png","has_preview_image":true},
      "f0":{"id":"f0","user_id":"me","channel_id":"c1","create_at":5,"name":"orphan.bin","extension":"bin","size":1}
    }}
    """#

    @Test func parsesCommands() {
        func command(_ string: String) -> DebugCommand? { DebugCommand(url: URL(string: "boltun://debug/\(string)")!) }
        #expect(command("channel-files") == .channelFiles(on: true))
        #expect(command("channel-files?on=0") == .channelFiles(on: false))
        #expect(command("channel-files?on=yes") == .channelFiles(on: true))
        #expect(command("channel-files-filter?type=documents") == .channelFilesFilter(.documents))
        #expect(command("channel-files-filter?type=Videos") == .channelFilesFilter(.video))
        #expect(command("channel-files-filter?type=video") == .channelFilesFilter(.video))
        #expect(command("channel-files-filter?type=zip") == nil)
        #expect(command("channel-files-filter") == nil)
        #expect(command("channel-files-search?q=budget%202026") == .channelFilesSearch("budget 2026"))
        #expect(command("channel-files-search") == .channelFilesSearch(""))
        #expect(command("channel-files-more") == .channelFilesMore)
        #expect(command("channel-file?index=2") == .channelFile(index: 2, action: .preview))
        #expect(command("channel-file?index=0&action=open") == .channelFile(index: 0, action: .open))
        #expect(command("channel-file?index=0&action=Download") == .channelFile(index: 0, action: .download))
        #expect(command("channel-file?index=0&action=copy-link") == .channelFile(index: 0, action: .copyLink))
        #expect(command("channel-file?index=0&action=delete") == nil)
        #expect(command("channel-file?index=-1") == nil)
        #expect(command("channel-file") == nil)
        #expect(command("quick-look-close") == .quickLookClose)
    }

    @Test func drivesThePaneFromScripts() async throws {
        let transport = FakeTransport()
        transport.set("POST teams/t1/files/search", Self.files)
        transport.set("GET files/f1", "hello notes")
        let server = Harness.server()
        let harness = Harness(servers: [server], tokens: [server.id: "token"], transport: transport)
        await harness.model.startAll()
        let sink = LogSink()
        let automation = DebugAutomation(router: AppRouter(model: harness.model), host: FakeAutomationHost(), isEnabled: { true }) { sink.lines.append($0) }
        let workspace = try automation.currentWorkspace()
        let directory = FileManager.default.temporaryDirectory.appending(path: "boltun-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        workspace.previewDirectory = directory.appending(path: "previews")
        workspace.downloadDirectory = directory.appending(path: "downloads")
        workspace.revealInFinder = { _ in }
        workspace.pasteboard = NSPasteboard(name: NSPasteboard.Name("boltun-tests-\(UUID().uuidString)"))
        var looked: [URL] = []
        workspace.quickLook = { looked.append($0) }
        func run(_ command: String) async -> String {
            await automation.handle(URL(string: "boltun://debug/\(command)")!)
            return sink.lines.last ?? ""
        }

        #expect(await run("channel-files-more") == "error /channel-files-more channel files pane is closed")
        #expect(await run("channel-files?on=0") == "ok /channel-files 0")
        #expect(await run("channel-files") == "ok /channel-files 3")
        #expect(workspace.rightPane == .channelFiles("c1"))
        #expect(await run("channel-files-filter?type=images") == "ok /channel-files-filter 3")
        let filtered = transport.requests(matching: "POST teams/t1/files/search").last.map(body)?["terms"] as? String
        #expect(filtered?.hasPrefix("channel:c1 ext:png") == true)
        #expect(await run("channel-files-search?q=photo") == "ok /channel-files-search 3")
        #expect(transport.requests(matching: "POST teams/t1/files/search").last.map(body)?["terms"] as? String == "photo channel:c1 ext:png ext:jpg ext:jpeg ext:bmp ext:tiff ext:svg ext:xcf")

        let path = "/tmp/boltun-tests-\(UUID().uuidString)-files.json"
        _ = await run("state?path=\(path)")
        let state = try JSONDecoder().decode(AutomationState.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        try? FileManager.default.removeItem(atPath: path)
        let summary = try #require(state.ui?.channelFiles)
        #expect(state.ui?.rightPane == "channel-files:c1")
        #expect(summary.open)
        #expect(summary.enabled)
        #expect(summary.channel == "Town Square")
        #expect(summary.title == "Search Results")
        #expect(summary.filter == "images")
        #expect(summary.filterTitle == "Images")
        #expect(summary.query == "photo")
        #expect(summary.atEnd)
        #expect(summary.count == 3)
        #expect(summary.empty == nil)
        #expect(summary.files.map(\.name) == ["photo.png", "notes.txt", "orphan.bin"])
        #expect(summary.files[0].thumbnail)
        #expect(summary.files[1].size == "2 KB")
        #expect(summary.files[1].sender == "boltun")
        #expect(summary.files[1].kind == "text")
        #expect(summary.quickLook == nil)

        #expect(await run("channel-files-more") == "ok /channel-files-more 3")
        #expect(await run("channel-file?index=9") == "error /channel-file no file at index 9")
        #expect(await run("channel-file?index=0") == "ok /channel-file image-preview")
        #expect(workspace.previewFile?.id == "f2")
        workspace.previewFile = nil
        let preview = await run("channel-file?index=1&action=preview")
        #expect(preview.hasPrefix("ok /channel-file quick-look:") && preview.hasSuffix("/f1/notes.txt"))
        #expect(looked.last?.lastPathComponent == "notes.txt")
        #expect(await run("channel-file?index=2&action=preview").hasPrefix("error /channel-file Preview failed"))
        #expect(await run("channel-file?index=1&action=copy-link") == "ok /channel-file http://chat.example.com:8065/team-one/pl/p1")
        #expect(await run("channel-file?index=2&action=copy-link") == "error /channel-file file has no post")
        #expect(await run("channel-file?index=2&action=open") == "error /channel-file file has no post")
        let download = await run("channel-file?index=1&action=download")
        #expect(download.hasPrefix("ok /channel-file \(directory.path)") || download.hasPrefix("ok /channel-file /private\(directory.path)"))
        #expect(await run("channel-file?index=2&action=download").hasPrefix("error /channel-file Download failed"))
        #expect(await run("channel-file?index=1&action=open") == "ok /channel-file c1")
        #expect(workspace.highlightedPostId == "p1")
        #expect(await run("channel-files-search") == "ok /channel-files-search 3")
        #expect(workspace.channelFiles.query.text.isEmpty)
        #expect(await run("quick-look-close").hasPrefix("ok /quick-look-close"))
        #expect(await run("channel-files?on=0") == "ok /channel-files 3")
        #expect(workspace.rightPane == nil)
        #expect(await run("channel-files-filter?type=all") == "error /channel-files-filter channel files pane is closed")
        workspace.session.config = ClientConfig(values: ["EnableFileAttachments": "false"])
        #expect(await run("channel-files") == "error /channel-files file attachments disabled")
    }

    @Test func rejectsForeignCommands() async throws {
        let harness = await Harness.connected()
        let automation = DebugAutomation(router: AppRouter(model: harness.model), host: FakeAutomationHost(), isEnabled: { true }) { _ in }
        let workspace = try automation.currentWorkspace()
        await #expect(throws: AutomationError.self) { try await automation.performChannelFiles(.leave, workspace: workspace) }
    }
}
