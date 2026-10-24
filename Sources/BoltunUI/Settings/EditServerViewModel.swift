import BoltunKit
import Foundation
import Observation

@MainActor
@Observable
public final class EditServerViewModel {
    public var name: String
    public var urlText: String
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    public let server: ServerConfig
    let model: AppModel

    public init(model: AppModel, server: ServerConfig) {
        self.model = model
        self.server = server
        name = server.name
        urlText = server.url.absoluteString
    }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var urlChanged: Bool {
        (try? APIClient.normalize(urlText)) != server.url
    }

    public var canSave: Bool {
        !isSaving && !trimmedName.isEmpty && !urlText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @discardableResult
    public func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        var updated = server
        updated.name = trimmedName
        if urlChanged {
            do {
                let url = try await model.validate(url: urlText).0
                if model.servers.contains(where: { $0.id != server.id && $0.url == url }) {
                    errorMessage = "Another server already uses this URL."
                    return false
                }
                updated.url = url
            } catch {
                errorMessage = AddServerViewModel.describe(error)
                return false
            }
        }
        model.updateServer(updated)
        return true
    }
}
