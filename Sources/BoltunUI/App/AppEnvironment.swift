import AppKit
import BoltunKit
import Foundation
import SwiftUI

@MainActor
final class SilentNotificationCenter: NotificationPosting {
    var onActivate: ((NotificationRoute) -> Void)?
    private(set) var posted: [NotificationPayload] = []
    private(set) var removed: [String] = []
    var authorized = true
    private(set) var authorizationRequests = 0

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return authorized
    }

    func post(_ payload: NotificationPayload) async {
        posted.append(payload)
    }

    func removeDelivered(threadIdentifier: String) async {
        removed.append(threadIdentifier)
    }
}

@MainActor
public final class AppEnvironment: AutomationHost {
    public let model: AppModel
    public let router: AppRouter
    public let notifications: NotificationCoordinator
    public let badge: DockBadgeController
    let dock: DockControlling
    let loginItem: LoginItemControlling
    private(set) var windowController: MainWindowController?
    private(set) var launched = false
    private var channelObserver: ValueObserver<String?>?
    lazy var automation = DebugAutomation(router: router, host: self)

    public init(
        model: AppModel,
        center: NotificationPosting,
        dock: DockControlling,
        loginItem: LoginItemControlling,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.model = model
        self.dock = dock
        self.loginItem = loginItem
        router = AppRouter(model: model)
        notifications = NotificationCoordinator(model: model, router: router, center: center, dock: dock)
        badge = DockBadgeController(model: model) { [weak dock] label in dock?.badgeLabel = label }
        router.openExternalURL = openURL
        router.showMainWindow = { [weak self] in self?.showMainWindow() }
    }

    public static func credentialStore(defaults: UserDefaults = .standard) -> CredentialStore {
        defaults.bool(forKey: DebugCommand.defaultsKey) ? FileCredentialStore(fileURL: FileCredentialStore.defaultURL()) : KeychainCredentialStore()
    }

    public static func live() -> AppEnvironment {
        let model = AppModel(store: FileAppStateStore(fileURL: FileAppStateStore.defaultURL()), credentials: credentialStore())
        let center: NotificationPosting = SystemNotificationCenter.isAvailable ? SystemNotificationCenter() : SilentNotificationCenter()
        return AppEnvironment(model: model, center: center, dock: AppKitDock(), loginItem: SystemLoginItem())
    }

    public var mainWindow: NSWindow? { windowController?.window }

    public func launch(startSessions: Bool = true) {
        guard !launched else { return }
        launched = true
        let dock = self.dock
        model.isAppActive = { dock.isAppActive }
        notifications.install()
        if UserDefaults.standard.bool(forKey: DebugCommand.defaultsKey) {
            notifications.onDeliver = { DebugAutomation.appendToLog("notification \($0.channelId) \($0.title): \($0.body)") }
            automation.probe.start(model: model)
        }
        badge.start()
        let model = self.model
        let notifications = self.notifications
        let observer = ValueObserver(read: { model.selectedSession?.currentChannelId }) { channelId in
            guard let channelId else { return }
            Task { await notifications.channelViewed(channelId) }
        }
        observer.start()
        channelObserver = observer
        syncLoginItem()
        showMainWindow()
        if startSessions { Task { await model.startAll() } }
    }

    public func showMainWindow() {
        if windowController == nil {
            let controller = MainWindowController(rootView: AppRootView(model: model, router: router))
            controller.onBecomeKey = { [weak self] in self?.mainWindowDidBecomeKey() }
            windowController = controller
        }
        windowController?.present()
    }

    public func appDidBecomeActive() {
        guard launched else { return }
        let model = self.model
        Task {
            await model.markSelectedChannelViewed()
            await model.refreshSelectedPresence()
            await model.refreshSelectedReadStatus()
        }
    }

    public func appDidResignActive() {
        model.appDidResignActive()
    }

    func mainWindowDidBecomeKey() {
        guard launched else { return }
        let model = self.model
        Task { await model.refreshSelectedReadStatus() }
    }

    public func handle(url: URL) async {
        if DebugCommand.isDebugURL(url) {
            await automation.handle(url)
            return
        }
        await router.open(url: url)
    }

    public func shutdown() {
        model.stopAll()
    }

    public func deliverTestNotification(title: String, body: String) async {
        guard let session = model.selectedSession, let channelId = session.currentChannelId else { return }
        let notification = MentionNotification(
            serverId: session.serverId,
            teamId: session.currentTeamId ?? "",
            channelId: channelId,
            postId: UUID().uuidString,
            rootId: "",
            title: title,
            body: body
        )
        await notifications.deliver(notification)
    }

    public func terminate() {
        NSApp.terminate(nil)
    }

    public func activateNotification(_ route: NotificationRoute) async {
        await notifications.activate(route)
    }

    func syncLoginItem() {
        let enabled = loginItem.isEnabled
        if model.settings.launchAtLogin != enabled { model.settings.launchAtLogin = enabled }
    }
}
