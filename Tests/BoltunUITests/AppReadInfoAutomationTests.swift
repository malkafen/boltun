import AppKit
@testable import BoltunKit
import Foundation
import Testing
@testable import BoltunUI

@MainActor
struct AppReadInfoCommandTests {
    func command(_ string: String) -> DebugCommand? {
        DebugCommand(url: URL(string: string)!)
    }

    @Test func parsesReadInfoCommands() {
        #expect(command("boltun://debug/acknowledge") == .acknowledge(index: 0, postId: nil))
        #expect(command("boltun://debug/acknowledge?index=2") == .acknowledge(index: 2, postId: nil))
        #expect(command("boltun://debug/acknowledge?post=p1") == .acknowledge(index: 0, postId: "p1"))
        #expect(command("boltun://debug/priority?level=urgent&ack=1&notify=1") == .priority(PostPriority(priority: .urgent, requestedAck: true, persistentNotifications: true)))
        #expect(command("boltun://debug/priority?level=important") == .priority(PostPriority(priority: .important)))
        #expect(command("boltun://debug/priority?level=standard") == .priority(PostPriority()))
        #expect(command("boltun://debug/priority?level=none") == .priority(PostPriority()))
        #expect(command("boltun://debug/priority?level=bogus") == nil)
        #expect(command("boltun://debug/priority") == nil)
        #expect(command("boltun://debug/burn-on-read") == .burnOnRead(on: true))
        #expect(command("boltun://debug/burn-on-read?on=0") == .burnOnRead(on: false))
        #expect(command("boltun://debug/reveal?index=1") == .reveal(index: 1, postId: nil))
        #expect(command("boltun://debug/reveal?post=b1") == .reveal(index: 0, postId: "b1"))
        #expect(command("boltun://debug/burn?post=b1") == .burn(index: 0, postId: "b1"))
        #expect(command("boltun://debug/burn") == .burn(index: 0, postId: nil))
    }

    @Test func parsesPriorityLevels() {
        #expect(DebugCommand.priorityLevel("") == .standard)
        #expect(DebugCommand.priorityLevel("URGENT") == .urgent)
        #expect(DebugCommand.priorityLevel("Important") == .important)
        #expect(DebugCommand.priorityLevel("low") == nil)
    }
}

@MainActor
struct AppReadInfoAutomationTests {
    static let licensedConfig = #"{"SiteName":"Test Site","Version":"12.0.1","PostPriority":"true","PostAcknowledgements":"true","AllowPersistentNotifications":"true","PersistentNotificationIntervalMinutes":"5","EnableBurnOnRead":"true","BurnOnReadDurationSeconds":"600"}"#
    static let readInfoPosts = """
    {"order":["burn-out","burn-in","ask","p1"],"posts":{
      "p1":{"id":"p1","channel_id":"c1","user_id":"me","message":"hello","create_at":10},
      "ask":{"id":"ask","channel_id":"c1","user_id":"u2","message":"confirm please","create_at":20,
             "metadata":{"priority":{"priority":"urgent","requested_ack":true}}},
      "burn-in":{"id":"burn-in","channel_id":"c1","user_id":"u2","message":"","create_at":30,"type":"burn_on_read",
                 "props":{"read_duration":600000}},
      "burn-out":{"id":"burn-out","channel_id":"c1","user_id":"me","message":"my secret","create_at":40,"type":"burn_on_read",
                  "props":{"read_duration":600000},"metadata":{"recipients":[]}}}}
    """

    func harness(licensed: Bool = true) async -> Harness {
        var routes = FakeTransport.standardRoutes
        if licensed {
            routes["GET config/client"] = .init(status: 200, body: Self.licensedConfig)
            routes["GET license/client"] = .init(status: 200, body: #"{"IsLicensed":"true","SkuShortName":"entry"}"#)
        }
        routes["GET channels/c1/posts"] = .init(status: 200, body: Self.readInfoPosts)
        routes["GET channels/c1/stats"] = .init(status: 200, body: #"{"channel_id":"c1","member_count":4}"#)
        let now = Date().mattermostMillis
        routes["POST users/me/posts/ask/ack"] = .init(status: 200, body: #"{"user_id":"me","post_id":"ask","acknowledged_at":\#(now),"channel_id":"c1"}"#)
        routes["DELETE users/me/posts/ask/ack"] = .init(status: 200, body: #"{"status":"OK"}"#)
        routes["GET posts/burn-in/reveal"] = .init(status: 200, body: #"{"id":"burn-in","channel_id":"c1","user_id":"u2","message":"the secret","create_at":30,"type":"burn_on_read","props":{"read_duration":600000},"metadata":{"expire_at":\#(now + 600_000)}}"#)
        routes["DELETE posts/burn-out/burn"] = .init(status: 200, body: #"{"status":"OK"}"#)
        let server = Harness.server()
        let harness = Harness(servers: [server], tokens: [server.id: "token"], transport: FakeTransport(routes: routes))
        await harness.model.startAll()
        return harness
    }

    func make(_ harness: Harness) -> (DebugAutomation, LogSink) {
        let sink = LogSink()
        let router = AppRouter(model: harness.model)
        let automation = DebugAutomation(router: router, host: FakeAutomationHost(), isEnabled: { true }) { sink.lines.append($0) }
        return (automation, sink)
    }

    func state(_ automation: DebugAutomation) async throws -> AutomationState {
        let path = "/tmp/boltun-tests-\(UUID().uuidString).json"
        await automation.handle(URL(string: "boltun://debug/state?path=\(path)")!)
        defer { try? FileManager.default.removeItem(atPath: path) }
        return try JSONDecoder().decode(AutomationState.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    @Test func acknowledgesAndRevokes() async throws {
        let harness = await harness()
        let (automation, sink) = make(harness)
        let session = try #require(harness.model.selectedSession)
        #expect(await eventually { session.posts["ask"] != nil })
        await automation.handle(URL(string: "boltun://debug/acknowledge?post=ask")!)
        #expect(sink.lines.last == "ok /acknowledge 1")
        var ui = try #require(try await state(automation).ui)
        let ask = try #require(ui.recentPosts.first { $0.id == "ask" })
        #expect(ask.priority == "urgent")
        #expect(ask.requestedAck)
        #expect(ask.acknowledgedBy == ["boltun"])
        await automation.handle(URL(string: "boltun://debug/acknowledge?post=ask")!)
        #expect(sink.lines.last == "ok /acknowledge 0")
        ui = try #require(try await state(automation).ui)
        #expect(ui.recentPosts.first { $0.id == "ask" }?.acknowledgedBy.isEmpty == true)
        await automation.handle(URL(string: "boltun://debug/acknowledge?index=9")!)
        #expect(sink.lines.last == "error /acknowledge no post at index 9")
    }

    @Test func setsComposerPriorityAndBurnOnRead() async throws {
        let harness = await harness()
        let (automation, sink) = make(harness)
        await automation.handle(URL(string: "boltun://debug/priority?level=urgent&ack=1&notify=1")!)
        #expect(sink.lines.last == "ok /priority urgent:true:true")
        await automation.handle(URL(string: "boltun://debug/burn-on-read")!)
        #expect(sink.lines.last == "ok /burn-on-read true")
        var ui = try #require(try await state(automation).ui)
        var composer = try #require(ui.composer)
        #expect(composer.priority == "urgent")
        #expect(composer.requestedAck)
        #expect(composer.persistentNotifications)
        #expect(composer.burnOnRead)
        #expect(ui.readInfo == AutomationUIState.ReadInfoFeatures(
            postPriority: true, acknowledgements: true, persistentNotifications: true, burnOnRead: true, licenseSku: "entry"
        ))
        await automation.handle(URL(string: "boltun://debug/priority?level=standard")!)
        #expect(sink.lines.last == "ok /priority :false:false")
        await automation.handle(URL(string: "boltun://debug/burn-on-read?on=0")!)
        #expect(sink.lines.last == "ok /burn-on-read false")
        ui = try #require(try await state(automation).ui)
        composer = try #require(ui.composer)
        #expect(composer.priority.isEmpty)
        #expect(!composer.burnOnRead)
    }

    @Test func revealsAndBurns() async throws {
        let harness = await harness()
        let (automation, sink) = make(harness)
        let session = try #require(harness.model.selectedSession)
        #expect(await eventually { session.posts["burn-in"] != nil })
        var ui = try #require(try await state(automation).ui)
        var incoming = try #require(ui.recentPosts.first { $0.id == "burn-in" }?.burnOnRead)
        #expect(incoming == AutomationUIState.BurnOnReadSummary(isSender: false, revealed: false, expireAt: 0, readBy: 0, recipients: nil))
        #expect(await eventually { session.channelMemberCounts["c1"] == 4 })
        let outgoing = try #require(ui.recentPosts.first { $0.id == "burn-out" }?.burnOnRead)
        #expect(outgoing.isSender)
        #expect(outgoing.revealed)
        await automation.handle(URL(string: "boltun://debug/reveal?index=1")!)
        #expect(sink.lines.last == "ok /reveal true")
        ui = try #require(try await state(automation).ui)
        incoming = try #require(ui.recentPosts.first { $0.id == "burn-in" }?.burnOnRead)
        #expect(incoming.revealed)
        #expect(incoming.expireAt > 0)
        await automation.handle(URL(string: "boltun://debug/burn?post=burn-out")!)
        #expect(sink.lines.last == "ok /burn burn-out")
        ui = try #require(try await state(automation).ui)
        #expect(!ui.recentPosts.contains { $0.id == "burn-out" })
        #expect(!ui.sheets.contains("burn-confirmation"))
        await automation.handle(URL(string: "boltun://debug/burn?post=nope")!)
        #expect(sink.lines.last == "error /burn no post nope")
    }

    @Test func unlicensedServerRefusesTheCommands() async throws {
        let harness = await harness(licensed: false)
        let (automation, sink) = make(harness)
        await automation.handle(URL(string: "boltun://debug/priority?level=urgent")!)
        #expect(sink.lines.last == "error /priority message priority disabled")
        await automation.handle(URL(string: "boltun://debug/burn-on-read")!)
        #expect(sink.lines.last == "error /burn-on-read burn on read disabled")
        await automation.handle(URL(string: "boltun://debug/burn-on-read?on=0")!)
        #expect(sink.lines.last == "ok /burn-on-read false")
        let ui = try #require(try await state(automation).ui)
        #expect(ui.readInfo == AutomationUIState.ReadInfoFeatures(
            postPriority: false, acknowledgements: false, persistentNotifications: false, burnOnRead: false, licenseSku: ""
        ))
        #expect(ui.composer?.priority.isEmpty == true)
        #expect(ui.composer?.burnOnRead == false)
    }
}
