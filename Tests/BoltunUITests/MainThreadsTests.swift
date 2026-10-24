import AppKit
import Foundation
import SwiftUI
import Testing
@testable import BoltunKit
@testable import BoltunUI

@MainActor
@Suite struct CollapsedThreadsTimelineTests {
    func collapsedWorkspace() -> Workspace {
        let workspace = Fixture.workspace()
        let session = workspace.session
        session.collapsedThreads = true
        session.posts["p1"]?.lastReplyAt = Fixture.minutes(41)
        session.posts["p1"]?.participantIds = ["bob", "carol", "me", "alice"]
        return workspace
    }

    func row(_ items: [TimelineItem], _ id: String) -> MessageRowModel? {
        for item in items {
            if case .post(let model) = item, model.id == id { return model }
        }
        return nil
    }

    @Test func channelHidesRepliesAndSummarizesThreads() throws {
        let workspace = collapsedWorkspace()
        let items = workspace.channelItems(channelId: "town")
        #expect(row(items, "p3") == nil)
        #expect(row(items, "r1") == nil)
        let root = try #require(row(items, "p1"))
        let thread = try #require(root.thread)
        #expect(thread.replyCount == 2)
        #expect(thread.replyText == "2 replies")
        #expect(thread.participants.map(\.id) == ["alice", "me", "carol"])
        #expect(thread.participants.first?.name == "alice")
        #expect(thread.participants.first?.avatarURL?.absoluteString.contains("users/alice/image") == true)
        #expect(thread.lastReplyText == "Last reply 19 min ago")
        #expect(thread.hasNewReplies)
        #expect(root.replyContext == nil)
        #expect(row(items, "p2")?.thread == nil)
        #expect(row(items, "p4")?.isContinuation == false)
    }

    @Test func expandedChannelKeepsRepliesAndOldReplyButton() throws {
        let workspace = Fixture.workspace()
        let items = workspace.channelItems(channelId: "town")
        #expect(row(items, "p3") != nil)
        #expect(row(items, "r1")?.replyContext?.rootId == "p1")
        let root = try #require(row(items, "p1"))
        #expect(root.thread == nil)
        #expect(root.replyCount == 2)
    }

    @Test func openingThreadClearsNewRepliesMarker() async throws {
        let workspace = collapsedWorkspace()
        await workspace.openThread(rootId: "p1")
        #expect(try #require(row(workspace.channelItems(channelId: "town"), "p1")?.thread).hasNewReplies == false)
        workspace.closeRightPane()
        #expect((workspace.threadSeenAt["p1"] ?? 0) >= Fixture.now.mattermostMillis)
        #expect(try #require(row(workspace.channelItems(channelId: "town"), "p1")?.thread).hasNewReplies == false)
        workspace.session.posts["p1"]?.lastReplyAt = Fixture.now.mattermostMillis + 60_000
        #expect(try #require(row(workspace.channelItems(channelId: "town"), "p1")?.thread).hasNewReplies)
    }

    @Test func switchingThreadsMarksPreviousAsSeen() async {
        let workspace = collapsedWorkspace()
        await workspace.openThread(rootId: "p1")
        workspace.threadSeenAt["p1"] = 0
        await workspace.openThread(rootId: "p2")
        #expect((workspace.threadSeenAt["p1"] ?? 0) > 0)
        workspace.markThreadSeen("p1")
        let seen = workspace.threadSeenAt["p1"]
        workspace.now = { Fixture.now.addingTimeInterval(-3600) }
        workspace.markThreadSeen("p1")
        #expect(workspace.threadSeenAt["p1"] == seen)
    }

    @Test func threadSummaryRules() {
        var context = TimelineContext(myId: "me", myUsername: "boltun", lastViewedAt: 100, now: Fixture.now, calendar: Fixture.calendar, collapsedThreads: true)
        context.userName = { $0.uppercased() }
        let root = Post(id: "r", createAt: 1, userId: "a", channelId: "c", message: "x", replyCount: 1, lastReplyAt: 0, participantIds: ["b"])
        let summary = TimelineBuilder.threadSummary(for: root, context: context)
        #expect(summary?.replyText == "1 reply")
        #expect(summary?.lastReplyText == "")
        #expect(summary?.participants.map(\.name) == ["B"])
        #expect(summary?.hasNewReplies == false)
        var fresh = root
        fresh.lastReplyAt = 200
        #expect(TimelineBuilder.threadSummary(for: fresh, context: context)?.hasNewReplies == true)
        context.openThreadId = "r"
        #expect(TimelineBuilder.threadSummary(for: fresh, context: context)?.hasNewReplies == false)
        context.openThreadId = nil
        context.threadSeenAt = { _ in 300 }
        #expect(TimelineBuilder.threadSummary(for: fresh, context: context)?.hasNewReplies == false)
        context.lastViewedAt = 0
        context.threadSeenAt = { _ in 0 }
        #expect(TimelineBuilder.threadSummary(for: fresh, context: context)?.hasNewReplies == false)
        var none = root
        none.replyCount = 0
        #expect(TimelineBuilder.threadSummary(for: none, context: context) == nil)
        var reply = root
        reply.rootId = "other"
        #expect(TimelineBuilder.threadSummary(for: reply, context: context) == nil)
        var deleted = root
        deleted.deleteAt = 5
        #expect(TimelineBuilder.threadSummary(for: deleted, context: context) == nil)
    }

    @Test func highlightingReplyOpensItsThreadWhenCollapsed() async {
        let workspace = collapsedWorkspace()
        workspace.highlightDuration = .seconds(30)
        await workspace.highlight(postId: "r1")
        #expect(workspace.threadRootId == "p1")
        #expect(workspace.highlightedPostId == "r1")
        #expect(workspace.scrollRequest?.target == .post("p1"))
        await workspace.highlight(postId: "p3")
        #expect(workspace.threadRootId == "p1")
        #expect(workspace.highlightedPostId == "p3")
    }

    @Test func highlightingReplyStaysInChannelWhenExpanded() async {
        let workspace = Fixture.workspace()
        workspace.highlightDuration = .seconds(30)
        await workspace.highlight(postId: "r1")
        #expect(workspace.threadRootId == nil)
        #expect(workspace.scrollRequest?.target == .post("r1"))
    }

    @Test func threadScrollTargetRequiresVisibleHighlightedPost() {
        let items = TimelineBuilder.threadItems(posts: Fixture.townPosts().filter { $0.id == "p1" || $0.rootId == "p1" }, context: TimelineContext(myId: "me", myUsername: "boltun"))
        #expect(ThreadScrollTarget.target(highlighted: "r1", items: items) == "r1")
        #expect(ThreadScrollTarget.target(highlighted: "p8", items: items) == nil)
        #expect(ThreadScrollTarget.target(highlighted: nil, items: items) == nil)
    }

    @Test func relativeTimes() {
        let now = Fixture.now
        let calendar = Fixture.calendar
        #expect(TimeFormatting.relative(now.addingTimeInterval(-20), now: now, calendar: calendar) == "just now")
        #expect(TimeFormatting.relative(now.addingTimeInterval(-300), now: now, calendar: calendar) == "5 min ago")
        #expect(TimeFormatting.relative(now.addingTimeInterval(-7200), now: now, calendar: calendar) == "2 hr ago")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        #expect(TimeFormatting.relative(yesterday, now: now, calendar: calendar) == "yesterday")
        let older = calendar.date(byAdding: .day, value: -10, to: now)!
        #expect(TimeFormatting.relative(older, now: now, calendar: calendar) == TimeFormatting.short(older, now: now, calendar: calendar))
    }

    @Test func rendersThreadSummaryRows() async {
        let workspace = collapsedWorkspace()
        let view = MessageListView(workspace: workspace, channelId: "town")
        let rep = await MainSnapshot.render(view, size: CGSize(width: 760, height: 700), name: "collapsed-threads", settle: .milliseconds(600))
        #expect(MainSnapshot.distinctColors(rep) > 8)
        let summary = ThreadSummary(replyCount: 3, participants: [ThreadParticipant(id: "a", name: "Alice", avatarURL: nil)], lastReplyText: "Last reply just now", hasNewReplies: true)
        let button = await MainSnapshot.render(ThreadSummaryButton(summary: summary, client: nil) {}, size: CGSize(width: 320, height: 40), name: "thread-summary")
        #expect(MainSnapshot.distinctColors(button) > 3)
    }
}

@MainActor
@Suite struct TeamRailOrderingTests {
    @Test func tilesFollowLayoutWithFavoritesFirst() {
        let session = Fixture.session()
        session.teams.append(Team(id: "t3", name: "ops", displayName: "Operations"))
        session.setFavorite(teamId: "t3", favorite: true)
        let tiles = TeamTileModel.make(session: session)
        #expect(tiles.map(\.id) == ["t3", "t1", "t2"])
        #expect(tiles.map(\.favorite) == [true, false, false])
        #expect(tiles.map(\.index) == [0, 1, 2])
        #expect(tiles[0].tooltip == "Operations — ⌃⌘1")
        #expect(tiles[0].previousId == nil && tiles[0].nextId == nil)
        #expect(tiles[1].previousId == nil && tiles[1].nextId == "t2")
        #expect(tiles[2].previousId == "t1" && tiles[2].nextId == nil)
    }

    @Test func shortcutsAndCyclingFollowDisplayedOrder() async {
        let workspace = Fixture.workspace()
        let session = workspace.session
        session.loadedTeams = ["t1", "t2"]
        session.moveTeam("t2", to: "t1")
        await session.switchTeam(number: 1)
        #expect(session.currentTeamId == "t2")
        await session.cycleTeam(offset: 1)
        #expect(session.currentTeamId == "t1")
    }

    @Test func dropTargetsMoveTeams() {
        let session = Fixture.session()
        session.teams.append(Team(id: "t3", name: "ops", displayName: "Operations"))
        session.moveTeam("t3", onto: .team("t1"))
        #expect(session.orderedTeams.map(\.id) == ["t3", "t1", "t2"])
        session.moveTeam("t1", onto: .endOfFavorites)
        #expect(session.teamSections.favorites.map(\.id) == ["t1"])
        session.moveTeam("t1", onto: .endOfOthers)
        #expect(session.teamSections.favorites.isEmpty)
        #expect(session.orderedTeams.map(\.id) == ["t3", "t2", "t1"])
    }

    @Test func dropDelegateMovesDraggedTeamOnly() {
        let session = Fixture.session()
        var dragging: String? = "t2"
        let binding = Binding(get: { dragging }, set: { dragging = $0 })
        let delegate = TeamDropDelegate(target: .team("t1"), session: session, dragging: binding)
        #expect(delegate.target == .team("t1"))
        let idle = TeamDropDelegate(target: .endOfFavorites, session: session, dragging: .constant(nil))
        #expect(idle.target == .endOfFavorites)
        #expect(session.orderedTeams.map(\.id) == ["t1", "t2"])
        #expect(dragging == "t2")
    }

    @Test func rendersRailWithFavoritesDivider() async {
        let (model, session) = Fixture.appModel()
        await model.selectServer(at: 0)
        session.teams.append(Team(id: "t3", name: "ops", displayName: "Operations"))
        session.setFavorite(teamId: "t2", favorite: true)
        let rail = await MainSnapshot.render(LeftRail(model: model, onAddServer: {}), size: CGSize(width: LeftRail.width, height: 400), name: "left-rail-favorites")
        #expect(MainSnapshot.distinctColors(rail) > 4)
        #expect(model.servers[0].teamLayout.favorites == ["t2"])
        let menu = await MainSnapshot.render(VStack { TeamTileMenu(tile: TeamTileModel.make(session: session)[1], session: session) }, size: CGSize(width: 200, height: 120))
        #expect(menu.pixelsWide >= 200)
        let divider = await MainSnapshot.render(TeamSectionDivider(), size: CGSize(width: LeftRail.width, height: 9))
        #expect(divider.pixelsWide >= Int(LeftRail.width))
    }
}
