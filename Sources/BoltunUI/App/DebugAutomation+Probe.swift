import BoltunKit
import Foundation

struct ProbeReport: Codable, Equatable, Sendable {
    var command: Double
    var now: Double
    var channel: String?
    var shown: Double?
    var connected: Double?
    var count: Int?
    var more: Bool?
    var intro: Bool?
    var freeze: Double?

    func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

extension DebugAutomation {
    func performProbe(_ request: DebugCommand.ProbeRequest) async throws -> String {
        guard probe.isActive else { throw AutomationError.failed("probe inactive") }
        switch request {
        case .posts(let sinceLaunch, let timeout):
            return try await waitForPosts(since: sinceLaunch ? 0 : probe.commandAt, timeout: timeout)
        case .connected(let timeout):
            let probe = self.probe
            guard await Observe.until(timeout: .seconds(timeout), { probe.connectedAt != nil }) else {
                throw AutomationError.failed("timeout")
            }
            return report(connected: probe.connectedAt).json()
        case .history(let count, let timeout):
            return try await waitForHistory(after: count, timeout: timeout)
        case .freeze(let since):
            let now = probe.clock()
            return report(now: now, freeze: probe.longestStall(from: since ?? probe.commandAt, to: now) * 1000).json()
        }
    }

    private func waitForPosts(since: Double, timeout: Double) async throws -> String {
        let model = self.model
        let probe = self.probe
        let shown = await Observe.until(timeout: .seconds(timeout)) {
            guard let channelId = model.selectedSession?.currentChannelId else { return false }
            return (probe.postsShownAt[channelId] ?? -1) >= since
        }
        guard shown, let channelId = model.selectedSession?.currentChannelId else { throw AutomationError.failed("timeout") }
        return report(channel: channelId, shown: probe.postsShownAt[channelId]).json()
    }

    private func waitForHistory(after count: Int?, timeout: Double) async throws -> String {
        let session = try currentWorkspace().session
        let channelId = try currentChannelId(session)
        let probe = self.probe
        let since = probe.commandAt
        let introShown = { (probe.introShownAt[channelId] ?? -1) >= since }
        if let count {
            _ = await Observe.until(timeout: .seconds(timeout)) {
                let timeline = session.timelines[channelId] ?? ChannelTimeline()
                return introShown() || (timeline.postIds.count > count && !timeline.isLoading)
            }
        }
        let timeline = session.timelines[channelId] ?? ChannelTimeline()
        return report(
            channel: channelId,
            shown: introShown() ? probe.introShownAt[channelId] : nil,
            count: timeline.postIds.count,
            more: timeline.hasMoreOlder,
            intro: introShown()
        ).json()
    }

    private func report(
        now: Double? = nil,
        channel: String? = nil,
        shown: Double? = nil,
        connected: Double? = nil,
        count: Int? = nil,
        more: Bool? = nil,
        intro: Bool? = nil,
        freeze: Double? = nil
    ) -> ProbeReport {
        ProbeReport(
            command: probe.commandAt,
            now: now ?? probe.clock(),
            channel: channel,
            shown: shown,
            connected: connected,
            count: count,
            more: more,
            intro: intro,
            freeze: freeze
        )
    }
}
