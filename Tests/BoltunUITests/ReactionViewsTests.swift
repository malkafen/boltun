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
        #expect(ReactionText.overflow(count: 12, shown: 12) == nil)
        #expect(ReactionText.overflow(count: 15, shown: 12) == "and 3 more")
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
}

@Suite(.serialized) @MainActor struct HoverCardPanelTests {
    @Test func showsUpdatesAndHidesOnlyForItsOwner() {
        let panel = HoverCardPanel()
        let owner = UUID()
        let other = UUID()
        #expect(!panel.isVisible)
        let anchor = CGRect(x: 200, y: 200, width: 40, height: 22)
        panel.show(Text("Short").padding(4), owner: owner, anchor: anchor, visible: CGRect(x: 0, y: 0, width: 1200, height: 900))
        #expect(panel.isVisible)
        #expect(panel.owner == owner)
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
    }
}

@Suite(.serialized) @MainActor struct ReactionSnapshotTests {
    func people(_ count: Int) -> [ReactionPerson] {
        [ReactionPerson(id: "me", name: "Alice Liddell", isMe: true)]
            + (1..<count).map { ReactionPerson(id: "u\($0)", name: "Teammate \($0)", isMe: false) }
    }

    @Test func reactorsCardListsPeopleWithOverflow() async {
        let reaction = ReactionChipModel(emojiName: "+1", glyph: "👍", count: 15, isMine: true, people: people(15))
        let rep = await MainSnapshot.render(ReactorsCard(reaction: reaction, client: nil), size: CGSize(width: 240, height: 420), name: "reactors-card")
        #expect(MainSnapshot.distinctColors(rep) > 4)
        let single = ReactionChipModel(emojiName: "party", customEmojiId: "e1", count: 1, isMine: false, people: [ReactionPerson(id: "bob", name: "Bob", isMe: false)])
        await MainSnapshot.render(ReactorsCard(reaction: single, client: nil), size: CGSize(width: 240, height: 140))
    }

    @Test func chipAndMenuRender() async {
        let reaction = ReactionChipModel(emojiName: "tada", glyph: "🎉", count: 2, isMine: false, people: people(2))
        var toggled = 0
        let view = VStack {
            ReactionChip(reaction: reaction, client: nil) { toggled += 1 }
            ReactionMenu(reaction: reaction) { toggled += 1 }
        }
        let rep = await MainSnapshot.render(view.background(Theme.content), size: CGSize(width: 240, height: 160), name: "reaction-chip-menu")
        #expect(rep.pixelsWide >= 240)
        #expect(toggled == 0)
    }
}
