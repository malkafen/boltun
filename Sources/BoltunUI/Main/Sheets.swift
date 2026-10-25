import BoltunKit
import SwiftUI

struct BrowseChannelsSheet: View {
    let workspace: Workspace
    @State private var channels: [Channel] = []
    @State private var loading = true
    @State private var filter = ""
    @Environment(\.dismiss) private var dismiss

    static func filtered(_ channels: [Channel], query: String) -> [Channel] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let sorted = channels.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        guard !trimmed.isEmpty else { return sorted }
        return sorted.filter { $0.displayName.lowercased().contains(trimmed) || $0.name.contains(trimmed) || $0.purpose.lowercased().contains(trimmed) }
    }

    var body: some View {
        let session = workspace.session
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Browse Channels").scaledFont(17, weight: .bold)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            SearchField(text: $filter, placeholder: "Search channels") {}
            if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else {
                List(Self.filtered(channels, query: filter)) { channel in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "globe").foregroundStyle(Theme.textSecondary).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.displayName).scaledFont(13.5, weight: .semibold)
                            if !channel.purpose.isEmpty {
                                Text(channel.purpose).scaledFont(12).foregroundStyle(Theme.textSecondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        let joined = session.members[channel.id] != nil
                        Button(joined ? "View" : "Join") {
                            dismiss()
                            Task {
                                if joined { await workspace.select(channelId: channel.id) } else { await session.join(channel: channel) }
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
                .scrollContentBackground(.hidden)
                .frame(minHeight: 320)
            }
        }
        .padding(18)
        .frame(width: 520, height: 480)
        .background(Theme.content)
        .task {
            channels = await session.browsePublicChannels()
            loading = false
        }
    }
}

struct DirectMessageSheet: View {
    let workspace: Workspace
    @State private var query = ""
    @State private var users: [User] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let session = workspace.session
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Direct Messages").scaledFont(17, weight: .bold)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            SearchField(text: $query, placeholder: "Search people") {}
            List(users) { user in
                Button {
                    dismiss()
                    Task { await session.openDirect(userId: user.id) }
                } label: {
                    HStack(spacing: 10) {
                        Avatar(url: session.client.profileImageURL(userId: user.id, lastPictureUpdate: user.lastPictureUpdate), client: session.client, name: user.username, size: 28, status: session.statuses[user.id])
                        VStack(alignment: .leading, spacing: 1) {
                            Text("@\(user.username)").scaledFont(13.5, weight: .semibold)
                            if !user.fullName.isEmpty {
                                Text(user.fullName).scaledFont(12).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
            .frame(minHeight: 320)
        }
        .padding(18)
        .frame(width: 460, height: 460)
        .background(Theme.content)
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(query.isEmpty ? 0 : 150))
            guard !Task.isCancelled else { return }
            let found = await session.autocompleteUsers(query, channelId: nil)
            guard !Task.isCancelled else { return }
            users = found.filter { !$0.isDeactivated && $0.id != session.myId }
        }
    }
}
