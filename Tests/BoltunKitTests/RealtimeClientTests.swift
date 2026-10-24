import Foundation
import Testing
@testable import BoltunKit

@Suite struct RealtimeClientTests {
    let url = URL(string: "wss://chat.example.com/api/v4/websocket")!

    func make(_ connector: FakeConnector, sleeper: SleepRecorder = .blocking(), maxBackoff: Duration = .seconds(30), handshakeTimeout: Duration? = nil) -> RealtimeClient {
        RealtimeClient(url: url, token: "tok", connector: connector, maxBackoff: maxBackoff, handshakeTimeout: handshakeTimeout, sleeper: sleeper.sleeper)
    }

    func socket(_ connector: FakeConnector, _ index: Int) async throws -> FakeSocket {
        #expect(await eventuallyAsync { connector.socket(index) != nil })
        return try #require(connector.socket(index))
    }

    func posted(seq: Int64) -> [String: Any] {
        Fixtures.event("posted", data: ["post": Fixtures.json(Fixtures.post("p\(seq)", channel: "c", user: "u", message: "m", createAt: seq))], channel: "c", seq: seq)
    }

    @Test func helloAnnouncesFirstConnectionAndForwardsEvents() async throws {
        let connector = FakeConnector()
        let client = make(connector)
        let collector = EventCollector(client)
        await client.start()
        await client.start()
        let first = try await socket(connector, 0)
        first.push(Fixtures.hello("conn1"))
        first.push(posted(seq: 1))
        #expect(await eventuallyAsync { await collector.received.count == 1 })
        #expect(await collector.connections == [false])
        #expect(await collector.received.first?.event == "posted")
        #expect(connector.urls == [url])
        #expect(connector.tokens == ["tok"])
        #expect(connector.sockets.count == 1)
        let ping = try #require(first.sentObjects.first)
        #expect(ping["action"] as? String == "ping")
        #expect(ping["seq"] as? Int == 1)
        await client.stop()
    }

    @Test func userTypingSendsAction() async throws {
        let connector = FakeConnector()
        let client = make(connector)
        await client.userTyping(channelId: "ignored")
        await client.start()
        let first = try await socket(connector, 0)
        first.push(Fixtures.hello("conn1"))
        #expect(await eventuallyAsync { first.sent.count == 1 })
        await client.userTyping(channelId: "c1", parentId: "root")
        await client.userTyping(channelId: "c2")
        let actions = first.sentObjects
        #expect(actions.count == 3)
        #expect(actions[1]["action"] as? String == "user_typing")
        #expect(actions[1]["seq"] as? Int == 2)
        #expect(actions[1]["data"] as? [String: String] == ["channel_id": "c1", "parent_id": "root"])
        #expect(actions[2]["seq"] as? Int == 3)
        #expect(actions[2]["data"] as? [String: String] == ["channel_id": "c2", "parent_id": ""])
        #expect(first.sent[1] == #"{"action":"user_typing","data":{"channel_id":"c1","parent_id":"root"},"seq":2}"#)
        await client.stop()
    }

    @Test func reconnectResumesWithConnectionIdAndNextSequence() async throws {
        let connector = FakeConnector()
        let sleeper = SleepRecorder()
        let client = make(connector, sleeper: sleeper)
        let collector = EventCollector(client)
        await client.start()
        let first = try await socket(connector, 0)
        first.push(Fixtures.hello("conn1"))
        first.push(posted(seq: 1))
        first.push(posted(seq: 2))
        #expect(await eventuallyAsync { await collector.received.count == 2 })
        first.close()
        let second = try await socket(connector, 1)
        #expect(await eventuallyAsync { await collector.disconnects == 1 })
        #expect(sleeper.durations == [.seconds(1)])
        let components = try #require(URLComponents(url: connector.urls[1], resolvingAgainstBaseURL: false))
        #expect(components.path == "/api/v4/websocket")
        #expect(components.queryItems == [URLQueryItem(name: "connection_id", value: "conn1"), URLQueryItem(name: "sequence_number", value: "3")])
        second.push(posted(seq: 3))
        #expect(await eventuallyAsync { await collector.received.count == 3 })
        #expect(await collector.connections == [false, false])
        await client.stop()
    }

    @Test func pingReplyAnnouncesResumedConnection() async throws {
        let connector = FakeConnector()
        let client = make(connector, sleeper: SleepRecorder())
        let collector = EventCollector(client)
        await client.start()
        let first = try await socket(connector, 0)
        first.push(#"{"status":"OK","seq_reply":1}"#)
        first.push(Fixtures.hello("conn1"))
        #expect(await eventuallyAsync { await collector.connections == [false] })
        first.close()
        let second = try await socket(connector, 1)
        second.push(#"{"status":"OK","seq_reply":1,"data":{"text":"pong"}}"#)
        second.push(#"{"status":"OK","seq_reply":2}"#)
        #expect(await eventuallyAsync { await collector.connections == [false, false] })
        await client.stop()
    }

    @Test func newConnectionIdAfterReconnectNeedsResync() async throws {
        let connector = FakeConnector()
        let client = make(connector, sleeper: SleepRecorder())
        let collector = EventCollector(client)
        await client.start()
        let first = try await socket(connector, 0)
        first.push(Fixtures.hello("conn1"))
        first.push(posted(seq: 1))
        #expect(await eventuallyAsync { await collector.received.count == 1 })
        first.close()
        let second = try await socket(connector, 1)
        second.push(Fixtures.hello("conn2"))
        second.push(posted(seq: 1))
        #expect(await eventuallyAsync { await collector.received.count == 2 })
        #expect(await collector.connections == [false, true])
        second.close()
        _ = try await socket(connector, 2)
        #expect(connector.urls[2].query?.contains("connection_id=conn2&sequence_number=2") == true)
        await client.stop()
    }

    @Test func helloWithSameConnectionIdIsAResume() async throws {
        let connector = FakeConnector()
        let client = make(connector, sleeper: SleepRecorder())
        let collector = EventCollector(client)
        await client.start()
        let first = try await socket(connector, 0)
        first.push(Fixtures.hello("conn1"))
        #expect(await eventuallyAsync { await collector.connections.count == 1 })
        first.close()
        let second = try await socket(connector, 1)
        second.push(Fixtures.hello("conn1"))
        #expect(await eventuallyAsync { await collector.connections == [false, false] })
        await client.stop()
    }

    @Test func sequenceGapRequestsResyncAndDuplicatesAreDropped() async throws {
        let connector = FakeConnector()
        let client = make(connector)
        let collector = EventCollector(client)
        await client.start()
        let first = try await socket(connector, 0)
        first.push(Fixtures.hello("conn1"))
        first.push(posted(seq: 1))
        first.push(posted(seq: 1))
        first.push(posted(seq: 3))
        first.push(posted(seq: 2))
        first.push(posted(seq: 4))
        #expect(await eventuallyAsync { await collector.received.count == 3 })
        #expect(await collector.received.map(\.seq) == [1, 3, 4])
        #expect(await collector.connections == [false, true])
        await client.stop()
    }

    @Test func gapRightAfterResumeRequestsResync() async throws {
        let connector = FakeConnector()
        let client = make(connector, sleeper: SleepRecorder())
        let collector = EventCollector(client)
        await client.start()
        let first = try await socket(connector, 0)
        first.push(Fixtures.hello("conn1"))
        first.push(posted(seq: 1))
        #expect(await eventuallyAsync { await collector.received.count == 1 })
        first.close()
        let second = try await socket(connector, 1)
        second.push(posted(seq: 1))
        second.push(posted(seq: 5))
        #expect(await eventuallyAsync { await collector.received.count == 2 })
        #expect(await collector.connections == [false, false, true])
        await client.stop()
    }

    @Test func eventsWithoutSequenceOrBeforeHelloAreForwarded() async throws {
        let connector = FakeConnector()
        let client = make(connector)
        let collector = EventCollector(client)
        await client.start()
        let first = try await socket(connector, 0)
        first.push("garbage")
        first.push(posted(seq: 9))
        first.push(Fixtures.hello("conn1"))
        first.push(Fixtures.event("status_change", data: ["user_id": "u", "status": "away"], seq: 0))
        #expect(await eventuallyAsync { await collector.received.count == 2 })
        #expect(await collector.connections == [false])
        await client.stop()
    }

    @Test func backoffGrowsAndIsCapped() async throws {
        let connector = FakeConnector { socket, _ in socket.close() }
        let sleeper = SleepRecorder { _, count in count >= 5 }
        let client = make(connector, sleeper: sleeper, maxBackoff: .seconds(4))
        let collector = EventCollector(client)
        await client.start()
        #expect(await eventuallyAsync { sleeper.durations.count == 5 })
        #expect(sleeper.durations == [.seconds(1), .seconds(2), .seconds(4), .seconds(4), .seconds(4)])
        #expect(await eventuallyAsync { await collector.disconnects == 5 })
        #expect(await collector.connections.isEmpty)
        await client.stop()
    }

    @Test func attemptsResetAfterSuccessfulReceive() async throws {
        let connector = FakeConnector { socket, index in
            if index == 1 { socket.close() }
        }
        let sleeper = SleepRecorder { _, count in count >= 3 }
        let client = make(connector, sleeper: sleeper)
        await client.start()
        let first = try await socket(connector, 0)
        first.push(Fixtures.hello("conn1"))
        #expect(await eventuallyAsync { first.sent.count == 1 })
        first.close()
        let third = try await socket(connector, 2)
        third.push(posted(seq: 1))
        #expect(await eventuallyAsync { third.sent.count == 1 })
        try await Task.sleep(for: .milliseconds(20))
        third.close()
        #expect(await eventuallyAsync { sleeper.durations.count == 3 })
        #expect(sleeper.durations == [.seconds(1), .seconds(2), .seconds(1)])
        await client.stop()
    }

    @Test func reconnectNowSkipsBackoff() async throws {
        let connector = FakeConnector()
        let sleeper = SleepRecorder.blocking()
        let client = make(connector, sleeper: sleeper)
        let collector = EventCollector(client)
        await client.start()
        let first = try await socket(connector, 0)
        first.push(Fixtures.hello("conn1"))
        #expect(await eventuallyAsync { await collector.connections.count == 1 })
        await client.reconnectNow()
        let second = try await socket(connector, 1)
        #expect(first.isClosed)
        #expect(sleeper.durations.isEmpty)
        second.push(Fixtures.hello("conn1"))
        #expect(await eventuallyAsync { await collector.connections == [false, false] })
        await client.stop()
    }

    @Test func reconnectNowInterruptsBackoffWait() async throws {
        let connector = FakeConnector { socket, index in
            if index == 0 { socket.close() }
        }
        let sleeper = SleepRecorder.blocking()
        let client = make(connector, sleeper: sleeper)
        await client.start()
        #expect(await eventuallyAsync { sleeper.durations.count == 1 })
        await client.reconnectNow()
        _ = try await socket(connector, 1)
        #expect(sleeper.durations.count == 1)
        await client.stop()
    }

    @Test func stopClosesAndFinishesForGood() async throws {
        let connector = FakeConnector()
        let client = make(connector)
        let collector = EventCollector(client)
        await client.start()
        let first = try await socket(connector, 0)
        first.push(Fixtures.hello("conn1"))
        #expect(await eventuallyAsync { await collector.connections.count == 1 })
        await client.stop()
        #expect(first.isClosed)
        #expect(await eventuallyAsync { await collector.finished })
        await client.start()
        await client.reconnectNow()
        try await Task.sleep(for: .milliseconds(30))
        #expect(connector.sockets.count == 1)
        #expect(await collector.disconnects == 0)
    }

    @Test func stopDuringBackoffEndsLoop() async throws {
        let connector = FakeConnector { socket, _ in socket.close() }
        let sleeper = SleepRecorder.blocking()
        let client = make(connector, sleeper: sleeper)
        let collector = EventCollector(client)
        await client.start()
        #expect(await eventuallyAsync { sleeper.durations.count == 1 })
        await client.stop()
        #expect(await eventuallyAsync { await collector.finished })
        try await Task.sleep(for: .milliseconds(30))
        #expect(connector.sockets.count == 1)
    }

    @Test func handshakeTimeoutClosesSilentConnection() async throws {
        let connector = FakeConnector()
        let sleeper = SleepRecorder { duration, _ in duration != .seconds(7) }
        let client = make(connector, sleeper: sleeper, handshakeTimeout: .seconds(7))
        let collector = EventCollector(client)
        await client.start()
        let first = try await socket(connector, 0)
        #expect(await eventuallyAsync { first.isClosed })
        #expect(await eventuallyAsync { await collector.disconnects == 1 })
        #expect(sleeper.durations.prefix(2) == [.seconds(7), .seconds(1)])
        await client.stop()
    }

    @Test func handshakeTimeoutIgnoredOnceEstablished() async throws {
        let connector = FakeConnector()
        let gate = Gate()
        let client = RealtimeClient(url: url, token: "tok", connector: connector, handshakeTimeout: .seconds(7)) { duration in
            if duration == .seconds(7) {
                await gate.wait()
            } else {
                try await Task.sleep(for: .seconds(3600))
            }
        }
        let collector = EventCollector(client)
        await client.start()
        let first = try await socket(connector, 0)
        first.push(Fixtures.hello("conn1"))
        #expect(await eventuallyAsync { await collector.connections.count == 1 })
        await gate.open()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!first.isClosed)
        await client.stop()
    }

    @Test func backoffSchedule() async {
        let client = make(FakeConnector())
        #expect(await client.backoff(attempt: 0) == .seconds(1))
        #expect(await client.backoff(attempt: 1) == .seconds(1))
        #expect(await client.backoff(attempt: 2) == .seconds(2))
        #expect(await client.backoff(attempt: 5) == .seconds(16))
        #expect(await client.backoff(attempt: 6) == .seconds(30))
        #expect(await client.backoff(attempt: 64) == .seconds(30))
        #expect(await client.connectionURL() == url)
    }

    @Test func urlSessionConnectorFailsAgainstClosedPort() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        let connector = URLSessionWebSocketConnector(session: URLSession(configuration: configuration))
        let connection = connector.connect(url: URL(string: "ws://127.0.0.1:9/api/v4/websocket")!, token: "tok")
        await #expect(throws: (any Error).self) { try await connection.send("{}") }
        await #expect(throws: (any Error).self) { try await connection.receive() }
        connection.close()
        _ = URLSessionWebSocketConnector()
    }
}
