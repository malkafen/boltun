import AppKit
import SwiftUI

public struct AboutSettingsView: View {
    let info: AppInfo
    let openURL: (URL) -> Void

    public init(info: AppInfo, openURL: @escaping (URL) -> Void) {
        self.info = info
        self.openURL = openURL
    }

    public var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)
            Text(info.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(info.versionDescription)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
            Text("A native macOS client for Mattermost.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 16) {
                Button("GitHub") { openURL(AppInfo.repositoryURL) }
                Button("Report an Issue") { openURL(AppInfo.issuesURL) }
                Button("Mattermost") { openURL(AppInfo.mattermostURL) }
            }
            .buttonStyle(.link)
            Spacer()
            Text("Not affiliated with Mattermost, Inc.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
