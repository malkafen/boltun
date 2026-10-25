import AppKit
import SwiftUI
import Testing
@testable import BoltunKit
@testable import BoltunUI

@Suite struct ReactionModelTests {
    let me = ReactionPerson(id: "me", name: "Alice", isMe: true)
    let bob = ReactionPerson(id: "bob", name: "Bob", isMe: false)
    let carol = ReactionPerson(id: "carol", name: "Carol", isMe: false, avatarURL: URL(string: "http://a/carol"))

    @Test func meIsListedFirstAsYou() {
        #expect(ReactionPerson.meFirst([bob, me, carol]) == [me, bob, carol])
        #expect(ReactionPerson.meFirst([bob, carol]) == [bob, carol])
        #expect(ReactionPerson.meFirst([]) == [])
        #expect(me.displayName == "You")
        #expect(bob.displayName == "Bob")
    }

    @Test func chipTooltipNamesEveryone() {
        let chip = ReactionChipModel(emojiName: "tada", glyph: "🎉", count: 3, isMine: true, people: [me, bob, carol])
        #expect(chip.userNames == ["You", "Bob", "Carol"])
        #expect(chip.tooltip == "You, Bob and Carol reacted with :tada:")
    }

    @Test func reactionTexts() {
        #expect(ReactionText.reactedWith("+1") == "Reacted with :+1:")
        #expect(ReactionText.peopleCount(1) == "1 person reacted")
        #expect(ReactionText.peopleCount(4) == "4 people reacted")
        #expect(ReactionText.toggleTitle(isMine: true) == "Remove Reaction")
        #expect(ReactionText.toggleTitle(isMine: false) == "Add Reaction")
        #expect(ReactionText.clickHint(isMine: true, emojiName: "x") == "Click to remove your reaction")
        #expect(ReactionText.clickHint(isMine: false, emojiName: "x") == "Click to react with :x:")
        #expect(ReactionText.viewAllTitle == "View All Reactions")
        #expect(ReactionText.viewAllLink == "View all")
        #expect(ReactionText.allTab == "All")
        #expect(ReactionText.you == "(you)")
        #expect(ReactionText.viewProfile("Bob") == "View profile of Bob")
    }

    @Test func chipExposesItsEmoji() {
        let custom = ReactionChipModel(emojiName: "party", customEmojiId: "e1", count: 1, isMine: false, people: [bob])
        #expect(custom.emoji == ReactionEmoji(name: "party", glyph: nil, customEmojiId: "e1"))
        let unicode = ReactionChipModel(emojiName: "tada", glyph: "🎉", count: 1, isMine: false, people: [bob])
        #expect(unicode.emoji == ReactionEmoji(name: "tada", glyph: "🎉"))
        #expect(ReactorEntry(person: bob).id == "bob")
        #expect(ReactorEntry(person: bob).emojis.isEmpty)
    }
}

@Suite struct ReactionBreakdownTests {
    let me = ReactionPerson(id: "me", name: "Alice", isMe: true)
    let bob = ReactionPerson(id: "bob", name: "Bob", isMe: false)
    let carol = ReactionPerson(id: "carol", name: "Carol", isMe: false)

    var thumbs: ReactionChipModel { ReactionChipModel(emojiName: "+1", glyph: "👍", count: 2, isMine: false, people: [bob, carol]) }
    var tada: ReactionChipModel { ReactionChipModel(emojiName: "tada", glyph: "🎉", count: 2, isMine: true, people: [me, bob]) }
    var breakdown: ReactionBreakdown { ReactionBreakdown(reactions: [thumbs, tada]) }

    @Test func tabsStartWithAllFollowedByEachEmoji() {
        #expect(breakdown.tabs == [.all, .emoji("+1"), .emoji("tada")])
        #expect(ReactionBreakdown(reactions: []).tabs == [.all])
    }

    @Test func countsPerTab() {
        #expect(breakdown.totalCount == 4)
        #expect(breakdown.count(for: .all) == 4)
        #expect(breakdown.count(for: .emoji("+1")) == 2)
        #expect(breakdown.count(for: .emoji("tada")) == 2)
        #expect(breakdown.count(for: .emoji("gone")) == 4)
    }

    @Test func everyoneIsListedOnceWithAllTheirEmojiAndMeFirst() {
        let everyone = breakdown.everyone
        #expect(everyone.map(\.id) == ["me", "bob", "carol"])
        #expect(everyone[0].emojis.map(\.name) == ["tada"])
        #expect(everyone[1].emojis.map(\.name) == ["+1", "tada"])
        #expect(everyone[2].emojis == [thumbs.emoji])
        #expect(breakdown.entries(for: .all) == everyone)
        #expect(ReactionBreakdown(reactions: []).everyone.isEmpty)
    }

    @Test func emojiTabListsOnlyThatReaction() {
        #expect(breakdown.entries(for: .emoji("+1")) == [ReactorEntry(person: bob), ReactorEntry(person: carol)])
        #expect(breakdown.entries(for: .emoji("tada")).map(\.id) == ["me", "bob"])
    }

    @Test func missingEmojiTabFallsBackToAll() {
        #expect(breakdown.resolved(.emoji("gone")) == .all)
        #expect(breakdown.resolved(.emoji("tada")) == .emoji("tada"))
        #expect(breakdown.resolved(.all) == .all)
        #expect(breakdown.entries(for: .emoji("gone")) == breakdown.everyone)
    }

    @Test func listLayoutCapsVisibleRowsAndScalesRows() {
        #expect(ReactorListLayout.visibleRows(count: 0, limit: 10) == 1)
        #expect(ReactorListLayout.visibleRows(count: 3, limit: 10) == 3)
        #expect(ReactorListLayout.visibleRows(count: 40, limit: 10) == 10)
        #expect(ReactorListLayout.visibleRows(count: 40, limit: 0) == 1)
        #expect(ReactorListLayout.rowHeight(fontScale: 1) == 26)
        #expect(ReactorListLayout.rowHeight(fontScale: 1.5) == 39)
        #expect(ReactorListLayout.rowHeight(fontScale: 0.5) == 24)
        #expect(ReactorListLayout.height(visibleRows: 10, rowHeight: 26) == 260)
        #expect(ReactorListLayout.scrolls(count: 40, visibleRows: 10))
        #expect(!ReactorListLayout.scrolls(count: 10, visibleRows: 10))
    }
}

@Suite struct HoverCardHoverStateTests {
    @Test func passiveCardHidesAsSoonAsThePointerLeavesTheAnchor() {
        var state = HoverCardHoverState(overAnchor: true)
        #expect(state.action == .keep)
        #expect(state.pointer(overCard: true) == .keep)
        #expect(state.pointer(overAnchor: false) == .hideNow)
        #expect(!state.isHovered)
    }

    @Test func interactiveCardWaitsForGraceAndStaysOpenInsideTheCard() {
        var state = HoverCardHoverState(interactive: true, overAnchor: true)
        #expect(state.pointer(overAnchor: false) == .hideAfterGrace)
        #expect(state.pointer(overCard: true) == .keep)
        #expect(state.isHovered)
        #expect(state.pointer(overCard: false) == .hideAfterGrace)
        #expect(state.pointer(overAnchor: true) == .keep)
        #expect(state.pointer(overCard: true) == .keep)
        #expect(state.pointer(overAnchor: false) == .keep)
    }
}

@Suite struct HoverCardPlacementTests {
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 240, height: 120)

    @Test func placesAboveTheAnchorAlignedToItsLeadingEdge() {
        let frame = HoverCardPlacement.frame(size: size, anchor: CGRect(x: 100, y: 300, width: 40, height: 22), visible: visible)
        #expect(frame == CGRect(x: 100, y: 328, width: 240, height: 120))
    }

    @Test func flipsBelowWhenThereIsNoRoomAbove() {
        let frame = HoverCardPlacement.frame(size: size, anchor: CGRect(x: 100, y: 700, width: 40, height: 22), visible: visible)
        #expect(frame == CGRect(x: 100, y: 574, width: 240, height: 120))
    }

    @Test func staysAboveWhenNeitherSideFits() {
        let tall = CGSize(width: 240, height: 700)
        let frame = HoverCardPlacement.frame(size: tall, anchor: CGRect(x: 100, y: 300, width: 40, height: 22), visible: visible)
        #expect(frame.minY == 328)
    }

    @Test func clampsHorizontallyInsideTheScreen() {
        let right = HoverCardPlacement.frame(size: size, anchor: CGRect(x: 950, y: 300, width: 40, height: 22), visible: visible)
        #expect(right.maxX == 996)
        let left = HoverCardPlacement.frame(size: size, anchor: CGRect(x: -50, y: 300, width: 40, height: 22), visible: visible)
        #expect(left.minX == 4)
        let narrow = HoverCardPlacement.frame(size: size, anchor: CGRect(x: 50, y: 300, width: 40, height: 22), visible: CGRect(x: 0, y: 0, width: 100, height: 800))
        #expect(narrow.minX == 4)
    }

    @Test func interactiveCardLeavesOnlyASmallGapToCross() {
        let anchor = CGRect(x: 100, y: 300, width: 40, height: 22)
        let above = HoverCardPlacement.frame(size: size, anchor: anchor, visible: visible)
        #expect(above.minY - anchor.maxY == HoverCardPlacement.gap)
        let below = HoverCardPlacement.frame(size: size, anchor: CGRect(x: 100, y: 700, width: 40, height: 22), visible: visible)
        #expect(700 - below.maxY == HoverCardPlacement.gap)
    }
}

@Suite(.serialized) @MainActor struct HoverCardPanelTests {
    let anchor = CGRect(x: 200, y: 200, width: 40, height: 22)
    let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)

    @Test func showsUpdatesAndHidesOnlyForItsOwner() {
        let panel = HoverCardPanel()
        let owner = UUID()
        let other = UUID()
        #expect(!panel.isVisible)
        panel.show(Text("Short").padding(4), owner: owner, anchor: anchor, visible: screen)
        #expect(panel.isVisible)
        #expect(panel.owner == owner)
        #expect(!panel.isInteractive)
        #expect(panel.frame.minY == anchor.maxY + HoverCardPlacement.gap)
        let shortHeight = panel.frame.height
        panel.update(VStack { Text("Taller"); Text("Card"); Text("Now") }.padding(4), owner: owner)
        #expect(panel.frame.height > shortHeight)
        #expect(panel.frame.minY == anchor.maxY + HoverCardPlacement.gap)
        let tallHeight = panel.frame.height
        panel.update(Text("Ignored"), owner: other)
        #expect(panel.frame.height == tallHeight)
        panel.hide(owner: other)
        #expect(panel.isVisible)
        panel.hide(owner: owner)
        #expect(!panel.isVisible)
        panel.show(Text("Fallback"), owner: other, anchor: anchor, visible: nil)
        #expect(panel.owner == other)
        panel.hide(owner: other)
    }

    @Test func passiveCardHidesImmediatelyWhenLeavingTheAnchor() {
        let panel = HoverCardPanel()
        let owner = UUID()
        panel.show(Text("Profile"), owner: owner, anchor: anchor, visible: screen)
        panel.pointer(overCard: true)
        panel.pointer(overAnchor: false, owner: UUID())
        #expect(panel.isVisible)
        panel.pointer(overAnchor: false, owner: owner)
        #expect(!panel.isVisible)
        #expect(panel.pendingHide == nil)
        #expect(panel.hover == HoverCardHoverState())
    }

    @Test func interactiveCardHidesAfterGraceWhenThePointerGoesElsewhere() async {
        let panel = HoverCardPanel(grace: .milliseconds(5))
        let owner = UUID()
        panel.show(Text("Reactors"), owner: owner, anchor: anchor, visible: screen, interactive: true)
        #expect(panel.isInteractive)
        #expect(panel.hover == HoverCardHoverState(interactive: true, overAnchor: true))
        panel.pointer(overAnchor: false, owner: owner)
        #expect(panel.isVisible)
        #expect(panel.pendingHide != nil)
        await panel.pendingHide?.value
        #expect(!panel.isVisible)
        #expect(!panel.isInteractive)
    }

    @Test func interactiveCardStaysOpenWhileThePointerIsInsideIt() async {
        let panel = HoverCardPanel(grace: .milliseconds(5))
        let owner = UUID()
        panel.show(Text("Reactors"), owner: owner, anchor: anchor, visible: screen, interactive: true)
        panel.pointer(overAnchor: false, owner: owner)
        let pending = panel.pendingHide
        panel.pointer(overCard: true)
        #expect(panel.pendingHide == nil)
        await pending?.value
        #expect(panel.isVisible)
        panel.pointer(overCard: false)
        panel.pointer(overAnchor: true, owner: owner)
        #expect(panel.pendingHide == nil)
        #expect(panel.isVisible)
        panel.pointer(overAnchor: false, owner: owner)
        await panel.pendingHide?.value
        #expect(!panel.isVisible)
    }

    @Test func pendingHideSkipsWhenHoveredAgainAndIsCancelledByANewCard() async {
        let panel = HoverCardPanel(grace: .milliseconds(5))
        let first = UUID()
        let second = UUID()
        panel.show(Text("First"), owner: first, anchor: anchor, visible: screen, interactive: true)
        panel.pointer(overAnchor: false, owner: first)
        panel.show(Text("Second"), owner: second, anchor: anchor, visible: screen, interactive: true)
        #expect(panel.pendingHide == nil)
        #expect(panel.owner == second)
        panel.close()
        #expect(!panel.isVisible)
        panel.close()
        panel.pointer(overCard: true)
        #expect(panel.hover == HoverCardHoverState())
    }

    @Test func hostingViewTracksThePointerAndAcceptsFirstClick() {
        let hosting = HoverCardHostingView(rootView: AnyView(Text("Card")))
        hosting.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        hosting.updateTrackingAreas()
        hosting.updateTrackingAreas()
        let areas = hosting.trackingAreas.filter { $0.owner === hosting && $0.options.contains(.activeAlways) }
        #expect(areas.count == 1)
        #expect(areas.first?.options.contains(.mouseEnteredAndExited) == true)
        #expect(hosting.acceptsFirstMouse(for: nil))
    }

    @Test func anchorReportsScreenRectOnlyInsideAWindow() {
        let anchor = HoverCardAnchor()
        #expect(anchor.screenRect == nil)
        #expect(anchor.visibleFrame == nil)
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        let view = NSView(frame: CGRect(x: 10, y: 20, width: 50, height: 30))
        window.contentView?.addSubview(view)
        anchor.view = view
        #expect(anchor.screenRect == CGRect(x: 110, y: 120, width: 50, height: 30))
        #expect(HoverCardModifier<Int, EmptyView>.delay == .milliseconds(350))
        #expect(HoverCardPanel.grace == .milliseconds(250))
    }
}

@Suite(.serialized) @MainActor struct ReactionSnapshotTests {
    func people(_ count: Int) -> [ReactionPerson] {
        [ReactionPerson(id: "me", name: "Alice Liddell", isMe: true)]
            + (1..<count).map { ReactionPerson(id: "u\($0)", name: "Teammate \($0)", isMe: false) }
    }

    @Test func reactorsCardListsEveryoneInAScrollableList() async {
        let reaction = ReactionChipModel(emojiName: "+1", glyph: "👍", count: 40, isMine: true, people: people(40))
        var selected: [String] = []
        var viewAll = 0
        let card = ReactorsCard(reaction: reaction, client: nil, onSelectPerson: { selected.append($0.id) }, onViewAll: { viewAll += 1 })
        let rep = await MainSnapshot.render(card, size: CGSize(width: ReactorsCard.width, height: 420), name: "reactors-card")
        #expect(MainSnapshot.distinctColors(rep) > 4)
        let hosting = NSHostingView(rootView: card)
        let listHeight = ReactorListLayout.height(visibleRows: ReactorsCard.maxVisibleRows, rowHeight: ReactorListLayout.rowHeight(fontScale: 1))
        #expect(hosting.fittingSize.height > listHeight)
        #expect(hosting.fittingSize.height < listHeight + 140)
        let single = ReactionChipModel(emojiName: "party", customEmojiId: "e1", count: 1, isMine: false, people: [ReactionPerson(id: "bob", name: "Bob", isMe: false)])
        await MainSnapshot.render(ReactorsCard(reaction: single, client: nil), size: CGSize(width: ReactorsCard.width, height: 140))
        #expect(selected.isEmpty)
        #expect(viewAll == 0)
    }

    @Test func chipAndMenuRender() async {
        let reaction = ReactionChipModel(emojiName: "tada", glyph: "🎉", count: 2, isMine: false, people: people(2))
        var toggled = 0
        let view = VStack {
            ReactionChip(reaction: reaction, client: nil) { toggled += 1 }
            ReactionChip(reaction: reaction, client: nil, onSelectPerson: { _ in toggled += 1 }, onViewAll: { toggled += 1 }) { toggled += 1 }
            ReactionMenu(reaction: reaction) { toggled += 1 }
            ReactionMenu(reaction: reaction, onViewAll: { toggled += 1 }) { toggled += 1 }
        }
        let rep = await MainSnapshot.render(view.background(Theme.content), size: CGSize(width: 240, height: 200), name: "reaction-chip-menu")
        #expect(rep.pixelsWide >= 240)
        #expect(toggled == 0)
    }

    @Test func reactorRowsRenderPlainAndClickable() async {
        let person = ReactionPerson(id: "me", name: "Alice Liddell", isMe: true)
        let emojis = [ReactionEmoji(name: "tada", glyph: "🎉"), ReactionEmoji(name: "party", customEmojiId: "e1")]
        var selected = 0
        let view = VStack(spacing: 0) {
            ReactorRow(person: person, emojis: emojis, client: nil)
            ReactorRow(person: person, client: nil) { _ in selected += 1 }
        }
        let rep = await MainSnapshot.render(view.background(Theme.popover), size: CGSize(width: 300, height: 60), name: "reactor-rows")
        #expect(MainSnapshot.distinctColors(rep) > 3)
        #expect(selected == 0)
    }

    @Test func allReactionsViewRendersTabsForEveryEmoji() async {
        let crowd = people(30)
        let reactions = [
            ReactionChipModel(emojiName: "+1", glyph: "👍", count: 30, isMine: true, people: crowd),
            ReactionChipModel(emojiName: "tada", glyph: "🎉", count: 2, isMine: false, people: Array(crowd.suffix(2))),
            ReactionChipModel(emojiName: "party", customEmojiId: "e1", count: 1, isMine: false, people: [crowd[3]]),
        ]
        let rep = await MainSnapshot.render(AllReactionsView(reactions: reactions, client: nil), size: CGSize(width: AllReactionsView.width, height: 420), name: "all-reactions")
        #expect(MainSnapshot.distinctColors(rep) > 4)
        await MainSnapshot.render(AllReactionsView(reactions: reactions, client: nil, selection: .emoji("tada")), size: CGSize(width: AllReactionsView.width, height: 420), name: "all-reactions-tada")
        await MainSnapshot.render(AllReactionsView(reactions: reactions, client: nil, selection: .emoji("gone")), size: CGSize(width: AllReactionsView.width, height: 420))
        let fitted = NSHostingView(rootView: AllReactionsView(reactions: reactions, client: nil)).fittingSize
        let tabFitted = NSHostingView(rootView: AllReactionsView(reactions: reactions, client: nil, selection: .emoji("tada"))).fittingSize
        #expect(fitted.width == AllReactionsView.width)
        #expect(fitted.height == tabFitted.height)
    }

    @Test func tabButtonRendersSelectedAndIdle() async {
        var tapped = 0
        let view = HStack {
            ReactionTabButton(count: 3, isSelected: true, action: { tapped += 1 }) { Text("All") }
            ReactionTabButton(count: 1, isSelected: false, action: { tapped += 1 }) { Text("🎉") }
        }
        let rep = await MainSnapshot.render(view.background(Theme.popover), size: CGSize(width: 160, height: 40))
        #expect(rep.pixelsWide >= 160)
        #expect(tapped == 0)
    }
}

@Suite(.serialized) @MainActor struct ReactionMessageRowTests {
    func reactedRow(_ workspace: Workspace) -> MessageRowModel {
        var post = Post(id: "rx", createAt: Fixture.minutes(30), userId: "alice", channelId: "town", message: "reacted")
        post.metadata.reactions = [Reaction(userId: "bob", postId: "rx", emojiName: "+1"), Reaction(userId: "me", postId: "rx", emojiName: "tada")]
        let context = workspace.timelineContext(lastViewedAt: 0, showReplyContext: true)
        return TimelineBuilder.row(for: post, previous: nil, continuation: false, context: context)
    }

    @Test func selectingAReactorOpensTheirProfileAnchoredToTheReactions() {
        let workspace = Fixture.workspace()
        let model = reactedRow(workspace)
        let bob = ReactionPerson(id: "bob", name: "Bob", isMe: false)
        let row = MessageRow(model: model, workspace: workspace)
        #expect(row.reactionProfileAnchor == ProfileAnchor(surface: .channel, kind: .reaction, id: "rx"))
        row.showReactorProfile(bob)
        #expect(workspace.profilePopover?.anchor == row.reactionProfileAnchor)
        #expect(workspace.profilePopover?.request == ProfilePopoverRequest(userId: "bob", channelId: "town"))
        let thread = MessageRow(model: model, workspace: workspace, inThread: true)
        thread.showReactorProfile(bob)
        #expect(workspace.profilePopover?.anchor == ProfileAnchor(surface: .thread, kind: .reaction, id: "rx"))
    }

    @Test func rowWithReactionsRendersWithProfileAnchor() async {
        let workspace = Fixture.workspace()
        let model = reactedRow(workspace)
        #expect(model.reactions.map(\.emojiName) == ["+1", "tada"])
        let row = MessageRow(model: model, workspace: workspace, hovering: true)
        workspace.showProfile(ProfilePopoverRequest(userId: "bob", channelId: "town"), anchor: row.reactionProfileAnchor)
        let rep = await MainSnapshot.render(row.background(Theme.content), size: CGSize(width: 600, height: 120), name: "message-row-reactions")
        #expect(MainSnapshot.distinctColors(rep) > 4)
        workspace.hideProfile()
    }
}
