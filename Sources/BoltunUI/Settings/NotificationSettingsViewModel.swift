import BoltunKit
import Foundation
import Observation

@MainActor
@Observable
public final class NotificationSettingsViewModel {
    public let model: AppModel
    public var serverId: UUID? {
        didSet { if serverId != oldValue { reload() } }
    }
    public private(set) var original: AccountNotifySettings?
    public var settings = AccountNotifySettings()
    public var keywordsText = ""
    public private(set) var saving = false
    public private(set) var errorMessage: String?

    public init(model: AppModel, serverId: UUID? = nil) {
        self.model = model
        self.serverId = serverId ?? model.selectedServerId ?? model.servers.first?.id
        reload()
    }

    public var servers: [ServerConfig] { model.servers }

    public var serverName: String { servers.first { $0.id == serverId }?.name ?? "" }

    var session: ServerSession? { serverId.flatMap(model.session(for:)) }

    public var user: User? { session?.me }

    public var isAvailable: Bool { original != nil }

    public var edited: AccountNotifySettings {
        var result = settings
        result.keywords = AccountNotifySettings.parseKeywords(keywordsText)
        return result
    }

    public var hasChanges: Bool { original.map { $0 != edited } ?? false }

    public var showsThreadReplies: Bool { (session?.collapsedThreads ?? false) && settings.desktop == .mention }

    public var firstName: String { user?.firstName ?? "" }

    public var username: String { user?.username ?? "" }

    public var unavailableMessage: String {
        servers.isEmpty ? "Add a server to change its notification settings." : "Sign in to \(serverName) to change its notification settings."
    }

    public func reload() {
        original = session?.accountNotifySettings
        settings = original ?? AccountNotifySettings()
        keywordsText = settings.keywords.joined(separator: ", ")
        errorMessage = nil
    }

    public func syncIfUnchanged() {
        if !hasChanges, original != session?.accountNotifySettings { reload() }
    }

    public func revert() {
        reload()
    }

    @discardableResult
    public func save() async -> Bool {
        guard let session, !saving else { return false }
        guard hasChanges else { return true }
        saving = true
        defer { saving = false }
        let target = edited
        guard await session.applyAccountNotifySettings(target) else {
            errorMessage = session.lastError ?? "Could not save notification settings."
            return false
        }
        reload()
        return true
    }
}
