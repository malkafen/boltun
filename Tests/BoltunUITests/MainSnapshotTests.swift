import AppKit
import BoltunMarkup
import SwiftUI
import Testing
@testable import BoltunKit
@testable import BoltunUI

@Suite(.serialized)
@MainActor
struct MainSnapshotTests {
    let size = CGSize(width: 1280, height: 800)

    func threadTransport() -> RoutedTransport {
        let transport = Fixture.transport()
        let posts = Fixture.townPosts().filter { ["p1", "p3", "r1"].contains($0.id) }
        transport.on("GET", "posts/p1/thread", value: PostList(order: posts.map(\.id), posts: Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })))
        return transport
    }

    @Test func mainWindowWithMockData() async {
        let (model, _) = Fixture.appModel()
        let rep = await Snapshot.render(MainView(model: model), size: size, name: "main-mock", settle: .milliseconds(900))
        #expect(rep.pixelsWide >= 1280)
        #expect(Snapshot.distinctColors(rep) > 12)
    }

    @Test func workspaceWithThreadPane() async {
        let workspace = Fixture.workspace(transport: threadTransport())
        await workspace.openThread(rootId: "p1")
        workspace.composer(for: ComposerTarget(channelId: "town", rootId: "p1")).userEdited(text: "Sounds good", cursor: 11)
        workspace.session.typing["town"] = ["alice": Date(), "bob": Date()]
        workspace.session.typing["town:p1"] = ["carol": Date()]
        let rep = await Snapshot.render(WorkspaceView(workspace: workspace), size: size, name: "thread-pane", settle: .milliseconds(700))
        #expect(Snapshot.distinctColors(rep) > 10)
    }

    @Test func workspaceWithSearchResults() async {
        let transport = Fixture.transport()
        let results = Fixture.townPosts().filter { ["p2", "p8"].contains($0.id) }
        transport.on("POST", "teams/t1/posts/search", value: PostSearchResults(order: results.map(\.id), posts: Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })))
        let workspace = Fixture.workspace(transport: transport)
        workspace.searchQuery = "release"
        await workspace.search()
        await Snapshot.render(WorkspaceView(workspace: workspace), size: size, name: "search-pane", settle: .milliseconds(500))
        workspace.searchResults = []
        await Snapshot.render(WorkspaceView(workspace: workspace), size: CGSize(width: 1100, height: 500), name: "search-empty")
        workspace.isSearching = true
        await Snapshot.render(WorkspaceView(workspace: workspace), size: CGSize(width: 1100, height: 500))
    }

    @Test func quickSwitcherOverlay() async {
        let workspace = Fixture.workspace()
        workspace.showQuickSwitcher = true
        let rep = await Snapshot.render(WorkspaceView(workspace: workspace), size: size, name: "quick-switcher", settle: .milliseconds(500))
        #expect(Snapshot.distinctColors(rep) > 8)
    }

    @Test func composerStates() async {
        let workspace = Fixture.workspace()
        let composer = workspace.composer(for: ComposerTarget(channelId: "town"))
        composer.userEdited(text: "hey @", cursor: 5)
        composer.uploads = [
            PendingUpload(filename: "design-v2.sketch", size: 4_200_000, state: .uploading),
            PendingUpload(filename: "notes.txt", size: 1200, state: .uploaded(FileInfo(id: "f", name: "notes.txt"))),
            PendingUpload(filename: "huge.mov", size: 1, state: .failed),
        ]
        await Snapshot.render(WorkspaceView(workspace: workspace), size: size, name: "composer-autocomplete", settle: .milliseconds(500))
        composer.clearSuggestions()
        composer.uploads = []
        workspace.beginEdit(workspace.session.posts["p4"]!)
        workspace.session.config = ClientConfig(values: ["MaxPostSize": "50"])
        await Snapshot.render(
            ComposerView(state: composer, workspace: workspace, placeholder: "Write").frame(width: 700).background(Theme.content),
            size: CGSize(width: 700, height: 160), name: "composer-editing"
        )
        composer.userEdited(text: "~", cursor: 1)
        await Snapshot.render(ComposerView(state: composer, workspace: workspace, placeholder: "Write").padding(.top, 260).background(Theme.content), size: CGSize(width: 700, height: 420), name: "composer-channel-popup")
        composer.userEdited(text: ":sm", cursor: 3)
        await Snapshot.render(ComposerView(state: composer, workspace: workspace, placeholder: "Write").padding(.top, 260).background(Theme.content), size: CGSize(width: 700, height: 420))
    }

    @Test func richMessageBlocks() async {
        let workspace = Fixture.workspace()
        var link = AttributedString("Mattermost docs")
        link.link = URL(string: "https://docs.mattermost.com")
        var bold = AttributedString("bold text")
        bold.inlinePresentationIntent = .stronglyEmphasized
        var paragraph = AttributedString("A paragraph with ")
        paragraph.append(bold)
        paragraph.append(AttributedString(" and a link to "))
        paragraph.append(link)
        let blocks: [MessageBlock] = [
            .heading(level: 2, AttributedString("Release notes")),
            .paragraph(paragraph),
            .code(language: "swift", code: "func greet(_ name: String) -> String {\n    \"Hello, \\(name)! This line is intentionally long to require horizontal scrolling in the code block view\"\n}"),
            .quote([.paragraph(AttributedString("Quoted wisdom from someone important."))]),
            .list(ordered: false, start: 1, items: [[.paragraph(AttributedString("First bullet"))], [.paragraph(AttributedString("Second bullet"))]]),
            .list(ordered: true, start: 3, items: [[.paragraph(AttributedString("Third"))], [.paragraph(AttributedString("Fourth"))]]),
            .table(header: [AttributedString("Name"), AttributedString("Status")], rows: [[AttributedString("API")], [AttributedString("Web"), AttributedString("Degraded")]]),
            .thematicBreak,
            .image(url: URL(string: "http://mm.test/api/v4/files/inline/preview")!, alt: "inline image"),
        ]
        var post = Post(id: "rich", createAt: Fixture.minutes(30), editAt: Fixture.minutes(31), userId: "alice", channelId: "town", message: "rich",
                        props: ["from_bot": .bool(true), "attachments": .array([.object(["title": .string("Build #42"), "text": .string("Passed"), "color": .string("good"), "fields": .array([.object(["title": .string("Branch"), "value": .string("main")])])])])])
        post.metadata.reactions = [Reaction(userId: "bob", postId: "rich", emojiName: "unknown_custom"), Reaction(userId: "me", postId: "rich", emojiName: "party")]
        workspace.session.customEmojis["party"] = CustomEmoji(id: "party-id", name: "party")
        var context = workspace.timelineContext(lastViewedAt: 0, showReplyContext: true)
        context.render = { _ in blocks }
        let model = TimelineBuilder.row(for: post, previous: nil, continuation: false, context: context)
        let view = VStack(alignment: .leading, spacing: 0) {
            MessageRow(model: model, workspace: workspace, hovering: true)
            MessageRow(model: TimelineBuilder.row(for: Fixture.townPosts()[0], previous: nil, continuation: false, context: context), workspace: workspace)
            MessageRow(model: TimelineBuilder.row(for: Fixture.townPosts()[2], previous: Fixture.townPosts()[1], continuation: true, context: context), workspace: workspace, hovering: true)
            Spacer()
        }
        .padding(.top, 20)
        .background(Theme.content)
        let rep = await Snapshot.render(view, size: CGSize(width: 900, height: 1000), name: "rich-blocks", settle: .milliseconds(500))
        #expect(Snapshot.distinctColors(rep) > 10)
    }

    @Test func placeholdersAndBanners() async {
        let (model, _) = Fixture.appModel()
        await model.selectServer(at: 1)
        var loginTapped: UUID?
        await Snapshot.render(MainView(model: model, onLogin: { loginTapped = $0 }), size: CGSize(width: 1000, height: 600), name: "login-placeholder")
        #expect(loginTapped == nil)
        let empty = AppModel(store: MemoryAppStateStore(), credentials: MemoryCredentialStore(), transport: Fixture.transport())
        await Snapshot.render(MainView(model: empty), size: CGSize(width: 1000, height: 600), name: "no-servers")
        let connecting = AppModel(store: MemoryAppStateStore(AppState(servers: [ServerConfig(name: "Pending", url: Fixture.serverURL)])), credentials: MemoryCredentialStore(), transport: Fixture.transport())
        await Snapshot.render(MainView(model: connecting), size: CGSize(width: 1000, height: 600))
        let workspace = Fixture.workspace()
        workspace.session.connection = .reconnecting
        workspace.session.lastError = "Something went wrong while loading posts."
        await Snapshot.render(WorkspaceView(workspace: workspace), size: size, name: "banners")
        workspace.session.connection = .failed("Timed out")
        workspace.session.currentChannelId = nil
        await Snapshot.render(WorkspaceView(workspace: workspace), size: CGSize(width: 1000, height: 600), name: "no-channel")
        workspace.session.connection = .connected
        workspace.session.teams = []
        workspace.session.currentTeamId = nil
        await Snapshot.render(ChannelView(workspace: workspace), size: CGSize(width: 700, height: 400))
        workspace.session.connection = .idle
        await Snapshot.render(ChannelView(workspace: workspace), size: CGSize(width: 700, height: 400))
    }

    @Test func archivedAndLoadingChannels() async {
        let workspace = Fixture.workspace()
        workspace.session.currentChannelId = "old"
        await Snapshot.render(ChannelView(workspace: workspace), size: CGSize(width: 800, height: 400), name: "archived")
        workspace.session.currentChannelId = "dm-alice"
        var timeline = ChannelTimeline()
        timeline.loaded = true
        timeline.hasMoreOlder = false
        workspace.session.timelines["dm-alice"] = timeline
        await Snapshot.render(ChannelView(workspace: workspace), size: CGSize(width: 800, height: 400), name: "empty-dm")
        workspace.session.currentChannelId = "gm"
        workspace.session.timelines["gm"] = timeline
        await Snapshot.render(ChannelView(workspace: workspace), size: CGSize(width: 800, height: 400))
        workspace.session.currentChannelId = "secret"
        await Snapshot.render(ChannelView(workspace: workspace), size: CGSize(width: 800, height: 400))
    }

    @Test func sheetsAndPopovers() async {
        let transport = Fixture.transport()
        transport.on("GET", "teams/t1/channels", value: [Fixture.channels()[0], Channel(id: "new", teamId: "t1", name: "random", displayName: "Random", purpose: "Anything goes")])
        transport.on("GET", "users/autocomplete", json: String(data: try! MattermostJSON.encoder.encode(["users": [Fixture.alice, Fixture.carol]]), encoding: .utf8)!)
        let workspace = Fixture.workspace(transport: transport)
        await Snapshot.render(BrowseChannelsSheet(workspace: workspace), size: CGSize(width: 520, height: 480), name: "browse-channels", settle: .milliseconds(500))
        await Snapshot.render(DirectMessageSheet(workspace: workspace), size: CGSize(width: 460, height: 460), name: "direct-messages", settle: .milliseconds(500))
        await Snapshot.render(ImagePreviewSheet(workspace: workspace, file: FileInfo(id: "f-img", name: "screenshot.png", size: 1000, hasPreviewImage: true)), size: CGSize(width: 800, height: 600), name: "image-preview", settle: .milliseconds(400))
        workspace.recentEmojis = ["rocket"]
        await Snapshot.render(EmojiPicker(workspace: workspace) { _ in }.background(Theme.popover), size: CGSize(width: 300, height: 280), name: "emoji-picker")
        await Snapshot.render(EmojiPicker(workspace: workspace) { _ in }.background(Theme.popover), size: CGSize(width: 300, height: 280))
    }

    @Test func components() async {
        let tiles: [ServerTileModel] = [
            ServerTileModel(id: UUID(), name: "A", initials: "A", index: 0, selected: true, unread: true, mentions: 120, hint: .none),
            ServerTileModel(id: UUID(), name: "B", initials: "B", index: 1, selected: false, unread: true, mentions: 0, hint: .connecting),
            ServerTileModel(id: UUID(), name: "C", initials: "C", index: 2, selected: false, unread: false, mentions: 0, hint: .failed),
            ServerTileModel(id: UUID(), name: "D", initials: "D", index: 3, selected: false, unread: false, mentions: 0, hint: .needsLogin),
        ]
        let view = HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 10) { ForEach(tiles) { ServerTile(tile: $0) {} } }
            VStack(alignment: .leading, spacing: 10) {
                ForEach([UserStatusValue.online, .away, .dnd, .offline], id: \.self) { status in
                    Avatar(url: nil, client: nil, name: "Zed \(status.rawValue)", size: 36, status: status)
                }
                Avatar(url: nil, client: nil, name: "q", size: 18)
                CountBadge(count: 7)
                Banner(style: .warning, text: "Warning banner", actionTitle: "Act", action: {})
                Banner(style: .error, text: "Error banner", onDismiss: {})
                NewMessagesPill(count: 1) {}
                NewMessagesPill(count: 5) {}
                FileChip(file: FileInfo(id: "f", name: "archive.zip", extension: "zip", size: 2048), isDownloading: true) {}
                UploadChip(upload: PendingUpload(filename: "x.png", size: 10, state: .failed)) {}
                IconButton(systemName: "star", help: "Star") {}
                HiddenShortcut(key: "k", modifiers: .command) {}
                TypingIndicator(names: ["alice"])
                ReplyIndicator(context: ReplyContext(rootId: "r", authorName: "", snippet: "")) {}
                SearchField(text: .constant("query")) {}
                ResizeHandle(width: .constant(200), range: 100...300, direction: 1).frame(height: 20)
                FindChannelButton {}
            }
            .frame(width: 320)
        }
        .padding(20)
        .background(Theme.sidebar)
        let rep = await Snapshot.render(view, size: CGSize(width: 520, height: 900), name: "components")
        #expect(Snapshot.distinctColors(rep) > 8)
    }

    @Test func sidebarVariants() async {
        let workspace = Fixture.workspace()
        workspace.session.categories["t1"]?[1].collapsed = true
        workspace.session.teams = [Team(id: "t1", name: "engineering", displayName: "Engineering")]
        await Snapshot.render(ChannelSidebar(workspace: workspace), size: CGSize(width: 250, height: 600), name: "sidebar-collapsed")
        await Snapshot.render(SidebarSectionHeader(section: SidebarSection(id: "d", title: "Direct Messages", type: .directMessages, collapsed: false, channelIds: []), onToggle: {}, onAdd: {}), size: CGSize(width: 250, height: 40))
    }
}
