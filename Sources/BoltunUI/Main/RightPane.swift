import BoltunKit
import BoltunMarkup
import SwiftUI

struct RightPaneView: View {
    let workspace: Workspace

    var body: some View {
        Group {
            switch workspace.rightPane {
            case .thread(let rootId): ThreadPane(workspace: workspace, rootId: rootId)
            case .search: SearchPane(workspace: workspace)
            case .members: ChannelMembersPane(workspace: workspace)
            case .channelFiles(let channelId): ChannelFilesPane(workspace: workspace, channelId: channelId)
            case nil: EmptyView()
            }
        }
        .background(Theme.content)
    }
}

struct PaneHeader<Accessory: View>: View {
    let title: String
    var subtitle: String = ""
    let accessory: Accessory
    let onClose: () -> Void

    init(title: String, subtitle: String = "", onClose: @escaping () -> Void, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).scaledFont(15, weight: .bold).foregroundStyle(Theme.textPrimary)
            if !subtitle.isEmpty {
                Text(subtitle).scaledFont(12).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            accessory
            IconButton(systemName: "xmark", help: "Close", action: onClose)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
    }
}

extension PaneHeader where Accessory == EmptyView {
    init(title: String, subtitle: String = "", onClose: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, onClose: onClose) { EmptyView() }
    }
}

struct ThreadPane: View {
    let workspace: Workspace
    let rootId: String

    var body: some View {
        let session = workspace.session
        let items = workspace.threadItems(rootId: rootId)
        let root = session.posts[rootId]
        let channelName = root.flatMap { session.channels[$0.channelId] }.map { session.displayName(channel: $0) } ?? ""
        VStack(spacing: 0) {
            PaneHeader(title: "Thread", subtitle: channelName, onClose: { workspace.closeRightPane() }) {
                if let following = workspace.threadFollowing {
                    ThreadFollowButton(following: following) {
                        Task { await workspace.setFollowing(threadId: rootId, !following) }
                    }
                }
            }
            if items.isEmpty && session.threads[rootId]?.isLoading == true {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if root == nil && items.isEmpty {
                Text("This message is no longer available.")
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(items) { item in
                                TimelineItemView(item: item, workspace: workspace, inThread: true, highlightedPostId: workspace.highlightedPostId)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .defaultScrollAnchor(.top, for: .alignment)
                    .defaultScrollAnchor(.bottom, for: .initialOffset)
                    .defaultScrollAnchor(.bottom, for: .sizeChanges)
                    .onChange(of: ThreadScrollTarget.target(highlighted: workspace.highlightedPostId, items: items), initial: true) { _, target in
                        guard let target else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .center) }
                    }
                }
            }
            if let root {
                LiveTypingIndicator(session: session, channelId: root.channelId, parentId: rootId)
                ComposerView(state: workspace.composer(for: ComposerTarget(channelId: root.channelId, rootId: rootId)), workspace: workspace, placeholder: "Reply…")
                    .id(rootId)
            }
        }
    }
}

enum ThreadScrollTarget {
    static func target(highlighted: String?, items: [TimelineItem]) -> String? {
        guard let highlighted, items.contains(where: { $0.id == highlighted }) else { return nil }
        return highlighted
    }
}

struct SearchPane: View {
    let workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Search Results", subtitle: workspace.searchQuery) { workspace.closeRightPane() }
            if workspace.isSearching {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if workspace.searchResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").scaledFont(28).foregroundStyle(Theme.textSecondary)
                    Text("No results for “\(workspace.searchQuery)”").foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(workspace.searchResults) { post in
                            SearchResultRow(workspace: workspace, post: post)
                        }
                    }
                }
            }
        }
    }
}

struct SearchResultRow: View {
    let workspace: Workspace
    let post: Post
    @State private var hovering = false

    var body: some View {
        let session = workspace.session
        let channel = session.channels[post.channelId]
        let blocks = workspace.renderCache.blocks(for: post, context: workspace.markupContext())
        let request = workspace.profileRequest(for: post)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let channel { ChannelGlyph(channel: channel, session: session, size: 10) }
                Text(channel.map { session.displayName(channel: $0) } ?? "Unknown channel")
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(TimeFormatting.short(post.createAt.mattermostDate, now: workspace.now(), calendar: workspace.calendar))
                    .scaledFont(11)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(alignment: .top, spacing: 8) {
                profileTrigger(.avatar, request: request) {
                    Avatar(url: session.client.profileImageURL(userId: post.userId, lastPictureUpdate: session.users[post.userId]?.lastPictureUpdate ?? 0), client: session.client, name: session.displayName(for: post), size: 28, status: post.overrideUsername == nil ? session.statuses[post.userId] : nil, statusRing: hovering ? Theme.hover : Theme.content)
                }
                VStack(alignment: .leading, spacing: 2) {
                    profileTrigger(.name, request: request) {
                        Text(session.displayName(for: post)).scaledFont(13, weight: .semibold).foregroundStyle(Theme.textPrimary)
                    }
                    MessageBody(blocks: blocks, client: session.client)
                        .lineLimit(6)
                        .mentionProfiles(workspace: workspace, anchor: ProfileAnchor(surface: .search, kind: .mention, id: post.id), channelId: post.channelId)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Theme.hover : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { Task { await workspace.jump(to: post) } }
        .onHover { hovering = $0 }
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    func profileTrigger<Label: View>(_ kind: ProfileAnchor.Kind, request: ProfilePopoverRequest?, @ViewBuilder label: @escaping () -> Label) -> some View {
        if let request {
            ProfilePopoverTrigger(workspace: workspace, anchor: ProfileAnchor(surface: .search, kind: kind, id: post.id), request: request, arrowEdge: .leading, label: label)
        } else {
            label()
        }
    }
}

struct QuickSwitcherView: View {
    @Bindable var workspace: Workspace
    @State private var selection = 0
    @FocusState private var focused: Bool

    var body: some View {
        let results = QuickSwitcher.results(workspace.quickSwitchItems(), query: workspace.quickSwitcherQuery)
        ZStack(alignment: .top) {
            Theme.overlayDim
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Find channels and direct messages", text: $workspace.quickSwitcherQuery)
                        .textFieldStyle(.plain)
                        .scaledFont(16)
                        .focused($focused)
                        .onSubmit { choose(results) }
                        .onKeyPress(.downArrow) { move(1, count: results.count); return .handled }
                        .onKeyPress(.upArrow) { move(-1, count: results.count); return .handled }
                        .onKeyPress(.escape) { close(); return .handled }
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                Rectangle().fill(Theme.separator).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                QuickSwitchRow(item: item, selected: index == selection)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selection = index; choose(results) }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: selection) { _, index in
                        if results.indices.contains(index) { proxy.scrollTo(results[index].id) }
                    }
                }
                if results.isEmpty {
                    Text("No matches").foregroundStyle(Theme.textSecondary).padding(18)
                }
                HStack(spacing: 14) {
                    Text("↑↓ to navigate")
                    Text("↵ to select")
                    Text("esc to dismiss")
                }
                .scaledFont(11)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.03))
            }
            .frame(width: 560)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.popover))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
            .padding(.top, 90)
        }
        .onAppear { focused = true }
        .onChange(of: workspace.quickSwitcherQuery) { selection = 0 }
    }

    func move(_ delta: Int, count: Int) {
        selection = QuickSwitcher.moveSelection(selection, by: delta, count: count)
    }

    func choose(_ results: [QuickSwitchItem]) {
        guard results.indices.contains(selection) else { return }
        let id = results[selection].channelId
        close()
        Task { await workspace.select(channelId: id) }
    }

    func close() {
        workspace.showQuickSwitcher = false
    }
}

struct QuickSwitchRow: View {
    let item: QuickSwitchItem
    let selected: Bool

    var icon: String {
        switch item.kind {
        case .open: return "globe"
        case .private: return "lock.fill"
        case .direct: return "person.fill"
        case .group: return "person.2.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).scaledFont(12).foregroundStyle(Theme.textSecondary).frame(width: 18)
            Text(item.title)
                .scaledFont(14, weight: item.unread ? .semibold : .regular)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if !item.subtitle.isEmpty {
                Text(item.subtitle).scaledFont(12).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            if item.mentions > 0 { CountBadge(count: item.mentions) }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 34)
        .background(selected ? Theme.accent.opacity(0.28) : .clear)
    }
}
