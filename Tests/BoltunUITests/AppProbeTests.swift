import AppKit
import BoltunKit
import CoreFoundation
import Foundation
import SwiftUI
import Testing
@testable import BoltunUI

@MainActor
final class ProbeClock {
    var now: Double = 1000
}

@MainActor
struct AppProbeCommandTests {
    func command(_ string: String) -> DebugCommand? {
        DebugCommand(url: URL(string: string)!)
    }

    @Test func parsesWaits() {
        #expect(command("boltun://debug/probe?wait=posts") == .probe(.posts(sinceLaunch: false, timeout: 30)))
        #expect(command("boltun://debug/probe?wait=posts&since=launch&timeout=90") == .probe(.posts(sinceLaunch: true, timeout: 90)))
        #expect(command("boltun://debug/probe?wait=connected&timeout=-4") == .probe(.connected(timeout: 0)))
        #expect(command("boltun://debug/probe?wait=history") == .probe(.history(count: nil, timeout: 30)))
        #expect(command("boltun://debug/probe?wait=history&count=120&timeout=5") == .probe(.history(count: 120, timeout: 5)))
        #expect(command("boltun://debug/probe?wait=bogus") == nil)
    }

    @Test func parsesFreeze() {
        #expect(command("boltun://debug/probe?freeze=1") == .probe(.freeze(since: nil)))
        #expect(command("boltun://debug/probe?freeze=1&since=1792872742.5") == .probe(.freeze(since: 1792872742.5)))
        #expect(command("boltun://debug/probe") == nil)
        #expect(command("boltun://debug/probe?freeze=0") == nil)
    }

    @Test func onlyProbesAreProbes() {
        #expect(DebugCommand.probe(.freeze(since: nil)).isProbe)
        #expect(!DebugCommand.quit.isProbe)
    }

    @Test func recognizesPostIds() {
        #expect(TimelineItem.isPostId("abc123"))
        #expect(!TimelineItem.isPostId(TimelineItem.date("Today").id))
        #expect(!TimelineItem.isPostId(TimelineItem.newMessages.id))
        #expect(!TimelineItem.isPostId(TimelineItem.replies(3).id))
    }
}

@MainActor
struct AppProbeTests {
    func make() -> (AutomationProbe, ProbeClock) {
        let clock = ProbeClock()
        let probe = AutomationProbe(clock: { clock.now }, stallThreshold: 0.004, stallLimit: 10)
        probe.start(model: Harness().model, runLoop: nil)
        return (probe, clock)
    }

    @Test func staysInactiveUntilStarted() {
        let probe = AutomationProbe(clock: { 5 })
        probe.commandReceived()
        probe.rowsVisible(channelId: "c1", ids: ["p1"])
        probe.introVisible(channelId: "c1")
        probe.flushPending(at: 6)
        #expect(!probe.isActive)
        #expect(probe.commandAt == 0)
        #expect(probe.postsShownAt.isEmpty)
        #expect(probe.introShownAt.isEmpty)
    }

    @Test func recordsWorkBetweenRunLoopActivities() {
        let (probe, clock) = make()
        probe.runLoop(.afterWaiting)
        clock.now += 0.002
        probe.runLoop(.beforeTimers)
        clock.now += 0.050
        probe.runLoop(.beforeSources)
        clock.now += 0.010
        probe.runLoop(.beforeWaiting)
        clock.now += 5
        probe.runLoop(.beforeTimers)
        #expect(probe.stalls.map(\.duration).map { ($0 * 1000).rounded() } == [50, 10])
        #expect(probe.longestStall(from: 1000, to: 1001) == probe.stalls[0].duration)
        #expect(probe.longestStall(from: 1000.055, to: 1001) == probe.stalls[1].duration)
        #expect(probe.longestStall(from: 1001, to: 1010) == 0)
    }

    @Test func keepsTheNewestStallsWithinTheLimit() {
        let (probe, clock) = make()
        for _ in 0..<12 {
            probe.runLoop(.afterWaiting)
            clock.now += 0.01
            probe.runLoop(.beforeWaiting)
        }
        #expect(probe.stalls.count == 7)
        #expect(probe.stalls.last?.end == clock.now)
    }

    @Test func stampsPostsOncePerCommand() {
        let (probe, clock) = make()
        probe.rowsVisible(channelId: "c1", ids: [TimelineItem.date("Today").id])
        probe.flushPending(at: clock.now)
        #expect(probe.postsShownAt["c1"] == nil)
        probe.rowsVisible(channelId: "c1", ids: ["p1"])
        probe.flushPending(at: 1001)
        probe.rowsVisible(channelId: "c1", ids: ["p2"])
        probe.flushPending(at: 1002)
        #expect(probe.postsShownAt["c1"] == 1001)
        clock.now = 1003
        probe.commandReceived()
        probe.rowsVisible(channelId: "c1", ids: ["p2"])
        probe.introVisible(channelId: "c1")
        probe.flushPending(at: 1004)
        #expect(probe.commandAt == 1003)
        #expect(probe.postsShownAt["c1"] == 1004)
        #expect(probe.introShownAt["c1"] == 1004)
    }

    @Test func flushesPendingStampsWhenTheRunLoopSleeps() {
        let (probe, clock) = make()
        probe.runLoop(.afterWaiting)
        probe.rowsVisible(channelId: "c1", ids: ["p1"])
        clock.now = 1000.02
        probe.runLoop(.beforeWaiting)
        #expect(probe.postsShownAt["c1"] == 1000.02)
    }

    @Test func notesWhenAllServersAreConnected() async {
        let harness = await Harness.connected([Harness.server("A"), Harness.server("B", port: 8066)])
        let clock = ProbeClock()
        let probe = AutomationProbe(clock: { clock.now })
        probe.start(model: harness.model, runLoop: nil)
        #expect(probe.connectedAt == 1000)
        probe.start(model: Harness().model, runLoop: nil)
        #expect(probe.isActive)
    }

    @Test func waitsForTheFirstConnection() async {
        let harness = Harness(servers: [Harness.server()], tokens: [:])
        let probe = AutomationProbe(clock: { 7 })
        probe.start(model: harness.model, runLoop: nil)
        #expect(probe.connectedAt == nil)
        #expect(!AutomationProbe.allConnected(Harness().model))
    }

    @Test func installsARunLoopObserver() async {
        let probe = AutomationProbe(stallThreshold: 0)
        probe.start(model: Harness().model)
        try? await Task.sleep(for: .milliseconds(20))
        MainSnapshot.pump(0.05)
        #expect(!probe.stalls.isEmpty)
    }
}

@MainActor
struct AppProbeAutomationTests {
    func make(_ harness: Harness, active: Bool = true) -> (DebugAutomation, AutomationProbe, ProbeClock, LogSink) {
        let clock = ProbeClock()
        let probe = AutomationProbe(clock: { clock.now })
        if active { probe.start(model: harness.model, runLoop: nil) }
        let sink = LogSink()
        let automation = DebugAutomation(router: AppRouter(model: harness.model), host: FakeAutomationHost(), probe: probe, isEnabled: { true }) { sink.lines.append($0) }
        return (automation, probe, clock, sink)
    }

    func report(_ line: String?, prefix: String) throws -> ProbeReport {
        let line = try #require(line)
        #expect(line.hasPrefix(prefix))
        return try JSONDecoder().decode(ProbeReport.self, from: Data(line.dropFirst(prefix.count).utf8))
    }

    @Test func failsWhileInactive() async {
        let (automation, _, _, sink) = make(Harness(), active: false)
        await automation.handle(URL(string: "boltun://debug/probe?freeze=1")!)
        #expect(sink.lines == ["error /probe probe inactive"])
    }

    @Test func onlyOtherCommandsMoveTheCommandTime() async {
        let harness = await Harness.connected()
        let (automation, probe, clock, _) = make(harness)
        clock.now = 1100
        await automation.handle(URL(string: "boltun://debug/select?server=0")!)
        clock.now = 1200
        await automation.handle(URL(string: "boltun://debug/probe?freeze=1")!)
        #expect(probe.commandAt == 1100)
    }

    @Test func waitsForPostsOfTheCurrentChannel() async throws {
        let harness = await Harness.connected()
        let (automation, probe, clock, sink) = make(harness)
        let channelId = try #require(harness.model.selectedSession?.currentChannelId)
        clock.now = 1010
        await automation.handle(URL(string: "boltun://debug/select?server=0")!)
        Task { @MainActor in
            probe.rowsVisible(channelId: channelId, ids: ["p1"])
            probe.flushPending(at: 1010.25)
        }
        await automation.handle(URL(string: "boltun://debug/probe?wait=posts&timeout=5")!)
        let result = try report(sink.lines.last, prefix: "ok /probe ")
        #expect(result.channel == channelId)
        #expect(result.command == 1010)
        #expect(result.shown == 1010.25)
    }

    @Test func reportsPostsSinceLaunch() async throws {
        let harness = await Harness.connected()
        let (automation, probe, clock, sink) = make(harness)
        let channelId = try #require(harness.model.selectedSession?.currentChannelId)
        probe.rowsVisible(channelId: channelId, ids: ["p1"])
        probe.flushPending(at: 1000.5)
        clock.now = 1020
        await automation.handle(URL(string: "boltun://debug/select?server=0")!)
        await automation.handle(URL(string: "boltun://debug/probe?wait=posts&since=launch&timeout=1")!)
        #expect(try report(sink.lines.last, prefix: "ok /probe ").shown == 1000.5)
        await automation.handle(URL(string: "boltun://debug/probe?wait=posts&timeout=0.05")!)
        #expect(sink.lines.last == "error /probe timeout")
    }

    @Test func reportsTheConnectionTime() async throws {
        let harness = await Harness.connected()
        let (automation, _, _, sink) = make(harness)
        await automation.handle(URL(string: "boltun://debug/probe?wait=connected")!)
        #expect(try report(sink.lines.last, prefix: "ok /probe ").connected == 1000)
        let (offline, _, _, offlineSink) = make(Harness(servers: [Harness.server()]))
        await offline.handle(URL(string: "boltun://debug/probe?wait=connected&timeout=0.05")!)
        #expect(offlineSink.lines.last == "error /probe timeout")
    }

    @Test func reportsHistoryProgress() async throws {
        let harness = await Harness.connected()
        let (automation, probe, clock, sink) = make(harness)
        let channelId = try #require(harness.model.selectedSession?.currentChannelId)
        await automation.handle(URL(string: "boltun://debug/probe?wait=history")!)
        let initial = try report(sink.lines.last, prefix: "ok /probe ")
        #expect(initial.count == 2)
        #expect(initial.intro == false)
        #expect(initial.shown == nil)
        await automation.handle(URL(string: "boltun://debug/probe?wait=history&count=1")!)
        #expect(try report(sink.lines.last, prefix: "ok /probe ").count == 2)
        clock.now = 1050
        await automation.handle(URL(string: "boltun://debug/scroll?to=top")!)
        Task { @MainActor in
            probe.introVisible(channelId: channelId)
            probe.flushPending(at: 1050.5)
        }
        await automation.handle(URL(string: "boltun://debug/probe?wait=history&count=2&timeout=5")!)
        let done = try report(sink.lines.last, prefix: "ok /probe ")
        #expect(done.intro == true)
        #expect(done.shown == 1050.5)
        #expect(done.more == false)
        #expect(done.channel == channelId)
    }

    @Test func reportsTheLongestFreeze() async throws {
        let harness = await Harness.connected()
        let (automation, probe, clock, sink) = make(harness)
        clock.now = 1100
        await automation.handle(URL(string: "boltun://debug/select?server=0")!)
        probe.runLoop(.afterWaiting)
        clock.now = 1100.120
        probe.runLoop(.beforeWaiting)
        clock.now = 1101
        await automation.handle(URL(string: "boltun://debug/probe?freeze=1")!)
        let result = try report(sink.lines.last, prefix: "ok /probe ")
        #expect((try #require(result.freeze)).rounded() == 120)
        #expect(result.now == 1101)
        await automation.handle(URL(string: "boltun://debug/probe?freeze=1&since=1100.5")!)
        #expect(try report(sink.lines.last, prefix: "ok /probe ").freeze == 0)
    }

    @Test func encodesOnlyPresentFields() {
        #expect(ProbeReport(command: 1, now: 2, freeze: 3).json() == #"{"command":1,"freeze":3,"now":2}"#)
    }
}

@MainActor
struct AppProbeViewTests {
    func sharedProbe() -> AutomationProbe {
        let probe = AutomationProbe.shared
        probe.start(model: Harness().model, runLoop: nil)
        return probe
    }

    @Test func channelIntroReportsItsAppearance() async {
        let probe = sharedProbe()
        let workspace = Fixture.workspace()
        await MainSnapshot.render(ChannelIntro(workspace: workspace, channelId: "town"), size: CGSize(width: 400, height: 120))
        probe.flushPending(at: probe.clock())
        #expect(probe.introShownAt["town"] != nil)
    }

    @Test(.enabled(if: InteractiveSession.available)) func messageListReportsVisiblePosts() async {
        let probe = sharedProbe()
        let workspace = Fixture.workspace()
        let size = CGSize(width: 900, height: 300)
        let hosting = NSHostingView(rootView: MessageListView(workspace: workspace, channelId: "town").frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        let deadline = ContinuousClock.now + .seconds(10)
        var shown = false
        while !shown, ContinuousClock.now < deadline {
            MainSnapshot.pump(0.02)
            try? await Task.sleep(for: .milliseconds(5))
            probe.flushPending(at: probe.clock())
            shown = probe.postsShownAt["town"] != nil
        }
        window.close()
        #expect(shown)
    }
}
