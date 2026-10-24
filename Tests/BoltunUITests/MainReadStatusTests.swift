import AppKit
import Foundation
import SwiftUI
import Testing
@testable import BoltunKit
@testable import BoltunUI

extension Fixture {
    static func directPosts() -> [Post] {
        [
            Post(id: "a1", createAt: minutes(0), userId: "alice", channelId: "dm-alice", message: "Are you around?"),
            Post(id: "m1", createAt: minutes(1), userId: "me", channelId: "dm-alice", message: "Yes"),
            Post(id: "m2", createAt: minutes(2), userId: "me", channelId: "dm-alice", message: "What's up?"),
            Post(id: "a2", createAt: minutes(3), userId: "alice", channelId: "dm-alice", message: "Can you review my PR?"),
            Post(id: "m3", createAt: minutes(4), userId: "me", channelId: "dm-alice", message: "Sure"),
            Post(id: "m4", createAt: minutes(4.5), userId: "me", channelId: "dm-alice", message: "Looking now"),
        ]
    }

    @MainActor
    static func readStatusWorkspace(aliceViewed: Int) -> Workspace {
        let workspace = workspace()
        let session = workspace.session
        for post in directPosts() { session.posts[post.id] = post }
        var timeline = ChannelTimeline()
        timeline.postIds = directPosts().map(\.id)
        timeline.loaded = true
        timeline.hasMoreOlder = false
        session.timelines["dm-alice"] = timeline
        session.channels["dm-alice"]?.totalMsgCount = 6
        session.channels["dm-alice"]?.totalMsgCountRoot = 6
        session.readCounts["dm-alice"] = [MemberReadCount(userId: "alice", msgCount: aliceViewed, msgCountRoot: aliceViewed)]
        session.currentChannelId = "dm-alice"
        return workspace
    }
}

struct ReadStatusRowModelTests {
    let names = ["alice": "Alice", "bob": "Bob", "carol": "Carol", "dave": "Dave"]

    func model(_ state: PostReadState) -> ReadStatusRowModel {
        ReadStatusRowModel(state: state) { names[$0] ?? $0 }
    }

    @Test func mapsStatesToKindsCheckmarksAndTooltips() {
        #expect(model(.sent) == ReadStatusRowModel(kind: .sent, tooltip: "Sent"))
        #expect(model(.sent).checkmarks == 1)
        #expect(model(.seen) == ReadStatusRowModel(kind: .seen, tooltip: "Seen"))
        #expect(model(.seen).checkmarks == 2)
        let partial = model(.partiallySeen(seenBy: ["alice", "bob"], total: 4))
        #expect(partial == ReadStatusRowModel(kind: .partiallySeen, tooltip: "Seen by Alice, Bob"))
        #expect(partial.checkmarks == 2)
    }

    @Test func manyReadersAreCounted() {
        #expect(model(.partiallySeen(seenBy: ["alice", "bob", "carol"], total: 5)).tooltip == "Seen by Alice, Bob, Carol")
        #expect(model(.partiallySeen(seenBy: ["alice", "bob", "carol", "dave"], total: 6)).tooltip == "Seen by 4 of 6")
    }
}

struct ReadStatusPlacementTests {
    func post(_ id: String, _ user: String, type: String = "", deleted: Bool = false) -> Post {
        Post(id: id, deleteAt: deleted ? 1 : 0, userId: user, channelId: "c", message: id, type: type)
    }

    func placed(_ posts: [Post], _ states: [String: PostReadState]) -> Set<String> {
        ReadStatusPlacement.postIds(posts: posts, states: states, myId: "me")
    }

    @Test func marksTheLastPostOfEachUnseenRunAndAlwaysTheLatest() {
        let posts = [post("m1", "me"), post("m2", "me"), post("o1", "u2"), post("m3", "me"), post("m4", "me")]
        #expect(placed(posts, ["m1": .seen, "m2": .seen, "m3": .seen, "m4": .seen]) == ["m4"])
        #expect(placed(posts, ["m1": .seen, "m2": .seen, "m3": .sent, "m4": .sent]) == ["m4"])
        #expect(placed(posts, ["m1": .sent, "m2": .sent, "m3": .sent, "m4": .sent]) == ["m2", "m4"])
        let partial = PostReadState.partiallySeen(seenBy: ["u2"], total: 2)
        #expect(placed(posts, ["m1": .seen, "m2": partial, "m3": .sent, "m4": .sent]) == ["m2", "m4"])
    }

    @Test func pendingAndBurnOnReadPostsLeaveTheIndicatorOnTheLastDeliveredPost() {
        let posts = [post("m1", "me"), post("m2", "me"), post("pending", "me"), post("bor", "me", type: PostType.burnOnRead)]
        #expect(placed(posts, ["m1": .seen, "m2": .sent]) == ["m2"])
    }

    @Test func systemAndDeletedPostsBreakRuns() {
        let posts = [post("m1", "me"), post("header", "me", type: "system_header_change"), post("m2", "me"), post("gone", "me", deleted: true), post("m3", "me")]
        #expect(placed(posts, ["m1": .sent, "m2": .sent, "m3": .sent]) == ["m1", "m2", "m3"])
    }

    @Test func nothingIsPlacedWithoutStatesOrOwnPosts() {
        #expect(placed([post("m1", "me")], [:]).isEmpty)
        #expect(placed([post("o1", "u2")], ["x": .sent]).isEmpty)
    }
}

@MainActor
@Suite struct ReadStatusTimelineTests {
    func rows(_ workspace: Workspace) -> [String: MessageRowModel] {
        var result: [String: MessageRowModel] = [:]
        for case .post(let model) in workspace.channelItems(channelId: "dm-alice") { result[model.id] = model }
        return result
    }

    @Test func directChannelRowsCarryTheComputedState() {
        let workspace = Fixture.readStatusWorkspace(aliceViewed: 4)
        let rows = rows(workspace)
        #expect(rows["m4"]?.readStatus == ReadStatusRowModel(kind: .sent, tooltip: "Sent"))
        #expect(rows["m4"]?.isContinuation == true)
        #expect(rows["m3"]?.readStatus == nil)
        #expect(rows["m2"]?.readStatus == nil)
        #expect(rows["a2"]?.readStatus == nil)
    }

    @Test func unseenOlderRunsAndSeenLatestPostAreMarked() {
        let unseen = rows(Fixture.readStatusWorkspace(aliceViewed: 2))
        #expect(unseen["m2"]?.readStatus?.kind == .sent)
        #expect(unseen["m4"]?.readStatus?.kind == .sent)
        let seen = rows(Fixture.readStatusWorkspace(aliceViewed: 6))
        #expect(seen["m2"]?.readStatus == nil)
        #expect(seen["m4"]?.readStatus == ReadStatusRowModel(kind: .seen, tooltip: "Seen"))
    }

    @Test func countChangesOnlyAlterTheAffectedRows() {
        let workspace = Fixture.readStatusWorkspace(aliceViewed: 4)
        let before = rows(workspace)
        workspace.session.readCounts["dm-alice"] = [MemberReadCount(userId: "alice", msgCount: 6, msgCountRoot: 6)]
        let after = rows(workspace)
        #expect(before["m4"] != after["m4"])
        for id in ["a1", "m1", "m2", "a2", "m3"] { #expect(before[id] == after[id], "\(id)") }
    }

    @Test func disabledOrPublicChannelsShowNothing() {
        let workspace = Fixture.readStatusWorkspace(aliceViewed: 4)
        workspace.session.readStatusEnabled = false
        #expect(rows(workspace).values.allSatisfy { $0.readStatus == nil })
        for case .post(let model) in workspace.channelItems(channelId: "town") { #expect(model.readStatus == nil) }
    }

    @Test func threadItemsNeverCarryReadStatus() {
        let workspace = Fixture.readStatusWorkspace(aliceViewed: 0)
        let items = TimelineBuilder.threadItems(posts: Fixture.directPosts(), context: workspace.timelineContext(lastViewedAt: 0, showReplyContext: false))
        for case .post(let model) in items { #expect(model.readStatus == nil) }
    }

    @Test func rendersIndicatorsInHeaderAndTrailingPositions() async {
        let workspace = Fixture.readStatusWorkspace(aliceViewed: 2)
        let items = workspace.channelItems(channelId: "dm-alice")
        let view = VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in TimelineItemView(item: item, workspace: workspace) }
            HStack(spacing: 12) {
                ReadStatusIndicator(model: ReadStatusRowModel(kind: .sent, tooltip: "Sent"))
                ReadStatusIndicator(model: ReadStatusRowModel(kind: .partiallySeen, tooltip: "Seen by Bob"))
                ReadStatusIndicator(model: ReadStatusRowModel(kind: .seen, tooltip: "Seen"))
            }
            .padding(16)
            Spacer()
        }
        let rep = await MainSnapshot.render(view, size: CGSize(width: 560, height: 420), name: "read-status-rows")
        #expect(MainSnapshot.distinctColors(rep) > 6)
    }

    @Test func singleOwnPostShowsTheIndicatorInItsHeader() async throws {
        let workspace = Fixture.readStatusWorkspace(aliceViewed: 6)
        let post = Post(id: "solo", createAt: Fixture.minutes(30), userId: "me", channelId: "dm-alice", message: "Done")
        workspace.session.posts["solo"] = post
        workspace.session.timelines["dm-alice"]?.postIds.append("solo")
        workspace.session.channels["dm-alice"]?.totalMsgCount = 7
        let solo = rows(workspace)["solo"]
        #expect(solo?.isContinuation == false)
        #expect(solo?.readStatus?.kind == .sent)
        let model = try #require(solo)
        let rep = await MainSnapshot.render(MessageRow(model: model, workspace: workspace, hovering: true), size: CGSize(width: 480, height: 80), name: "read-status-header")
        #expect(MainSnapshot.distinctColors(rep) > 2)
    }
}

@MainActor
@Suite struct ReadStatusSettingsTests {
    init() {
        _ = NSApplication.shared
    }

    @Test func toggleDefaultsOnPersistsAndReachesSessions() async throws {
        let harness = await Harness.connected()
        let session = try #require(harness.model.selectedSession)
        #expect(harness.model.settings.showReadStatus)
        #expect(session.readStatusEnabled)
        harness.model.settings.showReadStatus = false
        #expect(!harness.store.load().settings.showReadStatus)
        #expect(await eventually { !session.readStatusEnabled })
    }

    @Test func generalPaneRendersTheToggle() async {
        let harness = Harness()
        let view = GeneralSettingsView(viewModel: GeneralSettingsViewModel(model: harness.model, loginItem: FakeLoginItem()))
        let data = Render.png(view, size: CGSize(width: 600, height: 700), name: "settings-general-read-status")
        #expect(data != nil)
    }
}

@MainActor
@Suite struct ReadStatusAutomationTests {
    static let directChannels = #"[{"id":"c1","team_id":"t1","name":"town-square","display_name":"Town Square","type":"O","total_msg_count":3,"last_post_at":30},{"id":"dm2","team_id":"","name":"me__u2","display_name":"","type":"D","total_msg_count":2,"total_msg_count_root":2,"last_post_at":20}]"#
    static let directMembers = #"[{"channel_id":"c1","user_id":"me","msg_count":3},{"channel_id":"dm2","user_id":"me","msg_count":2}]"#
    static let directPosts = #"{"order":["d2","d1"],"posts":{"d1":{"id":"d1","channel_id":"dm2","user_id":"me","message":"one","create_at":10},"d2":{"id":"d2","channel_id":"dm2","user_id":"me","message":"two","create_at":20}}}"#

    func harness() async -> Harness {
        var routes = FakeTransport.standardRoutes
        routes["GET users/me/teams/t1/channels"] = .init(status: 200, body: Self.directChannels)
        routes["GET users/me/teams/t1/channels/members"] = .init(status: 200, body: Self.directMembers)
        routes["GET channels/dm2/posts"] = .init(status: 200, body: Self.directPosts)
        routes["GET channels/dm2"] = .init(status: 200, body: #"{"id":"dm2","team_id":"","name":"me__u2","type":"D","total_msg_count":2,"total_msg_count_root":2}"#)
        routes["GET channels/dm2/members"] = .init(status: 200, body: #"[{"channel_id":"dm2","user_id":"me","msg_count":2},{"channel_id":"dm2","user_id":"u2","msg_count":1,"msg_count_root":1}]"#)
        routes["POST users/ids"] = .init(status: 200, body: #"[{"id":"u2","username":"user1"}]"#)
        let server = Harness.server()
        let harness = Harness(servers: [server], tokens: [server.id: "token"], transport: FakeTransport(routes: routes))
        await harness.model.startAll()
        return harness
    }

    func make(_ harness: Harness) -> (DebugAutomation, LogSink) {
        let sink = LogSink()
        let automation = DebugAutomation(router: AppRouter(model: harness.model), host: FakeAutomationHost(), isEnabled: { true }) { sink.lines.append($0) }
        return (automation, sink)
    }

    func state(_ automation: DebugAutomation) async throws -> AutomationUIState {
        let path = "/tmp/boltun-tests-\(UUID().uuidString).json"
        await automation.handle(URL(string: "boltun://debug/state?path=\(path)")!)
        defer { try? FileManager.default.removeItem(atPath: path) }
        return try #require(try JSONDecoder().decode(AutomationState.self, from: Data(contentsOf: URL(fileURLWithPath: path))).ui)
    }

    @Test func stateDumpReportsReadStatusPerPost() async throws {
        let harness = await harness()
        let (automation, sink) = make(harness)
        let session = try #require(harness.model.selectedSession)
        session.readStatusPollInterval = .seconds(3600)
        await session.selectChannel("dm2")
        #expect(await eventually { session.users["u2"] != nil })
        var ui = try await state(automation)
        let first = try #require(ui.recentPosts.first { $0.id == "d1" })
        let second = try #require(ui.recentPosts.first { $0.id == "d2" })
        #expect(first.readStatus == "seen")
        #expect(first.seenBy == ["user1"])
        #expect(!first.readIndicator)
        #expect(second.readStatus == "sent")
        #expect(second.seenBy.isEmpty)
        #expect(second.readIndicator)
        #expect(ui.readStatus == AutomationUIState.ReadStatusTracking(enabled: true, tracked: true, polling: true, total: 2, unseenByMember: ["user1": 1]))

        await automation.handle(URL(string: "boltun://debug/setting?name=showReadStatus&value=0")!)
        #expect(sink.lines.last == "ok /setting 0")
        #expect(await eventually { !session.readStatusEnabled })
        ui = try await state(automation)
        #expect(ui.recentPosts.allSatisfy { $0.readStatus == nil && !$0.readIndicator })
        #expect(ui.readStatus == AutomationUIState.ReadStatusTracking(enabled: false, tracked: false, polling: false, total: 2, unseenByMember: [:]))
    }

    @Test func publicChannelsReportNoReadStatus() async throws {
        let harness = await harness()
        let (automation, _) = make(harness)
        let ui = try await state(automation)
        #expect(ui.recentPosts.allSatisfy { $0.readStatus == nil })
        #expect(ui.readStatus?.tracked == false)
    }

    @Test func describesEveryState() {
        #expect(DebugAutomation.describe(PostReadState.sent) == "sent")
        #expect(DebugAutomation.describe(PostReadState.seen) == "seen")
        #expect(DebugAutomation.describe(PostReadState.partiallySeen(seenBy: ["u2"], total: 3)) == "partially-seen/3")
        #expect(DebugAutomation.describe(nil) == nil)
    }
}

@MainActor
@Suite struct ReadStatusLifecycleTests {
    init() {
        _ = NSApplication.shared
    }

    @Test func activationKeyWindowAndResignDriveTheSelectedSession() async throws {
        let harness = await Harness.connected()
        let session = try #require(harness.model.selectedSession)
        let delegate = AppDelegate()
        let environment = harness.environment()
        delegate.environment = environment
        environment.appDidBecomeActive()
        environment.mainWindowDidBecomeKey()
        environment.launch(startSessions: false)
        session.readStatusPollTask = Task {}
        delegate.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))
        #expect(session.readStatusPollTask == nil)
        environment.mainWindowDidBecomeKey()
        environment.appDidBecomeActive()
        environment.mainWindow?.orderOut(nil)
    }

    @Test func windowControllerReportsBecomingKey() {
        let controller = MainWindowController(rootView: Text("Boltun"), autosaveName: nil)
        var count = 0
        controller.onBecomeKey = { count += 1 }
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        #expect(count == 1)
    }
}
