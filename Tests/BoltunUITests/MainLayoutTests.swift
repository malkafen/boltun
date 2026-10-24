import AppKit
import SwiftUI
import Testing
@testable import BoltunKit
@testable import BoltunUI

@MainActor
struct MainLayoutTests {
    func height(_ view: some View, width: CGFloat = 700) -> CGFloat {
        let hosting = NSHostingView(rootView: view.frame(width: width))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    @Test func hoverDoesNotChangeRowHeight() {
        let workspace = Fixture.workspace()
        let context = workspace.timelineContext(lastViewedAt: 0, showReplyContext: true)
        let posts = Fixture.townPosts()
        for (index, post) in posts.enumerated() {
            let previous = index > 0 ? posts[index - 1] : nil
            for continuation in [false, true] {
                let model = TimelineBuilder.row(for: post, previous: previous, continuation: continuation, context: context)
                let resting = height(MessageRow(model: model, workspace: workspace))
                let hovered = height(MessageRow(model: model, workspace: workspace, hovering: true))
                #expect(resting == hovered, "post \(post.id) continuation \(continuation)")
                #expect(resting > 0)
            }
        }
    }
}

@MainActor
struct MainWindowLogicTests {
    let teams = [Team(id: "t1", name: "one", displayName: "One"), Team(id: "t2", name: "two", displayName: "Two")]

    @Test func selectionRestorePrefersRememberedTeamAndChannel() {
        let server = ServerConfig(name: "S", url: URL(string: "http://s.test")!, lastTeamId: "t2", lastChannelByTeam: ["t2": "c9", "t1": "c1"])
        let target = SelectionRestore.target(teams: teams, server: server)
        #expect(target?.teamId == "t2")
        #expect(target?.channelId == "c9")
    }

    @Test func selectionRestoreFallsBackToFirstTeam() {
        let stale = ServerConfig(name: "S", url: URL(string: "http://s.test")!, lastTeamId: "gone", lastChannelByTeam: ["t1": "c1"])
        #expect(SelectionRestore.target(teams: teams, server: stale)?.teamId == "t1")
        #expect(SelectionRestore.target(teams: teams, server: stale)?.channelId == "c1")
        #expect(SelectionRestore.target(teams: teams, server: nil)?.teamId == "t1")
        #expect(SelectionRestore.target(teams: teams, server: nil)?.channelId == nil)
        #expect(SelectionRestore.target(teams: [], server: stale) == nil)
    }

    @Test func windowTitleFollowsChannelAndServer() async {
        let (model, session) = Fixture.appModel()
        #expect(WindowTitle.text(model: AppModel(store: MemoryAppStateStore(), credentials: MemoryCredentialStore(), transport: Fixture.transport())) == "Boltun")
        await model.selectServer(at: 0)
        #expect(WindowTitle.text(model: model) == "Town Square — Acme Corp")
        session.currentChannelId = nil
        #expect(WindowTitle.text(model: model) == "Acme Corp")
    }
}
