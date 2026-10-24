import AppKit
import Foundation
import SwiftUI
import Testing
@testable import BoltunKit
@testable import BoltunUI

@MainActor
@Suite struct PresenceAndFollowingUITests {
    func row(_ items: [TimelineItem], _ id: String) -> MessageRowModel? {
        for item in items {
            if case .post(let model) = item, model.id == id { return model }
        }
        return nil
    }

    func collapsedWorkspace(transport: RoutedTransport = Fixture.transport()) -> Workspace {
        let workspace = Fixture.workspace(transport: transport)
        workspace.session.collapsedThreads = true
        return workspace
    }

    @Test func rowsCarryAuthorStatus() throws {
        let workspace = Fixture.workspace()
        let items = workspace.channelItems(channelId: "town")
        #expect(row(items, "p1")?.authorStatus == .online)
        #expect(row(items, "p3")?.authorStatus == .away)
        #expect(row(items, "p5")?.authorStatus == .dnd)
        #expect(row(items, "p4")?.authorStatus == nil)
        #expect(row(items, "p0")?.authorStatus == nil)
        workspace.session.statuses["me"] = .online
        #expect(row(workspace.channelItems(channelId: "town"), "p4")?.authorStatus == .online)
    }

    @Test func webhookPostsHaveNoStatus() {
        var context = TimelineContext(myId: "me", myUsername: "boltun")
        context.status = { _ in .online }
        let hook = Post(id: "h", userId: "alice", channelId: "c", message: "x", props: ["from_webhook": .bool(true), "override_username": .string("ci")])
        #expect(TimelineBuilder.authorStatus(for: hook, context: context) == nil)
        let anonymous = Post(id: "a", userId: "", channelId: "c", message: "x")
        #expect(TimelineBuilder.authorStatus(for: anonymous, context: context) == nil)
        #expect(TimelineBuilder.authorStatus(for: Post(id: "b", userId: "bob", channelId: "c", message: "x"), context: context) == .online)
    }

    @Test func followStateOnlyForRootPostsInCollapsedMode() throws {
        let expanded = Fixture.workspace()
        #expect(row(expanded.channelItems(channelId: "town"), "p1")?.following == nil)
        let workspace = collapsedWorkspace()
        let items = workspace.channelItems(channelId: "town")
        #expect(row(items, "p1")?.following == false)
        #expect(row(items, "p4")?.following == true)
        #expect(row(items, "p0")?.following == nil)
        #expect(row(items, "p7")?.following == nil)
        workspace.session.posts["p1"]?.isFollowing = true
        #expect(row(workspace.channelItems(channelId: "town"), "p1")?.following == true)
    }

    @Test func followRules() {
        var context = TimelineContext(myId: "me", myUsername: "boltun", followThreads: true)
        context.isFollowing = { $0 == "root" }
        #expect(TimelineBuilder.following(for: Post(id: "root", userId: "a", channelId: "c", message: "x"), context: context) == true)
        #expect(TimelineBuilder.following(for: Post(id: "other", userId: "a", channelId: "c", message: "x"), context: context) == false)
        #expect(TimelineBuilder.following(for: Post(id: "r", userId: "a", channelId: "c", rootId: "root", message: "x"), context: context) == nil)
        #expect(TimelineBuilder.following(for: Post(id: "pending", userId: "me", channelId: "c", message: "x", pendingPostId: "pending"), context: context) == nil)
        #expect(TimelineBuilder.following(for: Post(id: "sent", userId: "me", channelId: "c", message: "x", pendingPostId: "pending"), context: context) == false)
        context.followThreads = false
        #expect(TimelineBuilder.following(for: Post(id: "root", userId: "a", channelId: "c", message: "x"), context: context) == nil)
    }

    @Test func rowEqualityTracksStatusAndFollowing() throws {
        let workspace = collapsedWorkspace()
        let base = try #require(row(workspace.channelItems(channelId: "town"), "p1"))
        var changed = base
        changed.authorStatus = .offline
        #expect(changed != base)
        changed = base
        changed.following = true
        #expect(changed != base)
    }

    @Test func threadPaneRootGetsFollowState() async throws {
        let workspace = collapsedWorkspace()
        #expect(workspace.threadFollowing == nil)
        await workspace.openThread(rootId: "p1")
        workspace.session.threads["p1"] = ThreadState(rootId: "p1")
        workspace.session.threads["p1"]?.postIds = ["p1", "p3", "r1"]
        #expect(workspace.threadFollowing == false)
        let items = workspace.threadItems(rootId: "p1")
        #expect(row(items, "p1")?.following == false)
        #expect(row(items, "p3")?.following == nil)
        workspace.session.collapsedThreads = false
        #expect(workspace.threadFollowing == nil)
    }

    @Test func togglingFollowHitsServer() async {
        let transport = Fixture.transport()
        transport.on("PUT", "users/me/teams/t1/threads/p1/following", json: "{}")
        transport.on("DELETE", "users/me/teams/t1/threads/p1/following", json: "{}")
        let workspace = collapsedWorkspace(transport: transport)
        await workspace.setFollowing(threadId: "p1", true)
        #expect(workspace.session.isFollowing(threadId: "p1"))
        #expect(transport.requests("PUT", "users/me/teams/t1/threads/p1/following").count == 1)
        await workspace.setFollowing(threadId: "p1", false)
        #expect(!workspace.session.isFollowing(threadId: "p1"))
        #expect(transport.requests("DELETE", "users/me/teams/t1/threads/p1/following").count == 1)
    }

    @Test func statusTitles() {
        #expect(UserStatusValue.selectable == [.online, .away, .dnd, .offline])
        #expect(UserStatusValue.selectable.map(\.title) == ["Online", "Away", "Do Not Disturb", "Offline"])
    }

    @Test func followButtonTitles() {
        #expect(ThreadFollowButton(following: false) {}.title == "Follow")
        #expect(ThreadFollowButton(following: true) {}.title == "Following")
        #expect(ThreadFollowButton(following: true, hovering: true) {}.title == "Unfollow")
        #expect(ThreadFollowButton(following: false, hovering: true) {}.title == "Follow")
    }

    @Test func myStatusMenuReflectsSession() {
        let session = Fixture.session()
        let menu = MyStatusMenu(session: session)
        #expect(menu.status == .offline)
        #expect(menu.avatarURL?.absoluteString.contains("users/me/image") == true)
        session.statuses["me"] = .dnd
        #expect(menu.status == .dnd)
    }

    @Test func rendersPresenceAndFollowControls() async {
        let summary = ThreadSummary(replyCount: 3, participants: [ThreadParticipant(id: "a", name: "Alice", avatarURL: nil)], lastReplyText: "Last reply just now", hasNewReplies: true)
        let idle = await MainSnapshot.render(ThreadSummaryButton(summary: summary, client: nil, following: true) {}.background(Theme.content), size: CGSize(width: 420, height: 40), name: "thread-summary-following")
        let hovered = await MainSnapshot.render(ThreadSummaryButton(summary: summary, client: nil, following: false, hovering: true) {}.background(Theme.content), size: CGSize(width: 420, height: 40), name: "thread-summary-hover")
        #expect(MainSnapshot.distinctColors(idle) > 3)
        #expect(MainSnapshot.distinctColors(hovered) > 3)
        let follow = await MainSnapshot.render(HStack { ThreadFollowButton(following: true, hovering: true) {}; ThreadFollowButton(following: false) {} }.background(Theme.content), size: CGSize(width: 220, height: 30), name: "thread-follow-buttons")
        #expect(MainSnapshot.distinctColors(follow) > 2)
        let link = await MainSnapshot.render(HoverLinkButton(action: {}) { Text("2 replies") }, size: CGSize(width: 120, height: 30))
        #expect(link.pixelsWide >= 120)
        let workspace = collapsedWorkspace()
        workspace.session.statuses["me"] = .away
        let header = await MainSnapshot.render(SidebarHeader(workspace: workspace).background(Theme.sidebar), size: CGSize(width: 260, height: 52), name: "sidebar-header-status")
        #expect(MainSnapshot.distinctColors(header) > 3)
        await workspace.openThread(rootId: "p1")
        workspace.session.threads["p1"]?.postIds = ["p1", "p3", "r1"]
        workspace.session.clearError()
        let pane = await MainSnapshot.render(RightPaneView(workspace: workspace), size: CGSize(width: 420, height: 500), name: "thread-pane-follow", settle: .milliseconds(500))
        #expect(MainSnapshot.distinctColors(pane) > 4)
        let list = await MainSnapshot.render(MessageListView(workspace: workspace, channelId: "town").background(Theme.content), size: CGSize(width: 760, height: 700), name: "presence-timeline", settle: .milliseconds(600))
        #expect(MainSnapshot.distinctColors(list) > 8)
    }
}

@Suite struct PresenceDebugCommandTests {
    func command(_ text: String) -> DebugCommand? {
        DebugCommand(url: URL(string: "boltun://debug/\(text)")!)
    }

    @Test func parsesFollowAndStatusCommands() {
        #expect(command("follow") == .follow(on: true, postId: nil))
        #expect(command("follow?on=0&post=abc") == .follow(on: false, postId: "abc"))
        #expect(command("set-status?status=dnd") == .setStatus(.dnd))
        #expect(command("set-status?status=busy") == nil)
        #expect(command("set-status") == nil)
    }
}
