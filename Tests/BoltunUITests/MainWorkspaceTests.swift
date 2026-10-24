import AppKit
import BoltunMarkup
import Foundation
import Testing
@testable import BoltunKit
@testable import BoltunUI

@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

func body(_ request: URLRequest) -> [String: Any] {
    guard let data = request.httpBody, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
}

@Suite @MainActor struct MainComposerTests {
    func postEcho(_ transport: RoutedTransport) {
        transport.on("POST", "posts") { request in
            let json = body(request)
            let post = Post(id: "new-\(UUID().uuidString.prefix(6))", createAt: Fixture.minutes(50), userId: "me", channelId: json["channel_id"] as? String ?? "", rootId: json["root_id"] as? String ?? "", message: json["message"] as? String ?? "", fileIds: json["file_ids"] as? [String] ?? [])
            return (201, try! MattermostJSON.encoder.encode(post))
        }
    }

    @Test func sendClearsTextAndPosts() async {
        let transport = Fixture.transport()
        postEcho(transport)
        let workspace = Fixture.workspace(transport: transport)
        let composer = workspace.composer(for: ComposerTarget(channelId: "town"))
        #expect(workspace.composer(for: ComposerTarget(channelId: "town")) === composer)
        #expect(!composer.canSend)
        composer.userEdited(text: "  hello world ", cursor: 14)
        #expect(composer.canSend)
        await composer.send()
        #expect(composer.text.isEmpty)
        let sent = transport.requests("POST", "posts")
        #expect(sent.count == 1)
        #expect(body(sent[0])["message"] as? String == "hello world")
        #expect(workspace.session.timelinePosts(channelId: "town").last?.message == "hello world")
    }

    @Test func sendFailureRestoresDraft() async {
        let transport = Fixture.transport()
        transport.on("POST", "posts", status: 500, json: #"{"message":"boom"}"#)
        let workspace = Fixture.workspace(transport: transport)
        let composer = workspace.composer(for: ComposerTarget(channelId: "town"))
        composer.userEdited(text: "draft", cursor: 5)
        #expect(composer.perform(.send))
        #expect(await eventually { workspace.session.lastError != nil && composer.text == "draft" })
        #expect(workspace.visibleError == "boom")
        workspace.dismissError()
        #expect(workspace.visibleError == nil)
    }

    @Test func editLastPostAndSave() async {
        let transport = Fixture.transport()
        transport.on("PUT", "posts/p4/patch") { request in
            var post = Fixture.townPosts()[4]
            post.message = body(request)["message"] as? String ?? ""
            post.editAt = 99
            return (200, try! MattermostJSON.encoder.encode(post))
        }
        let workspace = Fixture.workspace(transport: transport)
        let composer = workspace.composer(for: ComposerTarget(channelId: "town"))
        composer.userEdited(text: "", cursor: 0)
        #expect(composer.keyContext.isEmpty)
        #expect(composer.perform(ComposerKeyRouter.command(for: .up, modifiers: [], context: composer.keyContext)))
        #expect(composer.editingPostId == "p4")
        #expect(composer.text == "Thanks @alice, I'll handle the changelog.")
        composer.userEdited(text: "Updated text", cursor: 12)
        #expect(composer.keyContext.isEditing)
        await composer.send()
        #expect(composer.editingPostId == nil)
        #expect(composer.text.isEmpty)
        #expect(workspace.session.posts["p4"]?.message == "Updated text")
    }

    @Test func editFailureKeepsEditing() async {
        let transport = Fixture.transport()
        transport.on("PUT", "posts/p4/patch", status: 500, json: "{}")
        let workspace = Fixture.workspace(transport: transport)
        let composer = workspace.composer(for: ComposerTarget(channelId: "town"))
        workspace.beginEdit(workspace.session.posts["p4"]!)
        composer.userEdited(text: "changed", cursor: 7)
        await composer.send()
        #expect(composer.editingPostId == "p4")
        #expect(composer.text == "changed")
    }

    @Test func cancelEditRestoresDraft() {
        let workspace = Fixture.workspace()
        let composer = workspace.composer(for: ComposerTarget(channelId: "town"))
        composer.userEdited(text: "my draft", cursor: 8)
        let focus = composer.focusRevision
        composer.beginEditing(workspace.session.posts["p4"]!)
        #expect(composer.focusRevision == focus + 1)
        #expect(composer.perform(.cancelEdit))
        #expect(composer.text == "my draft")
        #expect(composer.editingPostId == nil)
        composer.cancelEdit()
        #expect(composer.text == "my draft")
        #expect(!composer.perform(.passThrough))
        #expect(!composer.perform(.insertNewline))
    }

    @Test func editLastWithoutOwnPosts() {
        let workspace = Fixture.workspace()
        let composer = workspace.composer(for: ComposerTarget(channelId: "offtopic"))
        #expect(!composer.editLastPost())
        #expect(composer.lastOwnPost() == nil)
    }

    @Test func threadComposerEditsOwnReply() {
        let workspace = Fixture.workspace()
        let session = workspace.session
        session.posts["r2"] = Post(id: "r2", createAt: Fixture.minutes(42), userId: "me", channelId: "town", rootId: "p1", message: "my reply")
        var thread = ThreadState(rootId: "p1")
        thread.postIds = ["p1", "p3", "r1", "r2"]
        session.threads["p1"] = thread
        let composer = workspace.composer(for: ComposerTarget(channelId: "town", rootId: "p1"))
        #expect(composer.target.isThread)
        #expect(composer.lastOwnPost()?.id == "r2")
        workspace.rightPane = .thread("p1")
        workspace.beginEdit(session.posts["r2"]!)
        #expect(composer.editingPostId == "r2")
    }

    @Test func userAutocompleteMergesRemote() async {
        let transport = Fixture.transport()
        let dave = User(id: "dave", username: "dave", firstName: "Dave")
        transport.on("GET", "users/autocomplete", json: String(data: try! MattermostJSON.encoder.encode(["users": [Fixture.alice, dave]]), encoding: .utf8)!)
        let workspace = Fixture.workspace(transport: transport)
        let composer = workspace.composer(for: ComposerTarget(channelId: "town"))
        composer.debounce = .milliseconds(1)
        composer.userEdited(text: "hi @", cursor: 4)
        #expect(composer.query?.kind == .user)
        #expect(composer.suggestions.count == 4)
        #expect(await eventually { composer.suggestions.contains { $0.userId == "dave" } })
        #expect(composer.suggestions.filter { $0.userId == "alice" }.count == 1)
        composer.userEdited(text: "hi @a", cursor: 5)
        #expect(composer.suggestions.first?.title == "@alice")
        #expect(composer.suggestions.contains { $0.id == "special:all" })
        #expect(composer.perform(.selectNextSuggestion))
        #expect(composer.selectedIndex == 1)
        #expect(composer.perform(.selectPreviousSuggestion))
        #expect(composer.selectedIndex == 0)
        #expect(composer.perform(.acceptSuggestion))
        #expect(composer.text == "hi @alice ")
        #expect(composer.cursor == 10)
        #expect(!composer.hasSuggestions)
        #expect(!composer.perform(.acceptSuggestion))
    }

    @Test func channelAndEmojiSuggestions() async {
        let transport = Fixture.transport()
        transport.on("GET", "teams/t1/channels/autocomplete", value: [Channel(id: "remote", teamId: "t1", name: "random", displayName: "Random")])
        let workspace = Fixture.workspace(transport: transport)
        workspace.session.customEmojis = ["smirkcat": CustomEmoji(id: "e1", name: "smirkcat")]
        let composer = workspace.composer(for: ComposerTarget(channelId: "town"))
        composer.debounce = .milliseconds(1)
        composer.userEdited(text: "see ~", cursor: 5)
        #expect(composer.suggestions.map(\.replacement).contains("~town-square"))
        #expect(!composer.suggestions.map(\.replacement).contains("~old-stuff"))
        #expect(await eventually { composer.suggestions.contains { $0.replacement == "~random" } })
        composer.userEdited(text: "see ~sec", cursor: 8)
        #expect(composer.suggestions.first?.replacement == "~secret-plans")
        composer.userEdited(text: "nice :sm", cursor: 8)
        #expect(composer.suggestions.contains { $0.id == "emoji:smile" && $0.glyph == "😄" })
        #expect(composer.suggestions.contains { $0.customEmojiId == "e1" })
        #expect(composer.perform(.dismissSuggestions))
        #expect(composer.suggestions.isEmpty)
        composer.userMovedCursor(3)
        #expect(composer.query == nil)
        composer.userMovedCursor(3)
    }

    @Test func limitsAndInsert() {
        let workspace = Fixture.workspace()
        workspace.session.config = ClientConfig(values: ["MaxPostSize": "10"])
        let composer = workspace.composer(for: ComposerTarget(channelId: "town"))
        composer.userEdited(text: "hello", cursor: 2)
        #expect(composer.remaining == 5 && composer.showsLimit && !composer.isOverLimit)
        composer.insert("XY")
        #expect(composer.text == "heXYllo")
        #expect(composer.cursor == 4)
        composer.userEdited(text: "01234567890", cursor: 11)
        #expect(composer.isOverLimit && !composer.canSend)
    }

    @Test func uploadsAttachAndSend() async throws {
        let transport = Fixture.transport()
        postEcho(transport)
        transport.on("POST", "files") { _ in
            (201, Data(#"{"file_infos":[{"id":"file1","name":"note.txt","size":5}]}"#.utf8))
        }
        let workspace = Fixture.workspace(transport: transport)
        let composer = workspace.composer(for: ComposerTarget(channelId: "town"))
        let url = FileManager.default.temporaryDirectory.appending(path: "boltun-note-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        composer.attach(fileURLs: [url, URL(fileURLWithPath: "/nonexistent/file")])
        #expect(composer.uploads.count == 1)
        #expect(composer.isUploading && !composer.canSend)
        #expect(await eventually { composer.uploadedFileIds == ["file1"] })
        #expect(composer.canSend)
        await composer.send()
        #expect(composer.uploads.isEmpty)
        #expect(body(transport.requests("POST", "posts")[0])["file_ids"] as? [String] == ["file1"])
        try? FileManager.default.removeItem(at: url)
    }

    @Test func uploadFailureAndRemoval() async {
        let transport = Fixture.transport()
        transport.on("POST", "files", status: 413, json: #"{"message":"too large"}"#)
        let workspace = Fixture.workspace(transport: transport)
        let composer = workspace.composer(for: ComposerTarget(channelId: "town"))
        composer.attach(data: Data([1, 2, 3]), filename: "a.png")
        #expect(await eventually { composer.uploads.first?.state == .failed })
        #expect(composer.uploads.first?.fileInfo == nil)
        composer.removeUpload(composer.uploads[0].id)
        #expect(composer.uploads.isEmpty)
    }

    @Test func typingNotifiesSession() {
        let workspace = Fixture.workspace()
        let composer = workspace.composer(for: ComposerTarget(channelId: "town"))
        composer.userEdited(text: "a", cursor: 1)
        #expect(workspace.session.lastTypingSent["town"] != nil)
    }

    @Test func mergeDeduplicates() {
        let a = AutocompleteSuggestion(id: "1", kind: .user, title: "", subtitle: "", replacement: "")
        let b = AutocompleteSuggestion(id: "2", kind: .user, title: "", subtitle: "", replacement: "")
        #expect(ComposerState.merge([a], [a, b]).map(\.id) == ["1", "2"])
        #expect(ComposerState.userMatches(Fixture.carol, prefix: "ck"))
        #expect(ComposerState.userMatches(Fixture.carol, prefix: "king"))
        #expect(ComposerState.userMatches(Fixture.carol, prefix: ""))
        #expect(!ComposerState.userMatches(Fixture.carol, prefix: "zed"))
    }
}

@Suite @MainActor struct MainWorkspaceTests {
    @Test func navigationOrderAndMoves() async {
        let workspace = Fixture.workspace()
        #expect(workspace.navigationOrder == ["offtopic", "muted", "secret", "town", "dm-alice", "gm", "dm-bob"])
        await workspace.navigate(offset: 1)
        #expect(workspace.session.currentChannelId == "dm-alice")
        await workspace.navigate(offset: -1)
        #expect(workspace.session.currentChannelId == "town")
        await workspace.navigateUnread(forward: true)
        #expect(workspace.session.currentChannelId == "dm-bob")
        await workspace.navigateUnread(forward: false)
        #expect(["offtopic", "secret"].contains(workspace.session.currentChannelId ?? ""))
    }

    @Test func quickSwitchItemsCoverChannelsAndDirects() {
        let workspace = Fixture.workspace()
        let items = workspace.quickSwitchItems()
        let ids = Set(items.map(\.channelId))
        #expect(ids.contains("town") && ids.contains("dm-alice") && ids.contains("gm"))
        #expect(!ids.contains("old"))
        #expect(!ids.contains("design-general"))
        let alice = items.first { $0.channelId == "dm-alice" }!
        #expect(alice.kind == .direct && alice.subtitle == "@alice" && alice.searchKey == "alice")
        #expect(items.first { $0.channelId == "secret" }?.kind == .private)
        #expect(items.first { $0.channelId == "gm" }?.kind == .group)
        #expect(items.first { $0.channelId == "town" }?.subtitle == "Engineering")
        #expect(items.first { $0.channelId == "offtopic" }?.mentions == 2)
    }

    @Test func linkHandling() async {
        let transport = Fixture.transport()
        transport.on("POST", "channels/direct", value: Fixture.channels()[5])
        transport.on("GET", "channels/dm-alice/members/me", value: Fixture.members()["dm-alice"]!)
        transport.on("POST", "users/usernames", value: [Fixture.carol])
        transport.on("POST", "teams/t1/posts/search", json: #"{"order":[],"posts":{}}"#)
        let workspace = Fixture.workspace(transport: transport)
        var opened: [URL] = []
        workspace.openExternal = { opened.append($0) }
        await workspace.handle(link: URL(string: "https://example.com")!)
        #expect(opened == [URL(string: "https://example.com")!])
        await workspace.handle(link: URL(string: "boltun-channel://secret-plans")!)
        #expect(workspace.session.currentChannelId == "secret")
        await workspace.handle(link: URL(string: "boltun-channel://unknown")!)
        #expect(workspace.session.currentChannelId == "secret")
        await workspace.handle(link: URL(string: "boltun-mention://alice")!)
        #expect(workspace.session.currentChannelId == "dm-alice")
        await workspace.handle(link: URL(string: "boltun-mention://channel")!)
        await workspace.handle(link: URL(string: "boltun-mention://carol2")!)
        #expect(transport.requests("POST", "users/usernames").count == 1)
        await workspace.handle(link: URL(string: "boltun-hashtag://release")!)
        #expect(workspace.searchQuery == "#release")
        #expect(workspace.rightPane == .search)
    }

    @Test func searchAndJump() async {
        let transport = Fixture.transport()
        let found = Post(id: "s1", createAt: Fixture.minutes(3), userId: "alice", channelId: "secret", rootId: "root", message: "found it")
        transport.on("POST", "teams/t1/posts/search", value: PostSearchResults(order: ["s1"], posts: ["s1": found]))
        transport.on("GET", "posts/root/thread", value: PostList(order: ["s1"], posts: ["s1": found]))
        let workspace = Fixture.workspace(transport: transport)
        workspace.searchQuery = "   "
        await workspace.search()
        #expect(workspace.rightPane == nil)
        workspace.searchQuery = "found"
        await workspace.search()
        #expect(workspace.rightPane == .search)
        #expect(workspace.searchResults.map(\.id) == ["s1"])
        #expect(!workspace.isSearching)
        await workspace.jump(to: found)
        #expect(workspace.session.currentChannelId == "secret")
        #expect(workspace.rightPane == .search)
        #expect(workspace.highlightedPostId == "s1")
        #expect(workspace.scrollRequest?.target == .post("s1"))
        await workspace.openThread(rootId: "root")
        workspace.closeRightPane()
        #expect(workspace.rightPane == nil)
        #expect(workspace.session.threads["root"] == nil)
    }

    @Test func replyOpensThreadAndFocusesComposer() async {
        let transport = Fixture.transport()
        let posts = Fixture.townPosts()
        transport.on("GET", "posts/p1/thread", value: PostList(order: ["p1", "p3", "r1"], posts: Dictionary(uniqueKeysWithValues: posts.filter { ["p1", "p3", "r1"].contains($0.id) }.map { ($0.id, $0) })))
        let workspace = Fixture.workspace(transport: transport)
        await workspace.reply(to: posts[3])
        #expect(workspace.threadRootId == "p1")
        #expect(workspace.composer(for: ComposerTarget(channelId: "town", rootId: "p1")).focusRevision == 1)
        #expect(workspace.session.threadPosts(rootId: "p1").map(\.id) == ["p1", "p3", "r1"])
        #expect(workspace.threadItems(rootId: "p1").count == 4)
    }

    @Test func clipboardActions() {
        let workspace = Fixture.workspace()
        let post = workspace.session.posts["p4"]!
        workspace.copyText(post)
        #expect(workspace.pasteboard.string(forType: .string) == post.message)
        workspace.copyLink(post)
        #expect(workspace.pasteboard.string(forType: .string) == "http://mm.test/engineering/pl/p4")
        workspace.copyLink(workspace.session.channels["secret"]!)
        #expect(workspace.pasteboard.string(forType: .string) == "http://mm.test/engineering/channels/secret-plans")
        #expect(workspace.link(for: workspace.session.channels["dm-alice"]!) == "http://mm.test/engineering/channels/alice__me")
    }

    @Test func pinReactDelete() async {
        let transport = Fixture.transport()
        transport.on("POST", "posts/p4/pin", json: #"{"status":"OK"}"#)
        transport.on("POST", "reactions", value: Reaction(userId: "me", postId: "p4", emojiName: "tada", createAt: 5))
        transport.on("DELETE", "posts/p4", json: #"{"status":"OK"}"#)
        let workspace = Fixture.workspace(transport: transport)
        let post = workspace.session.posts["p4"]!
        await workspace.togglePin(post)
        #expect(workspace.session.posts["p4"]?.isPinned == true)
        await workspace.toggleReaction(postId: "p4", emojiName: "tada")
        #expect(workspace.session.posts["p4"]?.metadata.reactions.count == 1)
        #expect(workspace.recentEmojis == ["tada"])
        await workspace.confirmDelete()
        workspace.rightPane = .thread("p4")
        workspace.requestDelete(post)
        #expect(workspace.pendingDeletion?.id == "p4")
        await workspace.confirmDelete()
        #expect(workspace.session.posts["p4"] == nil)
        #expect(workspace.rightPane == nil)
    }

    @Test func recentEmojisAreCapped() {
        let workspace = Fixture.workspace()
        for index in 0..<30 { workspace.recordEmoji("e\(index)") }
        workspace.recordEmoji("e5")
        #expect(workspace.recentEmojis.count == 24)
        #expect(workspace.recentEmojis.first == "e5")
        workspace.recentEmojis = ["+1"]
        let choices = workspace.emojiChoices(query: "")
        #expect(choices.first?.name == "+1")
        #expect(choices.filter { $0.name == "+1" }.count == 1)
        #expect(workspace.emojiChoices(query: "hear").map(\.name).contains("heart"))
        #expect(workspace.emojiChoices(query: "", limit: 3).count == 3)
    }

    @Test func downloadWritesFile() async throws {
        let transport = Fixture.transport()
        transport.on("GET", "files/f-doc", json: "PDFDATA")
        transport.on("GET", "files/broken", status: 500, json: "{}")
        let workspace = Fixture.workspace(transport: transport)
        let directory = FileManager.default.temporaryDirectory.appending(path: "boltun-dl-\(UUID().uuidString)")
        workspace.downloadDirectory = directory
        var revealed: [URL] = []
        workspace.revealInFinder = { revealed.append($0) }
        let file = FileInfo(id: "f-doc", name: "report.pdf", extension: "pdf")
        let first = await workspace.download(file)
        let second = await workspace.download(file)
        #expect(first?.lastPathComponent == "report.pdf")
        #expect(second?.lastPathComponent == "report (1).pdf")
        #expect(try String(contentsOf: first!, encoding: .utf8) == "PDFDATA")
        #expect(revealed.count == 2)
        #expect(workspace.downloading.isEmpty)
        #expect(await workspace.download(FileInfo(id: "broken", name: "x")) == nil)
        #expect(workspace.localError?.hasPrefix("Download failed") == true)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func memberCountsAndMarkup() async {
        let workspace = Fixture.workspace()
        await workspace.loadMemberCount(channelId: "town")
        #expect(workspace.memberCounts["town"] == 42)
        await workspace.loadMemberCount(channelId: "dm-alice")
        #expect(workspace.memberCounts["dm-alice"] == nil)
        let context = workspace.markupContext()
        #expect(context.myUsername == "boltun")
        #expect(context.mentionKeys == ["boltun", "deploy"])
        #expect(context.channelDisplayNames["town-square"] != nil)
        #expect(context.serverURL == Fixture.serverURL)
        #expect(workspace.mentionKeys == ["boltun", "deploy"])
        workspace.session.customEmojis["x"] = CustomEmoji(id: "x", name: "x")
        #expect(workspace.markupContext().customEmojiNames == ["x"])
    }

    @Test func renderCacheReusesBlocks() {
        let cache = RenderCache()
        let post = Fixture.townPosts()[1]
        _ = cache.blocks(for: post, context: MarkupContext())
        _ = cache.blocks(for: post, context: MarkupContext())
        #expect(cache.renders == 1)
        var edited = post
        edited.message = "changed"
        _ = cache.blocks(for: edited, context: MarkupContext())
        #expect(cache.renders == 2)
        let workspace = Fixture.workspace()
        _ = workspace.channelItems(channelId: "town")
        let renders = workspace.renderCache.renders
        _ = workspace.channelItems(channelId: "town")
        #expect(workspace.renderCache.renders == renders)
        #expect(workspace.channelItems(channelId: "nothing").isEmpty)
    }

    @Test func closeConversationHidesDirect() async {
        let workspace = Fixture.workspace()
        await workspace.select(channelId: "dm-alice")
        await workspace.closeConversation(channelId: "dm-alice")
        #expect(workspace.session.hiddenDirectChannelIds.contains("dm-alice"))
        #expect(workspace.session.currentChannelId != "dm-alice")
        await workspace.closeConversation(channelId: "gm")
        #expect(workspace.session.hiddenDirectChannelIds.contains("gm"))
        await workspace.closeConversation(channelId: "missing")
    }

    @Test func registryReusesWorkspaces() {
        let registry = WorkspaceRegistry()
        let session = Fixture.session()
        let first = registry.workspace(for: session, serverURL: Fixture.serverURL)
        #expect(registry.workspace(for: session, serverURL: Fixture.serverURL) === first)
        #expect(registry.workspace(for: session, serverURL: URL(string: "http://other")!) !== first)
        #expect(registry.count == 1)
    }

    @Test func imageStoreCachesAndAuthorizes() async {
        let store = ImageStore(costLimit: 1 << 20)
        let client = APIClient(baseURL: URL(string: "http://mm.test")!, token: "t")
        #expect(ImageStore.authorizedClient(for: URL(string: "http://mm.test/api/v4/users/x/image")!, client: client) != nil)
        #expect(ImageStore.authorizedClient(for: URL(string: "http://evil.test/x.png")!, client: client) == nil)
        #expect(ImageStore.authorizedClient(for: URL(string: "http://mm.test:8080/x.png")!, client: client) == nil)
        #expect(ImageStore.authorizedClient(for: URL(string: "http://mm.test/x.png")!, client: nil) == nil)
        let counter = Counter()
        store.fetcher = { url, client in
            counter.increment()
            if url.lastPathComponent == "bad" { throw APIError.invalidResponse }
            return TestImages.png(seed: url.absoluteString, size: 32)
        }
        let url = URL(string: "http://mm.test/a.png")!
        async let first = store.image(for: url, client: client, maxPixel: 16)
        async let second = store.image(for: url, client: client, maxPixel: 16)
        let (a, b) = await (first, second)
        #expect(a != nil && b != nil)
        #expect(counter.value == 1)
        #expect(store.cached(url, maxPixel: 16)?.size.width == 16)
        _ = await store.image(for: url, client: client, maxPixel: 16)
        #expect(counter.value == 1)
        let bad = URL(string: "http://mm.test/bad")!
        #expect(await store.image(for: bad, client: client, maxPixel: 16) == nil)
        #expect(await store.image(for: bad, client: client, maxPixel: 16) == nil)
        #expect(counter.value == 2)
        store.removeAll()
        #expect(store.cached(url, maxPixel: 16) == nil)
        #expect(ImageDecoder.decode(Data([0, 1, 2]), maxPixel: 10) == nil)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
