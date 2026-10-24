import BoltunKit
import BoltunMarkup
import SwiftUI
import UniformTypeIdentifiers

struct ChannelView: View {
    let workspace: Workspace
    @State private var dropTargeted = false

    var body: some View {
        let session = workspace.session
        VStack(spacing: 0) {
            if let channel = session.currentChannel {
                ChannelHeader(workspace: workspace, channel: channel)
                ConnectionBanners(workspace: workspace)
                MessageListView(workspace: workspace, channelId: channel.id)
                    .id(channel.id)
                LiveTypingIndicator(session: session, channelId: channel.id)
                if channel.isArchived {
                    Text("You are viewing an archived channel. New messages cannot be posted.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                } else {
                    ComposerView(
                        state: workspace.composer(for: ComposerTarget(channelId: channel.id)),
                        workspace: workspace,
                        placeholder: "Write to \(session.displayName(channel: channel))"
                    )
                    .id(channel.id)
                }
            } else {
                ConnectionBanners(workspace: workspace)
                EmptyChannelView(workspace: workspace)
            }
        }
        .background(Theme.content)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let channelId = session.currentChannelId else { return false }
            let composer = workspace.composer(for: ComposerTarget(channelId: channelId))
            FileDrop.load(providers) { urls in composer.attach(fileURLs: urls) }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(Theme.accent.opacity(0.08))
                    .overlay(Label("Drop files to upload", systemImage: "arrow.up.doc").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }
}

enum FileDrop {
    @MainActor
    static func load(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in completion([url]) }
            }
        }
    }
}

struct EmptyChannelView: View {
    let workspace: Workspace

    var body: some View {
        let session = workspace.session
        VStack(spacing: 10) {
            if session.connection == .connecting || (session.connection == .connected && session.currentTeamId != nil) {
                ProgressView().controlSize(.regular)
                Text("Loading…").foregroundStyle(Theme.textSecondary)
            } else if session.teams.isEmpty && session.connection == .connected {
                Image(systemName: "person.3").font(.system(size: 34)).foregroundStyle(Theme.textSecondary)
                Text("You are not a member of any team on this server.").foregroundStyle(Theme.textSecondary)
            } else {
                Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 34)).foregroundStyle(Theme.textSecondary)
                Text("Select a channel to start messaging").foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ChannelHeader: View {
    let workspace: Workspace
    let channel: Channel
    @State private var search = ""

    var body: some View {
        let session = workspace.session
        let favorite = session.isFavorite(channelId: channel.id)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    ChannelGlyph(channel: channel, session: session, size: 13)
                    Text(session.displayName(channel: channel))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Button {
                        Task { await session.setFavorite(channelId: channel.id, favorite: !favorite) }
                    } label: {
                        Image(systemName: favorite ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundStyle(favorite ? Theme.away : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(favorite ? "Remove from Favorites" : "Add to Favorites")
                    if let count = workspace.memberCounts[channel.id] {
                        Label("\(count)", systemImage: "person")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .help("\(count) members")
                    }
                }
                let subtitle = ChannelHeader.subtitle(for: channel)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(subtitle)
                }
            }
            Spacer(minLength: 12)
            SearchField(text: Binding(get: { workspace.searchQuery }, set: { workspace.searchQuery = $0 })) {
                Task { await workspace.search() }
            }
            .frame(width: 230)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
        .task(id: channel.id) { await workspace.loadMemberCount(channelId: channel.id) }
    }

    static func subtitle(for channel: Channel) -> String {
        let header = MessageRenderer.plainText(channel.header).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if !header.isEmpty { return header }
        return channel.purpose.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder = "Search"
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.separator))
    }
}

struct ChannelGlyph: View {
    let channel: Channel
    let session: ServerSession
    var size: CGFloat = 13

    var body: some View {
        switch channel.type {
        case .open:
            Image(systemName: channel.isArchived ? "archivebox" : "globe").font(.system(size: size)).foregroundStyle(Theme.textSecondary)
        case .private:
            Image(systemName: channel.isArchived ? "archivebox" : "lock.fill").font(.system(size: size)).foregroundStyle(Theme.textSecondary)
        case .group:
            Image(systemName: "person.2.fill").font(.system(size: size)).foregroundStyle(Theme.textSecondary)
        case .direct:
            if let partner = channel.directPartnerId(me: session.myId) {
                StatusDot(status: session.statuses[partner] ?? .offline, size: size - 1)
            }
        }
    }
}

struct ConnectionBanners: View {
    let workspace: Workspace

    var body: some View {
        let session = workspace.session
        VStack(spacing: 0) {
            switch session.connection {
            case .reconnecting:
                Banner(style: .warning, text: "Connection lost. Reconnecting…")
            case .failed(let message):
                Banner(style: .error, text: "Cannot connect to server: \(message)", actionTitle: "Retry") {
                    Task { await session.start() }
                }
            default:
                EmptyView()
            }
            if let error = workspace.visibleError {
                Banner(style: .error, text: error, onDismiss: { workspace.dismissError() })
            }
        }
    }
}

struct LiveTypingIndicator: View {
    let session: ServerSession
    let channelId: String
    var parentId = ""

    var body: some View {
        if session.typing[parentId.isEmpty ? channelId : "\(channelId):\(parentId)"]?.isEmpty ?? true {
            TypingIndicator(names: [])
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                TypingIndicator(names: session.typingUsers(channelId: channelId, parentId: parentId))
            }
        }
    }
}

struct TypingIndicator: View {
    let names: [String]

    var body: some View {
        Text(TypingText.text(for: names) ?? " ")
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .frame(height: 18)
    }
}
