import AppKit
import Foundation
import SwiftUI
@testable import BoltunKit
@testable import BoltunUI

final class RoutedTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (Int, Data)

    private let lock = NSLock()
    private var routes: [(method: String, path: String, handler: Handler)] = []
    private var log: [URLRequest] = []

    func on(_ method: String, _ path: String, status: Int = 200, json: String) {
        let data = Data(json.utf8)
        on(method, path) { _ in (status, data) }
    }

    func on<T: Encodable>(_ method: String, _ path: String, status: Int = 200, value: T) {
        let data = (try? MattermostJSON.encoder.encode(value)) ?? Data()
        on(method, path) { _ in (status, data) }
    }

    func on(_ method: String, _ path: String, handler: @escaping Handler) {
        lock.withLock { routes.insert((method, path, handler), at: 0) }
    }

    var requests: [URLRequest] { lock.withLock { log } }

    func requests(_ method: String, _ path: String) -> [URLRequest] {
        requests.filter { $0.httpMethod == method && Self.matches(pattern: path, path: $0.url?.path ?? "") }
    }

    static func matches(pattern: String, path: String) -> Bool {
        let full = pattern.hasPrefix("/") ? pattern : "/api/v4/" + pattern
        if full.hasSuffix("*") { return path.hasPrefix(String(full.dropLast())) }
        return path == full
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        let handler: Handler? = lock.withLock {
            log.append(request)
            return routes.first { $0.method == method && Self.matches(pattern: $0.path, path: path) }?.handler
        }
        let (status, data): (Int, Data)
        if let handler {
            (status, data) = handler(request)
        } else if path.hasSuffix("/image") || path.hasSuffix("/thumbnail") || path.hasSuffix("/preview") {
            (status, data) = (200, TestImages.png(seed: path))
        } else {
            (status, data) = (404, Data(#"{"id":"not_found","message":"Not found","status_code":404}"#.utf8))
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        return (data, response)
    }
}

enum TestImages {
    static func png(seed: String, size: Int = 64) -> Data {
        let hue = CGFloat(abs(seed.hashValue % 360)) / 360
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(hue: hue, saturation: 0.45, brightness: 0.75, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSColor(hue: hue, saturation: 0.3, brightness: 0.95, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: size / 4, y: size / 2, width: size / 2, height: size / 2 - 4)).fill()
        NSBezierPath(ovalIn: NSRect(x: size / 8, y: -size / 3, width: size * 3 / 4, height: size * 2 / 3)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
}

enum Fixture {
    static let serverURL = URL(string: "http://mm.test")!
    static let baseTime: Int64 = 1_793_000_000_000

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    static var now: Date { (baseTime + 3_600_000).mattermostDate }

    static func minutes(_ value: Double) -> Int64 { baseTime + Int64(value * 60_000) }

    static let me = User(id: "me", username: "boltun", firstName: "Bolt", lastName: "Un", notifyProps: ["mention_keys": "boltun,deploy"])
    static let alice = User(id: "alice", username: "alice", firstName: "Alice", lastName: "Doe")
    static let bob = User(id: "bob", username: "bob.smith", firstName: "Bob", lastName: "Smith")
    static let carol = User(id: "carol", username: "carol", firstName: "Carol", lastName: "King", nickname: "CK")

    static func channels() -> [Channel] {
        [
            Channel(id: "town", teamId: "t1", type: .open, name: "town-square", displayName: "Town Square", header: "Company-wide announcements and **work** chat", purpose: "Everyone", lastPostAt: minutes(40), totalMsgCount: 30),
            Channel(id: "offtopic", teamId: "t1", type: .open, name: "off-topic", displayName: "Off-Topic", lastPostAt: minutes(20), totalMsgCount: 12),
            Channel(id: "secret", teamId: "t1", type: .private, name: "secret-plans", displayName: "Secret Plans", lastPostAt: minutes(10), totalMsgCount: 8),
            Channel(id: "muted", teamId: "t1", type: .open, name: "noise", displayName: "Noise", lastPostAt: minutes(5), totalMsgCount: 50),
            Channel(id: "old", teamId: "t1", type: .open, name: "old-stuff", displayName: "Old Stuff", deleteAt: 1),
            Channel(id: "dm-alice", type: .direct, name: "alice__me", displayName: "", lastPostAt: minutes(35), totalMsgCount: 4),
            Channel(id: "dm-bob", type: .direct, name: "bob__me", displayName: "", lastPostAt: minutes(1), totalMsgCount: 2),
            Channel(id: "gm", type: .group, name: "gm1", displayName: "alice, bob.smith, boltun", lastPostAt: minutes(2), totalMsgCount: 1),
            Channel(id: "design-general", teamId: "t2", type: .open, name: "town-square", displayName: "Design Square", totalMsgCount: 3),
        ]
    }

    static func members() -> [String: ChannelMember] {
        [
            "town": ChannelMember(channelId: "town", userId: "me", lastViewedAt: minutes(3), msgCount: 30),
            "offtopic": ChannelMember(channelId: "offtopic", userId: "me", msgCount: 9, mentionCount: 2),
            "secret": ChannelMember(channelId: "secret", userId: "me", msgCount: 6),
            "muted": ChannelMember(channelId: "muted", userId: "me", msgCount: 10, notifyProps: ["mark_unread": "mention"]),
            "dm-alice": ChannelMember(channelId: "dm-alice", userId: "me", msgCount: 4),
            "dm-bob": ChannelMember(channelId: "dm-bob", userId: "me", msgCount: 1, mentionCount: 1),
            "gm": ChannelMember(channelId: "gm", userId: "me", msgCount: 1),
            "design-general": ChannelMember(channelId: "design-general", userId: "me", msgCount: 3),
        ]
    }

    static func categories() -> [ChannelCategory] {
        [
            ChannelCategory(id: "fav", teamId: "t1", type: .favorites, displayName: "Favorites", channelIds: ["offtopic"]),
            ChannelCategory(id: "chan", teamId: "t1", type: .channels, displayName: "Channels", channelIds: ["town", "secret", "muted", "old"]),
            ChannelCategory(id: "dms", teamId: "t1", type: .directMessages, displayName: "Direct Messages", channelIds: ["dm-alice", "dm-bob", "gm"]),
        ]
    }

    static func townPosts() -> [Post] {
        let image = FileInfo(id: "f-img", postId: "p6", name: "screenshot.png", extension: "png", size: 182_000, mimeType: "image/png", width: 640, height: 400, hasPreviewImage: true)
        let doc = FileInfo(id: "f-doc", postId: "p6", name: "quarterly-report.pdf", extension: "pdf", size: 2_400_000, mimeType: "application/pdf")
        return [
            Post(id: "p0", createAt: minutes(-1500), userId: "alice", channelId: "town", message: "alice joined the channel.", type: "system_join_channel"),
            Post(id: "p1", createAt: minutes(0), userId: "alice", channelId: "town", message: "Good morning team! The **release** is scheduled for today.", replyCount: 2),
            Post(id: "p2", createAt: minutes(1), userId: "alice", channelId: "town", message: "Please review the checklist before lunch.",
                 metadata: PostMetadata(reactions: [Reaction(userId: "me", postId: "p2", emojiName: "+1", createAt: 1), Reaction(userId: "bob", postId: "p2", emojiName: "+1", createAt: 2), Reaction(userId: "carol", postId: "p2", emojiName: "tada", createAt: 3)])),
            Post(id: "p3", createAt: minutes(4), userId: "bob", channelId: "town", rootId: "p1", message: "On it. I'll update the staging environment first."),
            Post(id: "p4", createAt: minutes(5), editAt: minutes(6), userId: "me", channelId: "town", message: "Thanks @alice, I'll handle the changelog."),
            Post(id: "p5", createAt: minutes(12), userId: "carol", channelId: "town", message: "```swift\nlet session = ServerSession(serverId: id, client: client)\nawait session.start()\n```"),
            Post(id: "p6", createAt: minutes(20), userId: "bob", channelId: "town", message: "Here are the files @boltun asked for", fileIds: ["f-img", "f-doc"], metadata: PostMetadata(files: [image, doc])),
            Post(id: "p7", createAt: minutes(21), deleteAt: minutes(22), userId: "bob", channelId: "town", message: ""),
            Post(id: "p8", createAt: minutes(40), isPinned: true, userId: "carol", channelId: "town", message: "Deploy finished. 🎉 See https://example.com/status"),
            Post(id: "r1", createAt: minutes(41), userId: "alice", channelId: "town", rootId: "p1", message: "Thread reply about the release"),
        ]
    }

    @MainActor
    static func populate(_ session: ServerSession) {
        session.me = me
        session.users = ["me": me, "alice": alice, "bob": bob, "carol": carol]
        session.config = ClientConfig(values: ["MaxPostSize": "16383", "SiteName": "Test"])
        session.teams = [Team(id: "t1", name: "engineering", displayName: "Engineering"), Team(id: "t2", name: "design", displayName: "Design")]
        session.teamUnreads = ["t2": TeamUnread(teamId: "t2", msgCount: 3, mentionCount: 1)]
        session.currentTeamId = "t1"
        session.loadedTeams = ["t1"]
        session.channels = Dictionary(uniqueKeysWithValues: channels().map { ($0.id, $0) })
        session.members = members()
        session.categories = ["t1": categories()]
        session.statuses = ["alice": .online, "bob": .away, "carol": .dnd]
        let posts = townPosts()
        session.posts = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
        var timeline = ChannelTimeline()
        timeline.postIds = posts.map(\.id)
        timeline.loaded = true
        timeline.hasMoreOlder = false
        timeline.lastViewedAtOnOpen = minutes(15)
        session.timelines = ["town": timeline]
        session.currentChannelId = "town"
        session.connection = .connected
    }

    @MainActor
    static func transport() -> RoutedTransport {
        let transport = RoutedTransport()
        transport.on("POST", "channels/members/me/view", json: #"{"status":"OK"}"#)
        transport.on("PUT", "users/me/teams/*", json: "{}")
        transport.on("PUT", "users/me/preferences", json: #"{"status":"OK"}"#)
        transport.on("PUT", "users/me/*", json: #"{"status":"OK"}"#)
        transport.on("POST", "users/ids", value: [alice, bob, carol])
        transport.on("POST", "users/status/ids", value: [UserStatus(userId: "alice", status: .online)])
        transport.on("GET", "channels/*", json: #"{"channel_id":"town","member_count":42,"pinnedpost_count":1}"#)
        return transport
    }

    @MainActor
    static func session(transport: RoutedTransport = transport()) -> ServerSession {
        let session = ServerSession(serverId: UUID(), client: APIClient(baseURL: serverURL, token: "token", transport: transport))
        populate(session)
        return session
    }

    @MainActor
    static func workspace(transport: RoutedTransport = transport()) -> Workspace {
        let workspace = Workspace(session: session(transport: transport), serverURL: serverURL)
        workspace.now = { now }
        workspace.calendar = calendar
        workspace.pasteboard = NSPasteboard(name: NSPasteboard.Name("boltun-tests-\(UUID().uuidString)"))
        workspace.openExternal = { _ in }
        workspace.revealInFinder = { _ in }
        return workspace
    }

    @MainActor
    static func appModel(transport: RoutedTransport = transport(), secondNeedsLogin: Bool = true) -> (AppModel, ServerSession) {
        let first = ServerConfig(name: "Acme Corp", url: serverURL)
        let second = ServerConfig(name: "Side Project", url: URL(string: "http://side.test")!)
        let third = ServerConfig(name: "community", url: URL(string: "http://community.test")!)
        var tokens = [first.id: "token", third.id: "token3"]
        if !secondNeedsLogin { tokens[second.id] = "token2" }
        let model = AppModel(store: MemoryAppStateStore(AppState(servers: [first, second, third])), credentials: MemoryCredentialStore(tokens), transport: transport)
        let session = model.makeSession(for: first)
        populate(session)
        model.makeSession(for: second)
        let community = model.makeSession(for: third)
        community.connection = .reconnecting
        community.channels = ["x": Channel(id: "x", teamId: "c", name: "x", totalMsgCount: 5)]
        community.members = ["x": ChannelMember(channelId: "x", userId: "", msgCount: 1, mentionCount: 3)]
        community.teams = [Team(id: "c", name: "c", displayName: "C")]
        community.loadedTeams = ["c"]
        return (model, session)
    }
}

@MainActor
enum MainSnapshot {
    static var directory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["BOLTUN_SNAPSHOT_DIR"] ?? "/tmp/boltun-shots")
    }

    @discardableResult
    static func render<V: View>(_ view: V, size: CGSize, name: String? = nil, settle: Duration = .milliseconds(250)) async -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height).preferredColorScheme(.dark))
        hosting.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let deadline = ContinuousClock.now + settle
        while ContinuousClock.now < deadline {
            pump(0.02)
            try? await Task.sleep(for: .milliseconds(5))
            hosting.layoutSubtreeIfNeeded()
        }
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let name {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
        }
        window.contentView = nil
        window.close()
        return rep
    }

    static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func distinctColors(_ rep: NSBitmapImageRep, samples: Int = 24) -> Int {
        var colors = Set<String>()
        for x in stride(from: 0, to: rep.pixelsWide, by: max(1, rep.pixelsWide / samples)) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: max(1, rep.pixelsHigh / samples)) {
                if let color = rep.colorAt(x: x, y: y) {
                    colors.insert(String(format: "%.2f-%.2f-%.2f", color.redComponent, color.greenComponent, color.blueComponent))
                }
            }
        }
        return colors.count
    }
}
