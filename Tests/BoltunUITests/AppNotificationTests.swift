import BoltunKit
import Foundation
import Testing
@testable import BoltunUI

@MainActor
struct AppNotificationTests {
    func mention(_ serverId: UUID, rootId: String = "") -> MentionNotification {
        MentionNotification(serverId: serverId, teamId: "t2", channelId: "c4", postId: "p1", rootId: rootId, title: "Alice", body: "@boltun hi")
    }

    @Test func buildsPayload() {
        let id = UUID()
        let payload = NotificationPayload(mention(id, rootId: "r1"), serverName: "Alpha", playSound: true)
        #expect(payload.identifier == "\(id.uuidString):p1")
        #expect(payload.title == "Alice")
        #expect(payload.subtitle == "Alpha")
        #expect(payload.body == "@boltun hi")
        #expect(payload.threadIdentifier == "c4")
        #expect(payload.playSound)
        #expect(payload.userInfo == ["serverId": id.uuidString, "teamId": "t2", "channelId": "c4", "rootId": "r1"])
        #expect(NotificationPayload(mention(id), serverName: nil, playSound: false).subtitle == "")
    }

    @Test func roundTripsRoute() {
        let route = NotificationRoute(mention(UUID(), rootId: "r1"))
        let decoded = NotificationRoute(userInfo: route.userInfo as [AnyHashable: Any])
        #expect(decoded == route)
        #expect(NotificationRoute(userInfo: ["channelId": "c"]) == nil)
        #expect(NotificationRoute(userInfo: ["serverId": "nope", "channelId": "c"]) == nil)
        let minimal = NotificationRoute(userInfo: ["serverId": route.serverId.uuidString, "channelId": "c"])
        #expect(minimal?.teamId == "")
        #expect(minimal?.rootId == "")
    }

    @Test func subtitleOnlyWithMultipleServers() {
        let one = Harness.server("One", port: 1)
        let harness = Harness(servers: [one])
        let center = SilentNotificationCenter()
        let coordinator = NotificationCoordinator(model: harness.model, router: AppRouter(model: harness.model), center: center, dock: FakeDock())
        #expect(coordinator.payload(for: mention(one.id)).subtitle == "")
        harness.model.addServer(name: "Two", url: URL(string: "https://two.example.com")!)
        #expect(coordinator.payload(for: mention(one.id)).subtitle == "One")
        harness.model.settings.notificationSound = false
        #expect(!coordinator.payload(for: mention(one.id)).playSound)
    }

    @Test func deliversAndBounces() async {
        let server = Harness.server()
        let harness = Harness(servers: [server])
        let center = SilentNotificationCenter()
        let dock = FakeDock()
        let coordinator = NotificationCoordinator(model: harness.model, router: AppRouter(model: harness.model), center: center, dock: dock)
        coordinator.install()
        await coordinator.deliver(mention(server.id))
        await coordinator.deliver(mention(server.id))
        #expect(center.posted.count == 2)
        #expect(center.authorizationRequests == 1)
        #expect(dock.attentionRequests == 2)
        dock.isAppActive = true
        await coordinator.deliver(mention(server.id))
        #expect(dock.attentionRequests == 2)
        harness.model.onNotification?(mention(server.id))
        #expect(await eventually { center.posted.count == 4 })
    }

    @Test func respectsSettings() async {
        let server = Harness.server()
        var settings = AppSettings()
        settings.notificationsEnabled = false
        settings.bounceDockIcon = false
        let harness = Harness(servers: [server], settings: settings)
        let center = SilentNotificationCenter()
        let dock = FakeDock()
        let coordinator = NotificationCoordinator(model: harness.model, router: AppRouter(model: harness.model), center: center, dock: dock)
        await coordinator.deliver(mention(server.id))
        #expect(center.posted.isEmpty)
        #expect(center.authorizationRequests == 0)
        #expect(dock.attentionRequests == 0)
    }

    @Test func skipsWhenUnauthorized() async {
        let server = Harness.server()
        let harness = Harness(servers: [server])
        let center = SilentNotificationCenter()
        center.authorized = false
        let coordinator = NotificationCoordinator(model: harness.model, router: AppRouter(model: harness.model), center: center, dock: FakeDock())
        await coordinator.deliver(mention(server.id))
        await coordinator.deliver(mention(server.id))
        #expect(center.posted.isEmpty)
        #expect(center.authorizationRequests == 1)
    }

    @Test func activationRoutesToChannelAndThread() async {
        let harness = await Harness.connected()
        let server = harness.model.servers[0]
        let center = SilentNotificationCenter()
        let dock = FakeDock()
        let router = AppRouter(model: harness.model)
        let coordinator = NotificationCoordinator(model: harness.model, router: router, center: center, dock: dock)
        center.onActivate?(NotificationRoute(mention(server.id, rootId: "r1")))
        #expect(await eventually { center.removed.contains("c4") })
        #expect(dock.activations == 1)
        #expect(harness.model.selectedSession?.currentChannelId == "c4")
        #expect(router.pendingThreadRootId == "r1")
        await coordinator.channelViewed("c1")
        #expect(center.removed.last == "c1")
    }
}

@MainActor
struct AppBadgeTests {
    @Test func tracksBadgeLabel() async {
        let harness = await Harness.connected()
        var applied: [String?] = []
        let controller = DockBadgeController(model: harness.model) { applied.append($0) }
        controller.start()
        controller.start()
        #expect(applied == ["1"])
        #expect(controller.currentLabel == "1")
        harness.model.settings.showUnreadBadge = false
        #expect(await eventually { applied.last == .some(nil) })
        harness.model.settings.fontScale = 1.2
        harness.model.settings.showUnreadBadge = true
        #expect(await eventually { applied.last == "1" })
        #expect(applied == ["1", nil, "1"])
    }

    @Test func observerSkipsUnchangedValues() async {
        let harness = Harness()
        var values: [Double] = []
        let observer = ValueObserver(read: { harness.model.settings.fontScale }) { values.append($0) }
        observer.start()
        harness.model.settings.showUnreadBadge = false
        try? await Task.sleep(for: .milliseconds(30))
        harness.model.settings.fontScale = 1.5
        #expect(await eventually { values == [1.0, 1.5] })
        #expect(observer.value == 1.5)
    }
}
