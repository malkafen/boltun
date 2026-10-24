import Foundation
import SwiftUI

public struct AppInfo: Equatable, Sendable {
    public static let repositoryURL = URL(string: "https://github.com/malkafen/boltun")!
    public static let issuesURL = URL(string: "https://github.com/malkafen/boltun/issues/new")!
    public static let mattermostURL = URL(string: "https://mattermost.com")!

    public var name: String
    public var shortVersion: String
    public var fullVersion: String
    public var build: String

    public init(name: String = "Boltun", shortVersion: String, fullVersion: String, build: String) {
        self.name = name
        self.shortVersion = shortVersion
        self.fullVersion = fullVersion
        self.build = build
    }

    public init(infoDictionary: [String: Any]?) {
        let info = infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        self.init(
            name: info["CFBundleName"] as? String ?? "Boltun",
            shortVersion: short,
            fullVersion: info["BoltunFullVersion"] as? String ?? short,
            build: info["CFBundleVersion"] as? String ?? "0"
        )
    }

    public static var current: AppInfo { AppInfo(infoDictionary: Bundle.main.infoDictionary) }

    public var versionDescription: String {
        let detail = fullVersion == shortVersion ? "build \(build)" : "\(fullVersion), build \(build)"
        return "Version \(shortVersion) (\(detail))"
    }
}

extension EnvironmentValues {
    @Entry public var fontScale: Double = 1.0
    @Entry public var spellChecking: Bool = true
    @Entry public var appRouter: AppRouter? = nil
}
