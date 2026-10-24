import AppKit
import BoltunKit
import Foundation
@preconcurrency import UserNotifications

public struct NotificationPayload: Hashable, Sendable {
    public var identifier: String
    public var title: String
    public var subtitle: String
    public var body: String
    public var threadIdentifier: String
    public var playSound: Bool
    public var userInfo: [String: String]

    public init(_ notification: MentionNotification, serverName: String?, playSound: Bool) {
        identifier = "\(notification.serverId.uuidString):\(notification.postId)"
        title = notification.title
        subtitle = serverName ?? ""
        body = notification.body
        threadIdentifier = notification.channelId
        self.playSound = playSound
        userInfo = NotificationRoute(notification).userInfo
    }
}

public struct NotificationRoute: Hashable, Sendable {
    public var serverId: UUID
    public var teamId: String
    public var channelId: String
    public var rootId: String

    public init(serverId: UUID, teamId: String, channelId: String, rootId: String) {
        self.serverId = serverId
        self.teamId = teamId
        self.channelId = channelId
        self.rootId = rootId
    }

    public init(_ notification: MentionNotification) {
        self.init(serverId: notification.serverId, teamId: notification.teamId, channelId: notification.channelId, rootId: notification.rootId)
    }

    public init?(userInfo: [AnyHashable: Any]) {
        guard let server = userInfo["serverId"] as? String, let serverId = UUID(uuidString: server),
              let channelId = userInfo["channelId"] as? String
        else { return nil }
        self.init(serverId: serverId, teamId: userInfo["teamId"] as? String ?? "", channelId: channelId, rootId: userInfo["rootId"] as? String ?? "")
    }

    public var userInfo: [String: String] {
        ["serverId": serverId.uuidString, "teamId": teamId, "channelId": channelId, "rootId": rootId]
    }
}

@MainActor
public protocol NotificationPosting: AnyObject {
    var onActivate: ((NotificationRoute) -> Void)? { get set }
    func requestAuthorization() async -> Bool
    func post(_ payload: NotificationPayload) async
    func removeDelivered(threadIdentifier: String) async
}

@MainActor
public protocol DockControlling: AnyObject {
    var badgeLabel: String? { get set }
    var isAppActive: Bool { get }
    func requestAttention()
    func activate()
}

@MainActor
final class AppKitDock: DockControlling {
    var badgeLabel: String? {
        get { NSApp.dockTile.badgeLabel }
        set { NSApp.dockTile.badgeLabel = newValue }
    }

    var isAppActive: Bool { NSApp.isActive }

    func requestAttention() {
        NSApp.requestUserAttention(.informationalRequest)
    }

    func activate() {
        NSApp.activate()
    }
}

@MainActor
public final class NotificationCoordinator {
    let model: AppModel
    let router: AppRouter
    let center: NotificationPosting
    let dock: DockControlling
    private(set) var authorization: Bool?

    public init(model: AppModel, router: AppRouter, center: NotificationPosting, dock: DockControlling) {
        self.model = model
        self.router = router
        self.center = center
        self.dock = dock
        center.onActivate = { [weak self] route in
            Task { await self?.activate(route) }
        }
    }

    public func install() {
        model.onNotification = { [weak self] notification in
            Task { await self?.deliver(notification) }
        }
    }

    public func payload(for notification: MentionNotification) -> NotificationPayload {
        let serverName = model.servers.count > 1 ? model.servers.first { $0.id == notification.serverId }?.name : nil
        return NotificationPayload(notification, serverName: serverName, playSound: model.settings.notificationSound)
    }

    public func deliver(_ notification: MentionNotification) async {
        if model.settings.bounceDockIcon, !dock.isAppActive { dock.requestAttention() }
        guard model.settings.notificationsEnabled else { return }
        if authorization == nil { authorization = await center.requestAuthorization() }
        guard authorization == true else { return }
        await center.post(payload(for: notification))
    }

    public func activate(_ route: NotificationRoute) async {
        dock.activate()
        await router.route(serverId: route.serverId, teamId: route.teamId, channelId: route.channelId, rootId: route.rootId)
        await center.removeDelivered(threadIdentifier: route.channelId)
    }

    public func channelViewed(_ channelId: String) async {
        await center.removeDelivered(threadIdentifier: channelId)
    }
}

@MainActor
final class SystemNotificationCenter: NSObject, NotificationPosting, UNUserNotificationCenterDelegate {
    var onActivate: ((NotificationRoute) -> Void)?
    private let center: UNUserNotificationCenter

    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    override init() {
        center = UNUserNotificationCenter.current()
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func post(_ payload: NotificationPayload) async {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.subtitle = payload.subtitle
        content.body = payload.body
        content.threadIdentifier = payload.threadIdentifier
        content.userInfo = payload.userInfo
        if payload.playSound { content.sound = .default }
        try? await center.add(UNNotificationRequest(identifier: payload.identifier, content: content, trigger: nil))
    }

    func removeDelivered(threadIdentifier: String) async {
        let delivered = await center.deliveredNotifications()
        let ids = delivered.filter { $0.request.content.threadIdentifier == threadIdentifier }.map(\.request.identifier)
        if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let route = NotificationRoute(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run { self.onActivate?(route) }
    }
}
