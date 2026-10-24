import AppKit
import BoltunMarkup
import Foundation
import SwiftUI
import Testing
@testable import BoltunKit
@testable import BoltunUI

@Suite struct MainFormattingTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)!
    }

    @Test func separatorTitles() {
        let now = date("2026-10-24T12:00:00Z")
        #expect(TimeFormatting.separatorTitle(for: date("2026-10-24T01:00:00Z"), now: now, calendar: calendar) == "Today")
        #expect(TimeFormatting.separatorTitle(for: date("2026-10-23T23:00:00Z"), now: now, calendar: calendar) == "Yesterday")
        #expect(TimeFormatting.separatorTitle(for: date("2026-10-20T10:00:00Z"), now: now, calendar: calendar) == "Tuesday, October 20")
        #expect(TimeFormatting.separatorTitle(for: date("2025-03-02T10:00:00Z"), now: now, calendar: calendar) == "March 2, 2025")
    }

    @Test func timeLabels() {
        let now = date("2026-10-24T12:00:00Z")
        #expect(TimeFormatting.time(date("2026-10-24T15:04:00Z"), calendar: calendar) == "3:04 PM")
        #expect(TimeFormatting.full(date("2026-10-24T09:30:00Z"), calendar: calendar) == "Saturday, October 24, 2026 at 9:30 AM")
        #expect(TimeFormatting.short(date("2026-10-24T09:30:00Z"), now: now, calendar: calendar) == "9:30 AM")
        #expect(TimeFormatting.short(date("2026-02-01T09:30:00Z"), now: now, calendar: calendar) == "Feb 1")
        #expect(TimeFormatting.short(date("2024-02-01T09:30:00Z"), now: now, calendar: calendar) == "Feb 1, 2024")
    }

    @Test func badgesAndTyping() {
        #expect(BadgeText.count(5) == "5")
        #expect(BadgeText.count(99) == "99")
        #expect(BadgeText.count(100) == "99+")
        #expect(TypingText.text(for: []) == nil)
        #expect(TypingText.text(for: ["a"]) == "a is typing…")
        #expect(TypingText.text(for: ["a", "b"]) == "a and b are typing…")
        #expect(TypingText.text(for: ["a", "b", "c"]) == "a, b and c are typing…")
        #expect(TypingText.text(for: ["a", "b", "c", "d", "e"]) == "a, b and 3 others are typing…")
    }

    @Test func initialsAndSizes() {
        #expect(Initials.of("Acme Corp") == "AC")
        #expect(Initials.of("bob.smith") == "BS")
        #expect(Initials.of("x") == "X")
        #expect(Initials.of("") == "")
        #expect(Initials.paletteIndex(for: "alice", count: 6) == Initials.paletteIndex(for: "alice", count: 6))
        #expect((0..<6).contains(Initials.paletteIndex(for: "bob", count: 6)))
        #expect(Initials.paletteIndex(for: "bob", count: 0) == 0)
        #expect(!FileSizeText.text(2_400_000).isEmpty)
    }

    @Test func formatterCacheReusesInstances() {
        let cache = FormatterCache()
        let first = cache.formatter(format: "h:mm", calendar: calendar)
        #expect(first === cache.formatter(format: "h:mm", calendar: calendar))
        #expect(first !== cache.formatter(format: "HH:mm", calendar: calendar))
    }
}

@Suite struct MainMentionTests {
    @Test func detectsUsernameAndKeys() {
        #expect(MentionDetector.mentions("hey @boltun look", username: "boltun", keys: []))
        #expect(MentionDetector.mentions("@BOLTUN!", username: "boltun", keys: []))
        #expect(!MentionDetector.mentions("hey @boltunx", username: "boltun", keys: []))
        #expect(!MentionDetector.mentions("mail boltun@x", username: "boltun", keys: []))
        #expect(MentionDetector.mentions("ping @here", username: "boltun", keys: []))
        #expect(MentionDetector.mentions("the deploy failed", username: "boltun", keys: ["deploy", " "]))
        #expect(!MentionDetector.mentions("redeployed", username: "boltun", keys: ["deploy"]))
        #expect(!MentionDetector.mentions("", username: "boltun", keys: ["x"]))
        #expect(!MentionDetector.mentions("hello", username: "", keys: []))
    }
}

@Suite @MainActor struct MainTimelineTests {
    func context(lastViewedAt: Int64 = 0, showReply: Bool = true) -> TimelineContext {
        let posts = Dictionary(uniqueKeysWithValues: Fixture.townPosts().map { ($0.id, $0) })
        var context = TimelineContext(myId: "me", myUsername: "boltun", mentionKeys: ["deploy"], lastViewedAt: lastViewedAt, now: Fixture.now, calendar: Fixture.calendar, showReplyContext: showReply)
        context.displayName = { $0.userId.capitalized }
        context.userName = { $0.capitalized }
        context.post = { posts[$0] }
        context.avatarURL = { URL(string: "http://a/\($0.userId)") }
        context.customEmojiId = { $0 == "party" ? "e1" : nil }
        return context
    }

    func rows(_ items: [TimelineItem]) -> [MessageRowModel] {
        items.compactMap { if case .post(let model) = $0 { return model } else { return nil } }
    }

    @Test func groupsAndSeparates() {
        let items = TimelineBuilder.items(posts: Fixture.townPosts(), context: context(lastViewedAt: Fixture.minutes(15)))
        let dates = items.filter { if case .date = $0 { return true } else { return false } }
        #expect(dates.count == 2)
        #expect(items.first == .date("Yesterday"))
        #expect(items.filter { $0 == .newMessages }.count == 1)
        let byId = Dictionary(uniqueKeysWithValues: rows(items).map { ($0.id, $0) })
        #expect(byId["p1"]?.isContinuation == false)
        #expect(byId["p2"]?.isContinuation == true)
        #expect(byId["p3"]?.isContinuation == false)
        #expect(byId["p3"]?.replyContext?.rootId == "p1")
        #expect(byId["p3"]?.replyContext?.authorName == "Alice")
        #expect(byId["p4"]?.isMine == true)
        #expect(byId["p4"]?.mentionsMe == false)
        #expect(byId["p6"]?.mentionsMe == true)
        #expect(byId["p6"]?.isContinuation == false)
        #expect(byId["p7"]?.blocks.isEmpty == true)
        #expect(byId["p7"]?.isContinuation == true)
        #expect(byId["p8"]?.mentionsMe == true)
        #expect(byId["p0"]?.isSystem == true)
        #expect(byId["p1"]?.replyCount == 2)
        #expect(byId["r1"]?.replyCount == 0)
        #expect(byId["p1"]?.avatarURL?.absoluteString == "http://a/alice")
        let reactions = byId["p2"]?.reactions ?? []
        #expect(reactions.map(\.emojiName) == ["+1", "tada"])
        #expect(reactions.first?.isMine == true)
        #expect(reactions.first?.count == 2)
        #expect(reactions.first?.glyph == "👍")
        #expect(reactions.first?.userNames == ["Me", "Bob"])
        let newIndex = items.firstIndex(of: .newMessages)!
        #expect(items[newIndex + 1].id == "p6")
    }

    @Test func newMessagesSkipsOwnPostsAndRequiresLastViewed() {
        let posts = [
            Post(id: "a", createAt: Fixture.minutes(1), userId: "me", channelId: "c", message: "mine"),
            Post(id: "b", createAt: Fixture.minutes(2), userId: "x", channelId: "c", message: "theirs"),
        ]
        let items = TimelineBuilder.items(posts: posts, context: context(lastViewedAt: Fixture.minutes(0)))
        #expect(items.map(\.id) == ["date:Today", "a", "new-messages", "b"])
        #expect(!TimelineBuilder.items(posts: posts, context: context()).contains(.newMessages))
    }

    @Test func threadContextOmitsReplyIndicator() {
        let items = TimelineBuilder.items(posts: Fixture.townPosts(), context: context(showReply: false))
        #expect(rows(items).allSatisfy { $0.replyContext == nil })
    }

    @Test func threadItemsInsertRepliesDivider() {
        let posts = Fixture.townPosts().filter { ["p1", "p3", "r1"].contains($0.id) }
        let context = self.context(showReply: false)
        #expect(TimelineBuilder.threadItems(posts: posts, context: context).map(\.id) == ["p1", "replies", "p3", "r1"])
        #expect(TimelineBuilder.threadItems(posts: [posts[0]], context: context).map(\.id) == ["p1"])
        #expect(TimelineBuilder.threadItems(posts: [posts[1]], context: context).first == .date("Today"))
        #expect(TimelineBuilder.threadItems(posts: [], context: context).isEmpty)
        #expect(TimelineItem.replies(2).id == "replies")
    }

    @Test func replyContextForMissingRoot() {
        let reply = Post(id: "x", createAt: 1, userId: "a", channelId: "c", rootId: "gone", message: "hi")
        let context = TimelineBuilder.replyContext(for: reply, previous: nil, context: self.context())
        #expect(context == ReplyContext(rootId: "gone", authorName: "", snippet: ""))
    }

    @Test func groupingRules() {
        let base = Post(id: "1", createAt: 0, userId: "a", channelId: "c", message: "x")
        var next = Post(id: "2", createAt: 60_000, userId: "a", channelId: "c", message: "y")
        #expect(TimelineBuilder.canGroup(next, after: base))
        next.createAt = 6 * 60_000
        #expect(!TimelineBuilder.canGroup(next, after: base))
        next.createAt = 1000
        next.userId = "b"
        #expect(!TimelineBuilder.canGroup(next, after: base))
        next.userId = "a"
        next.type = "system_join_channel"
        #expect(!TimelineBuilder.canGroup(next, after: base))
        next.type = ""
        next.props = ["from_webhook": .string("true"), "override_username": .string("bot")]
        #expect(!TimelineBuilder.canGroup(next, after: base))
        next.props = [:]
        next.rootId = "1"
        #expect(TimelineBuilder.canGroup(next, after: base))
        let reply = Post(id: "3", createAt: 500, userId: "a", channelId: "c", rootId: "1", message: "r")
        #expect(!TimelineBuilder.canGroup(Post(id: "4", createAt: 900, userId: "a", channelId: "c", message: "z"), after: reply))
        next.createAt = -1
        #expect(!TimelineBuilder.canGroup(next, after: base))
    }

    @Test func snippetTruncates() {
        #expect(TimelineBuilder.snippet("a\nb") == "a b")
        let long = String(repeating: "word ", count: 40)
        let result = TimelineBuilder.snippet(long, limit: 20)
        #expect(result.hasSuffix("…"))
        #expect(result.count <= 21)
    }

    @Test func rowModelEqualityIgnoresBlocks() {
        let row = TimelineBuilder.row(for: Fixture.townPosts()[1], previous: nil, continuation: false, context: context())
        var other = row
        other.blocks = []
        #expect(row == other)
        other.authorName = "Changed"
        #expect(row != other)
    }

    @Test func emojiGlyphFallbacks() {
        #expect(EmojiGlyph.glyph(for: "+1") == "👍")
        #expect(EmojiGlyph.glyph(for: "thumbsup") == "👍")
        #expect(EmojiGlyph.glyph(for: "definitely-not-an-emoji") == nil)
    }

    @Test func timelineItemIds() {
        #expect(TimelineItem.date("Today").id == "date:Today")
        #expect(TimelineItem.newMessages.id == "new-messages")
    }
}

@Suite struct MainAutocompleteTests {
    @Test func detectsTriggers() {
        #expect(AutocompleteParser.query(in: "hi @al", cursor: 6) == AutocompleteQuery(kind: .user, prefix: "al", location: 3, length: 3))
        #expect(AutocompleteParser.query(in: "@", cursor: 1) == AutocompleteQuery(kind: .user, prefix: "", location: 0, length: 1))
        #expect(AutocompleteParser.query(in: "go ~town", cursor: 8)?.kind == .channel)
        #expect(AutocompleteParser.query(in: "nice :sm", cursor: 8) == AutocompleteQuery(kind: .emoji, prefix: "sm", location: 5, length: 3))
        #expect(AutocompleteParser.query(in: "nice :s", cursor: 7) == nil)
        #expect(AutocompleteParser.query(in: "mail a@b", cursor: 8) == nil)
        #expect(AutocompleteParser.query(in: "hello", cursor: 5) == nil)
        #expect(AutocompleteParser.query(in: "(@bob.s", cursor: 7)?.prefix == "bob.s")
        #expect(AutocompleteParser.query(in: "@al x", cursor: 5) == nil)
        #expect(AutocompleteParser.query(in: "@al", cursor: 9) == nil)
        #expect(AutocompleteParser.query(in: "@alice", cursor: 3)?.prefix == "al")
        #expect(AutocompleteParser.query(in: "x\n:+1", cursor: 5)?.prefix == "+1")
    }

    @Test func appliesReplacement() {
        let query = AutocompleteParser.query(in: "hi @al there", cursor: 6)!
        let suggestion = AutocompleteSuggestion(id: "u", kind: .user, title: "@alice", subtitle: "", replacement: "@alice")
        let result = AutocompleteParser.apply(suggestion, to: "hi @al there", query: query)
        #expect(result.text == "hi @alice  there")
        #expect(result.cursor == 10)
    }

    @Test func keyRouting() {
        let empty = ComposerKeyContext(isEmpty: true, hasSuggestions: false, isEditing: false)
        let typed = ComposerKeyContext(isEmpty: false, hasSuggestions: false, isEditing: false)
        let suggesting = ComposerKeyContext(isEmpty: false, hasSuggestions: true, isEditing: false)
        let editing = ComposerKeyContext(isEmpty: false, hasSuggestions: false, isEditing: true)
        #expect(ComposerKeyRouter.command(for: .enter, modifiers: [], context: typed) == .send)
        #expect(ComposerKeyRouter.command(for: .enter, modifiers: .shift, context: typed) == .insertNewline)
        #expect(ComposerKeyRouter.command(for: .enter, modifiers: .option, context: typed) == .insertNewline)
        #expect(ComposerKeyRouter.command(for: .enter, modifiers: [], context: suggesting) == .acceptSuggestion)
        #expect(ComposerKeyRouter.command(for: .enter, modifiers: .shift, context: suggesting) == .insertNewline)
        #expect(ComposerKeyRouter.command(for: .tab, modifiers: [], context: suggesting) == .acceptSuggestion)
        #expect(ComposerKeyRouter.command(for: .tab, modifiers: [], context: typed) == .passThrough)
        #expect(ComposerKeyRouter.command(for: .up, modifiers: [], context: empty) == .editLastPost)
        #expect(ComposerKeyRouter.command(for: .up, modifiers: .shift, context: empty) == .passThrough)
        #expect(ComposerKeyRouter.command(for: .up, modifiers: [], context: typed) == .passThrough)
        #expect(ComposerKeyRouter.command(for: .up, modifiers: [], context: suggesting) == .selectPreviousSuggestion)
        #expect(ComposerKeyRouter.command(for: .down, modifiers: [], context: suggesting) == .selectNextSuggestion)
        #expect(ComposerKeyRouter.command(for: .down, modifiers: [], context: typed) == .passThrough)
        #expect(ComposerKeyRouter.command(for: .escape, modifiers: [], context: suggesting) == .dismissSuggestions)
        #expect(ComposerKeyRouter.command(for: .escape, modifiers: [], context: editing) == .cancelEdit)
        #expect(ComposerKeyRouter.command(for: .escape, modifiers: [], context: typed) == .passThrough)
        #expect(ComposerKeyRouter.command(for: .up, modifiers: [], context: ComposerKeyContext(isEmpty: true, hasSuggestions: false, isEditing: true)) == .passThrough)
    }

    @Test func selectorMapping() {
        #expect(ComposerKeyMapper.key(for: #selector(NSResponder.insertNewline(_:))) == .enter)
        #expect(ComposerKeyMapper.key(for: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))) == .enter)
        #expect(ComposerKeyMapper.key(for: #selector(NSResponder.insertLineBreak(_:))) == .enter)
        #expect(ComposerKeyMapper.key(for: #selector(NSResponder.moveUp(_:))) == .up)
        #expect(ComposerKeyMapper.key(for: #selector(NSResponder.moveDown(_:))) == .down)
        #expect(ComposerKeyMapper.key(for: #selector(NSResponder.insertTab(_:))) == .tab)
        #expect(ComposerKeyMapper.key(for: #selector(NSResponder.cancelOperation(_:))) == .escape)
        #expect(ComposerKeyMapper.key(for: #selector(NSResponder.moveLeft(_:))) == nil)
        #expect(ComposerKeyMapper.modifiers([.shift, .option, .command, .control]) == [.shift, .option, .command, .control])
        #expect(ComposerKeyMapper.modifiers([]) == [])
        #expect(ComposerKeyMapper.modifiers(for: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), flags: []) == .option)
        #expect(ComposerKeyMapper.modifiers(for: #selector(NSResponder.insertLineBreak(_:)), flags: []) == .control)
    }

    @Test func kindProperties() {
        #expect(AutocompleteKind.user.trigger == "@")
        #expect(AutocompleteKind.channel.trigger == "~")
        #expect(AutocompleteKind.emoji.minimumPrefix == 2)
    }

    @Test @MainActor func pasteboardContent() {
        let board = NSPasteboard(name: NSPasteboard.Name("boltun-paste-\(UUID().uuidString)"))
        board.clearContents()
        board.setString("hello", forType: .string)
        #expect(PasteboardReader.content(of: board) == .text)
        board.clearContents()
        let png = TestImages.png(seed: "x", size: 4)
        board.setData(png, forType: .png)
        #expect(PasteboardReader.content(of: board) == .image(png))
        board.clearContents()
        let tiff = NSImage(data: png)!.tiffRepresentation!
        board.setData(tiff, forType: .tiff)
        if case .image = PasteboardReader.content(of: board) {} else { Issue.record("expected image") }
        board.clearContents()
        let url = URL(fileURLWithPath: "/tmp/file.txt")
        board.writeObjects([url as NSURL])
        #expect(PasteboardReader.content(of: board) == .files([url]))
    }
}

@Suite struct MainNavigationTests {
    func item(_ id: String, _ title: String, unread: Bool = false, mentions: Int = 0, key: String = "") -> QuickSwitchItem {
        QuickSwitchItem(channelId: id, title: title, subtitle: "", kind: .open, unread: unread, mentions: mentions, searchKey: key.isEmpty ? title.lowercased() : key)
    }

    @Test func fuzzyScores() {
        #expect(FuzzyMatcher.score("", in: "anything") == 0)
        #expect(FuzzyMatcher.score("town", in: "Town Square")! > FuzzyMatcher.score("tsq", in: "Town Square")!)
        #expect(FuzzyMatcher.score("tsq", in: "Town Square") != nil)
        #expect(FuzzyMatcher.score("xyz", in: "Town Square") == nil)
        #expect(FuzzyMatcher.score("sq", in: "Square")! > FuzzyMatcher.score("sq", in: "Town Square")!)
    }

    @Test func quickSwitcherResults() {
        let items = [item("1", "Town Square"), item("2", "Off-Topic", unread: true), item("3", "Design", mentions: 2), item("4", "alice", key: "alice")]
        #expect(QuickSwitcher.results(items, query: "").map(\.channelId) == ["3", "2", "1", "4"])
        #expect(QuickSwitcher.results(items, query: "top").first?.channelId == "2")
        #expect(QuickSwitcher.results(items, query: "ali").map(\.channelId) == ["4"])
        #expect(QuickSwitcher.results(items, query: "zzz").isEmpty)
        #expect(QuickSwitcher.results(items, query: "", limit: 2).count == 2)
        #expect(QuickSwitcher.moveSelection(0, by: -1, count: 4) == 3)
        #expect(QuickSwitcher.moveSelection(3, by: 1, count: 4) == 0)
        #expect(QuickSwitcher.moveSelection(2, by: 1, count: 0) == 0)
    }

    @Test func adjacentAndUnread() {
        let ids = ["a", "b", "c", "d"]
        #expect(ChannelNavigator.adjacent(in: ids, from: "b", offset: 1) == "c")
        #expect(ChannelNavigator.adjacent(in: ids, from: "a", offset: -1) == "d")
        #expect(ChannelNavigator.adjacent(in: ids, from: nil, offset: 1) == "a")
        #expect(ChannelNavigator.adjacent(in: ids, from: "zz", offset: -1) == "d")
        #expect(ChannelNavigator.adjacent(in: [], from: "a", offset: 1) == nil)
        #expect(ChannelNavigator.nextUnread(in: ids, from: "b", unread: ["a", "d"], forward: true) == "d")
        #expect(ChannelNavigator.nextUnread(in: ids, from: "b", unread: ["a", "d"], forward: false) == "a")
        #expect(ChannelNavigator.nextUnread(in: ids, from: "b", unread: ["b"], forward: true) == nil)
        #expect(ChannelNavigator.nextUnread(in: ids, from: nil, unread: ["c"], forward: true) == "c")
        #expect(ChannelNavigator.nextUnread(in: ids, from: "a", unread: [], forward: true) == nil)
    }

    @Test func linkRouting() {
        #expect(LinkRouter.action(for: URL(string: "boltun-mention://alice")!) == .mention("alice"))
        #expect(LinkRouter.action(for: URL(string: "boltun-channel://town-square")!) == .channel("town-square"))
        #expect(LinkRouter.action(for: URL(string: "boltun-hashtag://release")!) == .hashtag("release"))
        #expect(LinkRouter.action(for: URL(string: "boltun-mention:bob.smith")!) == .mention("bob.smith"))
        let web = URL(string: "https://example.com/a")!
        #expect(LinkRouter.action(for: web) == .external(web))
        #expect(LinkRouter.payload(of: URL(string: "boltun-channel://a%20b/")!) == "a b")
    }

    @Test func permalinks() {
        let server = URL(string: "https://chat.example.com")!
        #expect(Permalink.channel(server: server, teamName: "eng", channelName: "town-square") == "https://chat.example.com/eng/channels/town-square")
        #expect(Permalink.post(server: server, teamName: "eng", postId: "abc") == "https://chat.example.com/eng/pl/abc")
    }

    @Test func downloadDestinations() {
        let dir = URL(fileURLWithPath: "/tmp/d")
        let taken: Set<String> = ["/tmp/d/report.pdf", "/tmp/d/report (1).pdf", "/tmp/d/README"]
        #expect(DownloadDestination.uniqueURL(in: dir, filename: "report.pdf", exists: { taken.contains($0.path) }).lastPathComponent == "report (2).pdf")
        #expect(DownloadDestination.uniqueURL(in: dir, filename: "README", exists: { taken.contains($0.path) }).lastPathComponent == "README (1)")
        #expect(DownloadDestination.uniqueURL(in: dir, filename: "a/b:c", exists: { _ in false }).lastPathComponent == "a_b_c")
        #expect(DownloadDestination.uniqueURL(in: dir, filename: "", exists: { _ in false }).lastPathComponent == "download")
        #expect(DownloadDestination.downloadsDirectory.path.hasSuffix("Downloads"))
    }

    @Test func mimeTypes() {
        #expect(MimeType.of(filename: "a.PNG") == "image/png")
        #expect(MimeType.of(filename: "a.jpeg") == "image/jpeg")
        for (name, mime) in [("a.gif", "image/gif"), ("a.webp", "image/webp"), ("a.heic", "image/heic"), ("a.pdf", "application/pdf"), ("a.md", "text/plain"), ("a.json", "application/json"), ("a.zip", "application/zip"), ("a.mp4", "video/mp4"), ("a.mov", "video/quicktime"), ("a.bin", "application/octet-stream")] {
            #expect(MimeType.of(filename: name) == mime)
        }
    }
}

@Suite @MainActor struct MainViewModelTests {
    @Test func tallNewPostAtTheBottomKeepsFollowing() {
        var state = ScrollFollowState()
        _ = state.postsChanged(postIds: ["a"], lastIsMine: false)
        state.scrolled(atBottom: true)
        let before = ScrollMetrics(distanceFromTop: 700, distanceFromBottom: 0, contentHeight: 1000, containerHeight: 300)
        let grown = ScrollMetrics(distanceFromTop: 700, distanceFromBottom: 140, contentHeight: 1140, containerHeight: 300)
        #expect(grown.grewInPlace(from: before))
        state.scrolled(atBottom: grown.isAtBottom, contentGrewInPlace: grown.grewInPlace(from: before))
        #expect(state.isAtBottom)
        let follows = state.postsChanged(postIds: ["a", "b"], lastIsMine: false)
        #expect(follows)
    }

    @Test func scrollingUpStillStopsFollowing() {
        var state = ScrollFollowState()
        state.scrolled(atBottom: true)
        let before = ScrollMetrics(distanceFromTop: 700, distanceFromBottom: 0, contentHeight: 1000, containerHeight: 300)
        let scrolled = ScrollMetrics(distanceFromTop: 500, distanceFromBottom: 200, contentHeight: 1000, containerHeight: 300)
        #expect(!scrolled.grewInPlace(from: before))
        state.scrolled(atBottom: scrolled.isAtBottom, contentGrewInPlace: scrolled.grewInPlace(from: before))
        #expect(!state.isAtBottom)
        let grownWhileUp = ScrollMetrics(distanceFromTop: 500, distanceFromBottom: 340, contentHeight: 1140, containerHeight: 300)
        state.scrolled(atBottom: grownWhileUp.isAtBottom, contentGrewInPlace: grownWhileUp.grewInPlace(from: scrolled))
        #expect(!state.isAtBottom)
    }

    @Test func scrollFollow() {
        var state = ScrollFollowState()
        var ids = ["a"]
        func change(_ appended: [String], mine: Bool = false) -> Bool {
            ids += appended
            return state.postsChanged(postIds: ids, lastIsMine: mine)
        }
        #expect(change([]))
        #expect(!change([]))
        state.scrolled(atBottom: false)
        #expect(!change(["x", "b"]))
        #expect(!change(["c"]))
        #expect(change(["d"], mine: true))
        state.scrolled(atBottom: true)
        #expect(change(["e"]))
        state.scrolled(atBottom: false)
        #expect(!change(["f"]))
        state.jumpedToBottom()
        #expect(state.isAtBottom)
        #expect(change(["g"]))
        func replace(_ list: [String]) -> Bool {
            state.postsChanged(postIds: list, lastIsMine: false)
        }
        #expect(!replace([]))
        #expect(replace(["h"]))
    }

    @Test func olderPagesDoNotFollow() {
        var state = ScrollFollowState()
        let latest = (300..<360).map { "p\($0)" }
        let initial = state.postsChanged(postIds: latest, lastIsMine: false)
        #expect(initial)
        state.scrolled(atBottom: false)
        let older = (0..<300).map { "p\($0)" } + latest
        let prepended = state.postsChanged(postIds: older, lastIsMine: false)
        #expect(!prepended)
        let appended = state.postsChanged(postIds: older + ["n1"], lastIsMine: false)
        #expect(!appended)
    }

    @Test func scrollMetrics() {
        #expect(ScrollMetrics(distanceFromTop: 0, distanceFromBottom: 100).isAtBottom)
        #expect(!ScrollMetrics(distanceFromTop: 0, distanceFromBottom: 101).isAtBottom)
        #expect(ScrollMetrics(distanceFromTop: 0, distanceFromBottom: 10).isAtBottom)
        #expect(!ScrollMetrics(distanceFromTop: 0, distanceFromBottom: 500).isAtBottom)
        let visible = ScrollMetrics(distanceFromTop: 0, distanceFromBottom: 0, containerHeight: 400)
        #expect(visible.isVisible(CGRect(x: 0, y: 50, width: 10, height: 20)))
        #expect(!visible.isVisible(CGRect(x: 0, y: -30, width: 10, height: 20)))
        #expect(!visible.isVisible(CGRect(x: 0, y: 400, width: 10, height: 20)))
        #expect(ScrollMetrics(distanceFromTop: 100, distanceFromBottom: 0).shouldLoadOlder)
        #expect(!ScrollMetrics(distanceFromTop: 5000, distanceFromBottom: 0).shouldLoadOlder)
    }

    @Test func forceScrollAlwaysChangesPosition() {
        var position = ScrollPosition(edge: .bottom)
        for _ in 0..<3 {
            let before = position
            position.forceScroll(to: .bottom, edgeItemId: "last")
            #expect(position != before)
        }
        var top = ScrollPosition(edge: .top)
        top.forceScroll(to: .top, edgeItemId: "first")
        #expect(top.viewID(type: String.self) == "first")
        top.forceScroll(to: .top, edgeItemId: "first")
        #expect(top.edge == .top)
        var noItems = ScrollPosition(edge: .bottom)
        noItems.forceScroll(to: .bottom, edgeItemId: nil)
        #expect(noItems.edge == .bottom)
    }

    @Test func scrollFollowSettlesOnlyAtBottom() {
        var state = ScrollFollowState()
        #expect(!state.settled)
        state.scrolled(atBottom: false)
        #expect(!state.settled)
        state.scrolled(atBottom: true)
        state.scrolled(atBottom: false)
        #expect(state.settled)
    }

    func timeline(_ ids: [String], loading: Bool = false, more: Bool = true) -> ChannelTimeline {
        var timeline = ChannelTimeline()
        timeline.postIds = ids
        timeline.loaded = true
        timeline.isLoading = loading
        timeline.hasMoreOlder = more
        return timeline
    }

    @Test func prependKeepsDistanceFromBottom() {
        let tracker = ScrollTracker()
        let before = ScrollMetrics(distanceFromTop: 500, distanceFromBottom: 800, contentHeight: 1900, containerHeight: 600)
        #expect(tracker.compensation(head: TimelineHead(timeline(["b", "c"])), old: before, new: before, settled: true) == nil)
        let grown = ScrollMetrics(distanceFromTop: 500, distanceFromBottom: 2000, contentHeight: 3100, containerHeight: 600)
        #expect(tracker.compensation(head: TimelineHead(timeline(["a", "b", "c"])), old: before, new: grown, settled: true) == 1700)
        let scrolled = ScrollMetrics(distanceFromTop: 1580, distanceFromBottom: 920, contentHeight: 3100, containerHeight: 600)
        #expect(tracker.compensation(head: TimelineHead(timeline(["a", "b", "c"])), old: grown, new: scrolled, settled: true) == nil)
    }

    @Test func loadingIndicatorChangeIsCompensated() {
        let tracker = ScrollTracker()
        let before = ScrollMetrics(distanceFromTop: 300, distanceFromBottom: 900, contentHeight: 1800, containerHeight: 600)
        _ = tracker.compensation(head: TimelineHead(timeline(["a"])), old: before, new: before, settled: true)
        let spinner = ScrollMetrics(distanceFromTop: 300, distanceFromBottom: 950, contentHeight: 1850, containerHeight: 600)
        #expect(tracker.compensation(head: TimelineHead(timeline(["a"], loading: true)), old: before, new: spinner, settled: true) == 350)
    }

    @Test func noCompensationWhenUnsettledOrAtBottom() {
        let before = ScrollMetrics(distanceFromTop: 100, distanceFromBottom: 900, contentHeight: 1600, containerHeight: 600)
        let grown = ScrollMetrics(distanceFromTop: 100, distanceFromBottom: 2100, contentHeight: 2800, containerHeight: 600)
        let unsettled = ScrollTracker()
        _ = unsettled.compensation(head: TimelineHead(timeline(["b"])), old: before, new: before, settled: false)
        #expect(unsettled.compensation(head: TimelineHead(timeline(["a", "b"])), old: before, new: grown, settled: false) == nil)
        let bottom = ScrollTracker()
        let atBottom = ScrollMetrics(distanceFromTop: 1000, distanceFromBottom: 0, contentHeight: 1600, containerHeight: 600)
        _ = bottom.compensation(head: TimelineHead(timeline(["b"])), old: atBottom, new: atBottom, settled: true)
        #expect(bottom.compensation(head: TimelineHead(timeline(["a", "b"])), old: atBottom, new: grown, settled: true) == nil)
        #expect(ScrollTracker.compensatedOffset(preserving: 100, in: ScrollMetrics(distanceFromTop: 0, distanceFromBottom: 100.5, contentHeight: 700, containerHeight: 600)) == nil)
        #expect(ScrollTracker.compensatedOffset(preserving: 900, in: ScrollMetrics(distanceFromTop: 0, distanceFromBottom: 0, contentHeight: 700, containerHeight: 600)) == 0)
    }

    @Test func alignmentSteps() {
        let middle = ScrollMetrics(distanceFromTop: 800, distanceFromBottom: 400)
        #expect(ScrollTracker.alignmentStep(frame: nil, metrics: middle) == .scrollToItem)
        #expect(ScrollTracker.alignmentStep(frame: CGRect(x: 0, y: 50.5, width: 10, height: 10), metrics: middle) == .done)
        #expect(ScrollTracker.alignmentStep(frame: CGRect(x: 0, y: 200, width: 10, height: 10), metrics: middle) == .scroll(950))
        #expect(ScrollTracker.alignmentStep(frame: CGRect(x: 0, y: -100, width: 10, height: 10), metrics: middle) == .scroll(650))
        #expect(ScrollTracker.alignmentStep(frame: CGRect(x: 0, y: -900, width: 10, height: 10), metrics: middle) == .scroll(0))
        let bottom = ScrollMetrics(distanceFromTop: 800, distanceFromBottom: 0.5)
        #expect(ScrollTracker.alignmentStep(frame: CGRect(x: 0, y: 300, width: 10, height: 10), metrics: bottom) == .done)
        let top = ScrollMetrics(distanceFromTop: 0, distanceFromBottom: 400)
        #expect(ScrollTracker.alignmentStep(frame: CGRect(x: 0, y: 10, width: 10, height: 10), metrics: top) == .done)
    }

    @Test func alignmentSearchesTowardsAnUnrenderedTarget() {
        let metrics = ScrollMetrics(distanceFromTop: 1000, distanceFromBottom: 300, containerHeight: 500)
        #expect(ScrollTracker.alignmentStep(frame: nil, metrics: metrics, targetIndex: 5, visible: 10...20) == .scroll(600))
        #expect(ScrollTracker.alignmentStep(frame: nil, metrics: metrics, targetIndex: 25, visible: 10...20) == .scroll(1300))
        #expect(ScrollTracker.alignmentStep(frame: nil, metrics: metrics, targetIndex: 15, visible: 10...20) == .scrollToItem)
        #expect(ScrollTracker.alignmentStep(frame: nil, metrics: metrics, targetIndex: 5, visible: nil) == .scrollToItem)
        let nearTop = ScrollMetrics(distanceFromTop: 100, distanceFromBottom: 900, containerHeight: 500)
        #expect(ScrollTracker.alignmentStep(frame: nil, metrics: nearTop, targetIndex: 1, visible: 3...9) == .scroll(0))
        let short = ScrollMetrics(distanceFromTop: 0, distanceFromBottom: 0, containerHeight: 0)
        #expect(ScrollTracker.alignmentStep(frame: nil, metrics: short, targetIndex: 9, visible: 0...3) == .scroll(0))
    }

    @Test func visibleRangeFollowsTimelineOrder() {
        let tracker = ScrollTracker()
        let items: [TimelineItem] = [.date("Today"), .newMessages, .replies(1)]
        #expect(tracker.visibleRange(in: items) == nil)
        tracker.visibleIds = ["replies", "new-messages", "unknown"]
        #expect(tracker.visibleRange(in: items) == 1...2)
    }

    @Test func liveFrameIgnoresFramesOfRowsThatAreNotVisibleWhenVisibilityIsKnown() {
        let tracker = ScrollTracker()
        tracker.frames["new-messages"] = CGRect(x: 0, y: -3200, width: 100, height: 20)
        #expect(tracker.liveFrame(of: "new-messages")?.minY == -3200)
        tracker.visibleIds = ["post-1"]
        #expect(tracker.liveFrame(of: "new-messages") == nil)
        tracker.visibleIds = ["new-messages"]
        #expect(tracker.liveFrame(of: "new-messages")?.minY == -3200)
        #expect(tracker.liveFrame(of: "missing") == nil)
    }

    @Test func timelineReadinessAndToastSignature() {
        var timeline = timeline(["a", "b"], loading: true)
        #expect(!TimelineReadiness(timeline).isReady)
        timeline.isLoading = false
        #expect(TimelineReadiness(timeline).isReady)
        timeline.loaded = false
        #expect(!TimelineReadiness(timeline).isReady)
        let signature = ToastSignature(timeline)
        timeline.lastViewedAtOnOpen = 5
        #expect(ToastSignature(timeline) != signature)
        #expect(ToastSignature(timeline).postCount == 2)
        #expect(ToastSignature(timeline).lastPostId == "b")
    }

    @Test func serverTiles() {
        let (model, _) = Fixture.appModel()
        let tiles = ServerTileModel.make(model: model)
        #expect(tiles.count == 3)
        #expect(tiles[0].selected)
        #expect(tiles[0].initials == "AC")
        #expect(tiles[0].mentions == 4)
        #expect(tiles[0].hint == .none)
        #expect(tiles[1].hint == .needsLogin)
        #expect(tiles[2].hint == .reconnecting)
        #expect(tiles[2].mentions == 3)
        #expect(tiles[0].tooltip == "Acme Corp — ⌘1")
        #expect(tiles[1].tooltip == "Side Project — Login required — ⌘2")
        #expect(ServerTileModel.hint(needsLogin: false, connection: .connecting) == .connecting)
        #expect(ServerTileModel.hint(needsLogin: false, connection: .unauthorized) == .needsLogin)
        #expect(ServerTileModel.hint(needsLogin: false, connection: .failed("x")) == .failed)
        #expect(ServerTileModel.hint(needsLogin: false, connection: nil) == .none)
        var tile = tiles[0]
        tile.index = 10
        tile.hint = .failed
        #expect(tile.shortcutLabel == nil)
        #expect(tile.tooltip == "Acme Corp — Cannot connect")
        tile.hint = .connecting
        #expect(tile.tooltip.contains("Connecting"))
        #expect(tiles[0].menuTitle == "✓ Acme Corp  (4)")
        #expect(tiles[1].menuTitle.hasSuffix(" — Login required"))
        #expect(!tiles[1].menuTitle.hasPrefix("✓"))
        let others = ServerTileModel.otherServersUnread(tiles)
        #expect(others.mentions == tiles[1].mentions + tiles[2].mentions)
        #expect(others.unread == (tiles[1].unread || tiles[2].unread))
        #expect(ServerTileModel.otherServersUnread([tiles[0]]) == ChannelUnread())
    }

    @Test func teamTiles() {
        let session = Fixture.session()
        session.teams.append(Team(id: "t3", name: "ops-team", displayName: "", lastTeamIconUpdate: 42))
        let tiles = TeamTileModel.make(session: session)
        #expect(tiles.map(\.id) == ["t1", "t2", "t3"])
        #expect(tiles[0].selected && !tiles[1].selected)
        #expect(tiles[0].initials == "E")
        #expect(tiles[2].initials == "OT")
        #expect(tiles[1].unread && tiles[1].mentions == 1)
        #expect(tiles[0].iconURL == nil)
        #expect(tiles[2].iconURL?.absoluteString.hasSuffix("teams/t3/image?_=42") == true)
        #expect(tiles[2].name == "ops-team")
        #expect(tiles[0].tooltip == "Engineering — ⌃⌘1")
        var far = tiles[1]
        far.index = 9
        #expect(far.shortcutLabel == nil)
        #expect(far.tooltip == "Design")
    }

    @Test func teamNavigatorByNumber() {
        #expect(TeamNavigator.team(number: 1, in: ["a", "b"]) == "a")
        #expect(TeamNavigator.team(number: 2, in: ["a", "b"]) == "b")
        #expect(TeamNavigator.team(number: 3, in: ["a", "b"]) == nil)
        #expect(TeamNavigator.team(number: 0, in: ["a", "b"]) == nil)
        #expect(TeamNavigator.team(number: 1, in: []) == nil)
    }

    @Test func sidebarRows() {
        let session = Fixture.session()
        let town = SidebarRowModel.make(channelId: "town", session: session)!
        #expect(town.selected && town.icon == .open && !town.unread)
        let off = SidebarRowModel.make(channelId: "offtopic", session: session)!
        #expect(off.unread && off.mentions == 2 && off.favorite)
        #expect(SidebarRowModel.make(channelId: "secret", session: session)?.icon == .private)
        #expect(SidebarRowModel.make(channelId: "muted", session: session)?.muted == true)
        #expect(SidebarRowModel.make(channelId: "old", session: session)?.icon == .archived)
        #expect(SidebarRowModel.make(channelId: "gm", session: session)?.icon == .group)
        let dm = SidebarRowModel.make(channelId: "dm-alice", session: session)!
        if case .direct(let userId, let status, let url) = dm.icon {
            #expect(userId == "alice" && status == .online && url != nil)
        } else {
            Issue.record("expected direct icon")
        }
        #expect(dm.title == "alice" && dm.isDirect)
        #expect(SidebarRowModel.make(channelId: "missing", session: session) == nil)
        let rows = ["town": town, "offtopic": off, "secret": SidebarRowModel.make(channelId: "secret", session: session)!]
        let section = SidebarSection(id: "s", title: "S", type: .channels, collapsed: true, channelIds: ["town", "offtopic", "secret", "nope"])
        #expect(SidebarRowModel.visibleIds(section: section, rows: rows) == ["town", "offtopic", "secret"])
        var open = section
        open.collapsed = false
        #expect(SidebarRowModel.visibleIds(section: open, rows: rows).count == 4)
    }

    @Test func smallHelpers() {
        #expect(SwitcherLabel.text(name: "Eng", unread: ChannelUnread(unread: true, mentions: 3), current: true) == "✓ Eng  (3)")
        #expect(SwitcherLabel.text(name: "Eng", unread: ChannelUnread(unread: true), current: false) == "Eng  •")
        #expect(SwitcherLabel.text(name: "Eng", unread: .none, current: false) == "Eng")
        #expect(ChannelHeader.subtitle(for: Channel(id: "c", name: "c", header: "line1\nline2", purpose: "p")) == "line1 line2")
        #expect(ChannelHeader.subtitle(for: Channel(id: "c", name: "c", purpose: "just purpose")) == "just purpose")
        #expect(ChannelIntro.text(for: Channel(id: "c", type: .direct, name: "a__b"), name: "alice").contains("conversation with alice"))
        #expect(ChannelIntro.text(for: Channel(id: "c", type: .group, name: "g"), name: "g").contains("group"))
        #expect(ChannelIntro.text(for: Channel(id: "c", name: "c", purpose: "Talk"), name: "C").hasSuffix("Talk"))
        #expect(ChannelIntro.text(for: Channel(id: "c", name: "c"), name: "C") == "This is the start of ~C.")
        let channels = [Channel(id: "1", name: "beta", displayName: "Beta"), Channel(id: "2", name: "alpha", displayName: "Alpha", purpose: "Fun stuff")]
        #expect(BrowseChannelsSheet.filtered(channels, query: "").map(\.id) == ["2", "1"])
        #expect(BrowseChannelsSheet.filtered(channels, query: "fun").map(\.id) == ["2"])
        #expect(FileChip.icon(for: FileInfo(id: "f", name: "a.zip", extension: "zip")) == "doc.zipper")
        #expect(FileChip.icon(for: FileInfo(id: "f", name: "a.mov", extension: "mov")) == "film")
        #expect(FileChip.icon(for: FileInfo(id: "f", name: "a.mp3", extension: "mp3")) == "waveform")
        #expect(FileChip.icon(for: FileInfo(id: "f", name: "a.pdf", extension: "pdf")) == "doc.richtext")
        #expect(FileChip.icon(for: FileInfo(id: "f", name: "a.swift", extension: "swift")) == "chevron.left.forwardslash.chevron.right")
        #expect(FileChip.icon(for: FileInfo(id: "f", name: "a.xyz", extension: "xyz")) == "doc")
        #expect(BlockView.headingSize(level: 1) == 22)
        #expect(BlockView.headingSize(level: 9) == 13.5)
        #expect(BlockView.headingSize(level: 0) == 22)
        #expect(ThumbnailSizing.size(width: 0, height: 0) == CGSize(width: 200, height: 140))
        #expect(ThumbnailSizing.size(width: 680, height: 240) == CGSize(width: 340, height: 120))
        #expect(ThumbnailSizing.size(width: 100, height: 50) == CGSize(width: 100, height: 50))
        #expect(ThumbnailSizing.size(width: 10, height: 2000).width == 48)
        #expect(ReactionTooltip.text(names: [], emojiName: "x") == "Nobody reacted with :x:")
        #expect(ReactionTooltip.text(names: ["a"], emojiName: "x") == "a reacted with :x:")
        #expect(ReactionTooltip.text(names: ["a", "b", "c"], emojiName: "x") == "a, b and c reacted with :x:")
        #expect(ReactionTooltip.text(names: ["a", "b", "c", "d", "e", "f", "g"], emojiName: "x") == "a, b, c, d, e and 2 others reacted with :x:")
    }

    @Test func attachmentSummary() {
        let value: JSONValue = .object([
            "pretext": .string("pre"), "title": .string("Title"), "text": .string("Body"), "color": .string("#ff0000"),
            "fields": .array([.object(["title": .string("F"), "value": .string("V")]), .object(["value": .string("no title")])]),
        ])
        let summary = AttachmentSummary(value)
        #expect(summary.pretext == "pre" && summary.title == "Title" && summary.text == "Body")
        #expect(summary.fields.count == 1 && summary.fields[0].0 == "F")
        #expect(AttachmentSummary(.object(["fallback": .string("fb")])).text == "fb")
        #expect(AttachmentSummary.color(hex: "good") == Theme.online)
        #expect(AttachmentSummary.color(hex: "warning") == Theme.away)
        #expect(AttachmentSummary.color(hex: "danger") == Theme.dnd)
        #expect(AttachmentSummary.color(hex: "zz") == nil)
        #expect(AttachmentSummary.color(hex: nil) == nil)
        #expect(AttachmentSummary.color(hex: "00ff00") != nil)
    }
}
