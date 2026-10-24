import Foundation
import Testing
@testable import BoltunKit
@testable import BoltunUI

final class GatedTransport: HTTPTransport, @unchecked Sendable {
    let inner: RoutedTransport
    let method: String
    let path: String
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ inner: RoutedTransport, method: String, path: String) {
        self.inner = inner
        self.method = method
        self.path = path
    }

    var waitingCount: Int { lock.withLock { waiting.count } }

    func releaseOne() {
        let next: CheckedContinuation<Void, Never>? = lock.withLock { waiting.isEmpty ? nil : waiting.removeFirst() }
        next?.resume()
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.httpMethod == method, RoutedTransport.matches(pattern: path, path: request.url?.path ?? "") {
            await withCheckedContinuation { continuation in
                lock.withLock { waiting.append(continuation) }
            }
        }
        return try await inner.send(request)
    }
}

@Suite @MainActor struct MainComposerQueueTests {
    func make(status: @escaping @Sendable (String) -> Int = { _ in 201 }) -> (Workspace, GatedTransport, ComposerState) {
        let routed = Fixture.transport()
        routed.on("POST", "posts") { request in
            let json = body(request)
            let message = json["message"] as? String ?? ""
            let post = Post(id: "new-\(message)", createAt: Fixture.minutes(50), userId: "me", channelId: json["channel_id"] as? String ?? "", message: message)
            let code = status(message)
            return (code, code < 300 ? try! MattermostJSON.encoder.encode(post) : Data(#"{"message":"boom"}"#.utf8))
        }
        let gated = GatedTransport(routed, method: "POST", path: "posts")
        let session = ServerSession(serverId: UUID(), client: APIClient(baseURL: Fixture.serverURL, token: "token", transport: gated))
        Fixture.populate(session)
        let workspace = Workspace(session: session, serverURL: Fixture.serverURL)
        return (workspace, gated, workspace.composer(for: ComposerTarget(channelId: "town")))
    }

    func type(_ composer: ComposerState, _ text: String) {
        composer.userEdited(text: text, cursor: (text as NSString).length)
    }

    @Test func enterWorksWhilePreviousSendIsInFlight() async {
        let (workspace, gated, composer) = make()
        for message in ["one", "two", "three"] {
            type(composer, message)
            #expect(composer.canSend)
            #expect(composer.perform(.send))
            #expect(composer.text.isEmpty)
        }
        #expect(await eventually { gated.waitingCount == 1 })
        #expect(composer.pendingSends == 3)
        for remaining in [2, 1, 0] {
            gated.releaseOne()
            #expect(await eventually { composer.pendingSends == remaining })
            #expect(await eventually { gated.waitingCount == min(remaining, 1) })
        }
        let sent = gated.inner.requests("POST", "posts").map { body($0)["message"] as? String }
        #expect(sent == ["one", "two", "three"])
        #expect(Array(workspace.session.timelinePosts(channelId: "town").suffix(3).map(\.message)) == ["one", "two", "three"])
    }

    @Test func failedQueuedSendKeepsNewerText() async {
        let (_, gated, composer) = make { $0 == "two" ? 500 : 201 }
        type(composer, "one")
        composer.perform(.send)
        type(composer, "two")
        composer.perform(.send)
        #expect(await eventually { composer.text.isEmpty && gated.waitingCount == 1 })
        type(composer, "draft")
        gated.releaseOne()
        #expect(await eventually { gated.waitingCount == 1 })
        gated.releaseOne()
        #expect(await eventually { composer.pendingSends == 0 })
        #expect(composer.text == "draft\ntwo")
    }

    @Test func failedEditDoesNotClobberNewDraft() async {
        let routed = Fixture.transport()
        routed.on("PUT", "posts/p4/patch", status: 500, json: "{}")
        let gated = GatedTransport(routed, method: "PUT", path: "posts/p4/patch")
        let session = ServerSession(serverId: UUID(), client: APIClient(baseURL: Fixture.serverURL, token: "token", transport: gated))
        Fixture.populate(session)
        let workspace = Workspace(session: session, serverURL: Fixture.serverURL)
        let composer = workspace.composer(for: ComposerTarget(channelId: "town"))
        workspace.beginEdit(session.posts["p4"]!)
        type(composer, "changed")
        composer.perform(.send)
        #expect(await eventually { gated.waitingCount == 1 && composer.editingPostId == nil })
        type(composer, "fresh")
        gated.releaseOne()
        #expect(await eventually { composer.pendingSends == 0 })
        #expect(composer.editingPostId == nil)
        #expect(composer.text == "fresh")
    }
}
