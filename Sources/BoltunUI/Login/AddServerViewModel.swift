import BoltunKit
import Foundation
import Observation

@MainActor
@Observable
public final class AddServerViewModel {
    public enum State: Equatable {
        case idle
        case validating
        case failed(String)
        case validated(URL, ClientConfig)
    }

    public var urlText = "" {
        didSet { if urlText != oldValue, state != .validating { state = .idle } }
    }
    public var name = ""
    public private(set) var state: State = .idle

    let model: AppModel

    public init(model: AppModel, urlText: String = "", name: String = "") {
        self.model = model
        self.urlText = urlText
        self.name = name
    }

    public var isValidating: Bool { state == .validating }

    public var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    public var siteName: String? {
        if case .validated(_, let config) = state { return config.siteName }
        return nil
    }

    public var namePlaceholder: String {
        siteName ?? (try? APIClient.normalize(urlText))?.host() ?? "Server name"
    }

    public var canSubmit: Bool {
        !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isValidating
    }

    public var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let host = (try? APIClient.normalize(urlText))?.host() ?? urlText
        guard let siteName, !model.servers.contains(where: { $0.name == siteName }) else { return host }
        return siteName
    }

    @discardableResult
    public func validate() async -> Bool {
        guard canSubmit else { return false }
        state = .validating
        do {
            let (url, config) = try await model.validate(url: urlText)
            state = .validated(url, config)
            return true
        } catch {
            state = .failed(Self.describe(error))
            return false
        }
    }

    public func submit() async -> ServerConfig? {
        guard await validate(), case .validated(let url, _) = state else { return nil }
        return model.addServer(name: resolvedName, url: url)
    }

    static func describe(_ error: Error) -> String {
        switch APIError.wrap(error) {
        case .invalidURL:
            return "Enter a valid server URL, for example https://chat.example.com."
        case .server(let status, _) where status == 404:
            return "No Mattermost server was found at this address."
        case .server(_, nil):
            return "No Mattermost server was found at this address."
        case .decoding, .invalidResponse:
            return "This address does not look like a Mattermost server."
        case let other:
            return other.localizedDescription
        }
    }
}
