import AppKit
import BoltunKit
import BoltunMarkup
import SwiftUI

struct TimelineItemView: View {
    let item: TimelineItem
    let workspace: Workspace
    var inThread = false
    var highlightedPostId: String?
    var onFrame: ((String, CGRect?) -> Void)?

    var body: some View {
        if let onFrame {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { [id = item.id] in onFrame(id, $0) }
                .onDisappear { [id = item.id] in onFrame(id, nil) }
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case .date(let title):
            DateSeparator(title: title)
        case .newMessages:
            NewMessagesLine()
        case .replies(let count):
            HStack(spacing: 10) {
                Text(count == 1 ? "1 reply" : "\(count) replies")
                    .scaledFont(11.5, weight: .semibold)
                    .foregroundStyle(Theme.textSecondary)
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        case .post(let model):
            MessageRow(model: model, workspace: workspace, inThread: inThread, highlighted: model.id == highlightedPostId)
                .equatable()
        }
    }
}

struct DateSeparator: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Theme.separator).frame(height: 1)
            Text(title)
                .scaledFont(11.5, weight: .semibold)
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.content))
                .overlay(Capsule().strokeBorder(Theme.separator))
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct NewMessagesLine: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Theme.newMessages).frame(height: 1)
            Text("New Messages")
                .scaledFont(11, weight: .bold)
                .foregroundStyle(Theme.newMessages)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

struct MessageRow: View, Equatable {
    let model: MessageRowModel
    let workspace: Workspace
    var inThread = false
    var highlighted = false
    @State private var hovering: Bool
    @State private var pickerShown = false
    @Environment(\.fontScale) private var fontScale

    init(model: MessageRowModel, workspace: Workspace, inThread: Bool = false, highlighted: Bool = false, hovering: Bool = false) {
        self.model = model
        self.workspace = workspace
        self.inThread = inThread
        self.highlighted = highlighted
        _hovering = State(initialValue: hovering)
    }

    nonisolated static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        MainActor.assumeIsolated {
            lhs.model == rhs.model && lhs.inThread == rhs.inThread && lhs.highlighted == rhs.highlighted && lhs.workspace === rhs.workspace
        }
    }

    var post: Post { model.post }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            gutter
            VStack(alignment: .leading, spacing: 3) {
                if !model.isContinuation { header }
                if let reply = model.replyContext { ReplyIndicator(context: reply) { open(thread: reply.rootId) } }
                if let burn = model.burnOnRead, burn.showsPlaceholder {
                    BurnOnReadPlaceholder(model: burn) { Task { await workspace.revealBurnOnRead(postId: burn.postId) } }
                } else {
                    content
                }
                if !post.isDeleted {
                    if !post.attachments.isEmpty { AttachmentsView(attachments: post.attachments) }
                    if !post.metadata.files.isEmpty { FilesView(files: post.metadata.files, workspace: workspace) }
                    if let acknowledgement = model.acknowledgement {
                        AcknowledgementButton(model: acknowledgement, client: workspace.session.client) {
                            Task { await workspace.toggleAcknowledgement(postId: acknowledgement.postId) }
                        }
                    }
                    if !model.reactions.isEmpty { reactions }
                    if !inThread {
                        if let thread = model.thread {
                            ThreadSummaryButton(summary: thread, client: workspace.session.client, following: model.following, onToggleFollow: toggleFollow) {
                                open(thread: post.id)
                            }
                        } else if model.replyCount > 0 {
                            replyButton
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if model.isContinuation, let readStatus = model.readStatus {
                ReadStatusIndicator(model: readStatus).padding(.top, 4)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .padding(.top, model.isContinuation ? 2 : 8)
        .padding(.bottom, 2)
        .background(background.animation(.easeOut(duration: 0.35), value: highlighted))
        .overlay(alignment: .leading) {
            if model.mentionsMe { Rectangle().fill(Theme.mentionRowBar).frame(width: 2) }
        }
        .overlay(alignment: .topTrailing) {
            if (hovering || pickerShown) && !post.isDeleted && !model.isSystem {
                actionBar.offset(x: -16, y: model.isContinuation ? -14 : -8)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
    }

    var background: Color {
        if highlighted { return Theme.postHighlight }
        if model.mentionsMe { return hovering ? Theme.mentionRowHover : Theme.mentionRow }
        return hovering ? Theme.hover : .clear
    }

    @ViewBuilder var gutter: some View {
        if model.isSystem && !model.isContinuation {
            Image(systemName: "info.circle")
                .scaledFont(18)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 36, height: 22)
        } else if model.isContinuation {
            Text(model.timeText.replacingOccurrences(of: " AM", with: "").replacingOccurrences(of: " PM", with: ""))
                .scaledFont(10)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 36, alignment: .trailing)
                .padding(.top, 3)
                .opacity(hovering ? 1 : 0)
                .help(model.fullTimeText)
        } else {
            profileTrigger(.avatar) {
                Avatar(url: model.avatarURL, client: workspace.session.client, name: model.authorName, size: 36, status: model.authorStatus, statusRing: Theme.content)
            }
        }
    }

    var profileSurface: ProfileAnchor.Surface { inThread ? .thread : .channel }

    @ViewBuilder
    func profileTrigger<Label: View>(_ kind: ProfileAnchor.Kind, @ViewBuilder label: @escaping () -> Label) -> some View {
        if !model.isSystem, let request = workspace.profileRequest(for: post) {
            ProfilePopoverTrigger(workspace: workspace, anchor: ProfileAnchor(surface: profileSurface, kind: kind, id: post.id), request: request, label: label)
        } else {
            label()
        }
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            profileTrigger(.name) {
                Text(model.isSystem ? "System" : model.authorName)
                    .scaledFont(13.5, weight: .semibold)
                    .foregroundStyle(Theme.textPrimary)
            }
            if post.overrideUsername != nil || post.props["from_bot"]?.boolValue == true {
                Text("BOT")
                    .scaledFont(9, weight: .bold)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.1)))
            }
            Text(model.timeText)
                .scaledFont(11.5)
                .foregroundStyle(Theme.textSecondary)
                .help(model.fullTimeText)
            if let readStatus = model.readStatus { ReadStatusIndicator(model: readStatus) }
            PostPriorityBadge(level: model.priority)
            if let burn = model.burnOnRead {
                if burn.showsTimer {
                    BurnOnReadTimerChip(model: burn, now: workspace.now) { workspace.pendingBurn = post }
                } else if burn.showsBadge {
                    BurnOnReadBadge(model: burn) { workspace.burnOnReadActivated(burn) }
                }
            }
            if post.isPinned {
                Label("Pinned", systemImage: "pin.fill")
                    .labelStyle(.titleAndIcon)
                    .scaledFont(10.5, weight: .medium)
                    .foregroundStyle(Theme.away)
            }
        }
    }

    @ViewBuilder var content: some View {
        if post.isDeleted {
            Text("(message deleted)")
                .font(Theme.messageFont(scale: fontScale).italic())
                .foregroundStyle(Theme.textSecondary)
        } else if model.isSystem {
            Text(MessageRenderer.plainText(post.message))
                .font(Theme.messageFont(scale: fontScale))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else if !model.blocks.isEmpty || post.isEdited {
            VStack(alignment: .leading, spacing: 2) {
                MessageBody(blocks: model.blocks, client: workspace.session.client)
                    .mentionProfiles(workspace: workspace, anchor: ProfileAnchor(surface: profileSurface, kind: .mention, id: post.id), channelId: post.channelId)
                if post.isEdited {
                    Text("Edited")
                        .scaledFont(10.5)
                        .foregroundStyle(Theme.textSecondary)
                        .help("Edited \(TimeFormatting.full(post.editAt.mattermostDate, calendar: workspace.calendar))")
                }
            }
        }
    }

    var reactions: some View {
        FlowLayout(spacing: 4) {
            ForEach(model.reactions) { reaction in
                ReactionChip(reaction: reaction, client: workspace.session.client) {
                    Task { await workspace.toggleReaction(postId: post.id, emojiName: reaction.emojiName) }
                }
            }
            Button { pickerShown = true } label: {
                Image(systemName: "face.smiling")
                    .scaledFont(12)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 22)
                    .background(Capsule().fill(Theme.reactionBackground))
            }
            .buttonStyle(.plain)
            .help("Add reaction")
        }
        .padding(.top, 3)
    }

    var replyButton: some View {
        HoverLinkButton(action: { open(thread: post.id) }) {
            HStack(spacing: 4) {
                Image(systemName: "arrowshape.turn.up.left.2")
                Text(model.replyCount == 1 ? "1 reply" : "\(model.replyCount) replies")
            }
            .scaledFont(12, weight: .semibold)
            .foregroundStyle(Theme.link)
        }
        .help("Open thread")
        .padding(.top, 2)
    }

    var actionBar: some View {
        HStack(spacing: 0) {
            IconButton(systemName: "face.smiling", help: "Add reaction") { pickerShown = true }
                .popover(isPresented: $pickerShown, arrowEdge: .bottom) {
                    EmojiPicker(workspace: workspace) { name in
                        pickerShown = false
                        Task { await workspace.toggleReaction(postId: post.id, emojiName: name) }
                    }
                }
            if !inThread || !post.isReply {
                IconButton(systemName: "arrowshape.turn.up.left", help: "Reply") { Task { await workspace.reply(to: post) } }
            }
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .scaledFont(13, weight: .medium)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28, height: 28)
            .help("More actions")
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.popover))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    @ViewBuilder var menuItems: some View {
        Button("Reply") { Task { await workspace.reply(to: post) } }
        if model.isMine && !model.isSystem {
            Button("Edit") { workspace.beginEdit(post) }
        }
        Button("Copy Text") { workspace.copyText(post) }
        Button("Copy Link") { workspace.copyLink(post) }
        Button(post.isPinned ? "Unpin from Channel" : "Pin to Channel") { Task { await workspace.togglePin(post) } }
        if let following = model.following {
            Button(following ? "Unfollow Thread" : "Follow Thread", action: toggleFollow)
        }
        if model.isMine {
            Divider()
            Button("Delete", role: .destructive) { workspace.requestDelete(post) }
        }
    }

    func open(thread rootId: String) {
        Task { await workspace.openThread(rootId: rootId) }
    }

    func toggleFollow() {
        guard let following = model.following else { return }
        Task { await workspace.setFollowing(threadId: post.id, !following) }
    }
}

struct ThreadSummaryButton: View {
    let summary: ThreadSummary
    let client: APIClient?
    var following: Bool?
    var onToggleFollow: () -> Void = {}
    let action: () -> Void
    @State private var hovering: Bool

    init(summary: ThreadSummary, client: APIClient?, following: Bool? = nil, onToggleFollow: @escaping () -> Void = {}, hovering: Bool = false, action: @escaping () -> Void) {
        self.summary = summary
        self.client = client
        self.following = following
        self.onToggleFollow = onToggleFollow
        self.action = action
        _hovering = State(initialValue: hovering)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: action) {
                HStack(spacing: 4) {
                    participants
                    Text(summary.replyText)
                        .scaledFont(12.5, weight: .semibold)
                        .foregroundStyle(Theme.link)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Theme.linkHover : .clear))
                    if !summary.lastReplyText.isEmpty {
                        Text(summary.lastReplyText)
                            .scaledFont(11.5)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    if summary.hasNewReplies {
                        Circle().fill(Theme.link).frame(width: 7, height: 7).padding(.leading, 2).help("New replies")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .pointerStyle(.link)
            .onHover { hovering = $0 }
            .help("Open thread")
            if let following {
                ThreadFollowButton(following: following, action: onToggleFollow)
            }
        }
        .padding(.top, 2)
    }

    var participants: some View {
        HStack(spacing: -6) {
            ForEach(summary.participants) { participant in
                Avatar(url: participant.avatarURL, client: client, name: participant.name, size: 20)
                    .overlay(Circle().strokeBorder(Theme.content, lineWidth: 1.5))
                    .help(participant.name)
            }
        }
        .padding(.trailing, 4)
    }
}

struct ThreadFollowButton: View {
    let following: Bool
    let action: () -> Void
    @State private var hovering: Bool

    init(following: Bool, hovering: Bool = false, action: @escaping () -> Void) {
        self.following = following
        self.action = action
        _hovering = State(initialValue: hovering)
    }

    var title: String {
        guard following else { return "Follow" }
        return hovering ? "Unfollow" : "Following"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: following ? (hovering ? "bell.slash" : "bell.fill") : "bell")
                Text(title)
            }
            .scaledFont(11.5, weight: .semibold)
            .foregroundStyle(following && !hovering ? Theme.link : (hovering ? Theme.textPrimary : Theme.textSecondary))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(hovering ? Color.white.opacity(0.08) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .help(following ? "Stop following this thread" : "Follow this thread to get notified about new replies")
        .accessibilityLabel(following ? "Unfollow thread" : "Follow thread")
    }
}

struct HoverLinkButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Theme.linkHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .padding(.leading, -5)
    }
}

struct ReplyIndicator: View {
    let context: ReplyContext
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrowshape.turn.up.left.fill").scaledFont(9)
                Group {
                    if context.authorName.isEmpty {
                        Text("Replied in thread")
                    } else {
                        Text("Replied to \(context.authorName): ").fontWeight(.semibold) + Text(context.snippet)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .scaledFont(12)
            .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("Open thread")
    }
}

struct ReactionChip: View {
    let reaction: ReactionChipModel
    let client: APIClient?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                EmojiGlyphView(name: reaction.emojiName, glyph: reaction.glyph, customEmojiId: reaction.customEmojiId, client: client, size: 14)
                Text("\(reaction.count)")
                    .scaledFont(11.5, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(reaction.isMine ? Theme.link : Theme.textSecondary)
            }
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(Capsule().fill(reaction.isMine ? Theme.reactionMine : Theme.reactionBackground))
            .overlay(Capsule().strokeBorder(reaction.isMine ? Theme.reactionMineBorder : Color.clear))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(ReactionTooltip.text(names: reaction.userNames, emojiName: reaction.emojiName))
    }
}

enum ReactionTooltip {
    static func text(names: [String], emojiName: String) -> String {
        let list: String
        switch names.count {
        case 0: list = "Nobody"
        case 1: list = names[0]
        case 2...5: list = names.dropLast().joined(separator: ", ") + " and " + names.last!
        default: list = names.prefix(5).joined(separator: ", ") + " and \(names.count - 5) others"
        }
        return "\(list) reacted with :\(emojiName):"
    }
}

struct EmojiGlyphView: View {
    let name: String
    let glyph: String?
    let customEmojiId: String?
    let client: APIClient?
    var size: CGFloat = 16

    var body: some View {
        if let glyph {
            Text(glyph).font(.system(size: size))
        } else if let customEmojiId, let client {
            RemoteImage(url: client.customEmojiImageURL(id: customEmojiId), client: client, maxPixel: 64, contentMode: .fit) {
                Text(":\(name):").font(.system(size: size * 0.7))
            }
            .frame(width: size + 2, height: size + 2)
        } else {
            Text(":\(name):")
                .font(.system(size: size * 0.72, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct AttachmentsView: View {
    let attachments: [JSONValue]
    @Environment(\.fontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                let summary = AttachmentSummary(attachment)
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5).fill(summary.color).frame(width: 3)
                    VStack(alignment: .leading, spacing: 3) {
                        if !summary.pretext.isEmpty { Text(summary.pretext).foregroundStyle(Theme.textSecondary) }
                        if !summary.title.isEmpty { Text(summary.title).fontWeight(.semibold) }
                        if !summary.text.isEmpty { Text(summary.text) }
                        ForEach(Array(summary.fields.enumerated()), id: \.offset) { _, field in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(field.0).scaledFont(12, weight: .semibold)
                                Text(field.1).foregroundStyle(Theme.textPrimary.opacity(0.9))
                            }
                        }
                    }
                    .font(Theme.messageFont(scale: fontScale))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
            }
        }
    }
}

struct AttachmentSummary {
    var pretext: String
    var title: String
    var text: String
    var fields: [(String, String)]
    var color: Color

    init(_ value: JSONValue) {
        pretext = value["pretext"]?.stringValue ?? ""
        title = value["title"]?.stringValue ?? ""
        let body = value["text"]?.stringValue ?? ""
        text = body.isEmpty ? (title.isEmpty && pretext.isEmpty ? (value["fallback"]?.stringValue ?? "") : "") : body
        fields = (value["fields"]?.arrayValue ?? []).compactMap { field in
            guard let title = field["title"]?.stringValue else { return nil }
            return (title, field["value"]?.stringValue ?? "")
        }
        color = Self.color(hex: value["color"]?.stringValue) ?? Theme.quoteBar
    }

    static func color(hex: String?) -> Color? {
        guard var hex, !hex.isEmpty else { return nil }
        switch hex {
        case "good": return Theme.online
        case "warning": return Theme.away
        case "danger": return Theme.dnd
        default: break
        }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }
}

struct FilesView: View {
    let files: [FileInfo]
    let workspace: Workspace

    var body: some View {
        let images = files.filter(\.isImage)
        let others = files.filter { !$0.isImage }
        VStack(alignment: .leading, spacing: 6) {
            if !images.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(images) { file in
                        ImageThumbnail(file: file, client: workspace.session.client) { workspace.previewFile = file }
                    }
                }
            }
            ForEach(others) { file in
                FileChip(file: file, isDownloading: workspace.downloading.contains(file.id)) {
                    Task { await workspace.download(file) }
                }
            }
        }
        .padding(.top, 3)
    }
}

enum ThumbnailSizing {
    static func size(width: Int, height: Int, maxWidth: CGFloat = 340, maxHeight: CGFloat = 240) -> CGSize {
        guard width > 0, height > 0 else { return CGSize(width: 200, height: 140) }
        let scale = min(1, maxWidth / CGFloat(width), maxHeight / CGFloat(height))
        return CGSize(width: max(48, CGFloat(width) * scale), height: max(36, CGFloat(height) * scale))
    }
}

struct ImageThumbnail: View {
    let file: FileInfo
    let client: APIClient
    let action: () -> Void

    var body: some View {
        let size = ThumbnailSizing.size(width: file.width, height: file.height)
        Button(action: action) {
            RemoteImage(url: file.hasPreviewImage ? client.filePreviewURL(id: file.id) : client.fileURL(id: file.id), client: client, maxPixel: 700, contentMode: .fill) {
                ZStack {
                    Theme.codeBackground
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.separator))
        }
        .buttonStyle(.plain)
        .help(file.name)
    }
}

struct FileChip: View {
    let file: FileInfo
    var isDownloading = false
    let action: () -> Void

    static func icon(for file: FileInfo) -> String {
        let ext = file.extension.lowercased()
        if ["zip", "gz", "tar", "rar", "7z"].contains(ext) { return "doc.zipper" }
        if ["mp4", "mov", "avi", "mkv", "webm"].contains(ext) { return "film" }
        if ["mp3", "wav", "m4a", "ogg", "flac"].contains(ext) { return "waveform" }
        if ["pdf"].contains(ext) { return "doc.richtext" }
        if ["swift", "js", "ts", "py", "go", "rs", "c", "h", "json", "yaml", "yml", "sh"].contains(ext) { return "chevron.left.forwardslash.chevron.right" }
        return "doc"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: Self.icon(for: file))
                    .scaledFont(20)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name)
                        .scaledFont(12.5, weight: .semibold)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text([file.extension.uppercased(), FileSizeText.text(file.size)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .scaledFont(11)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                if isDownloading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle").foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: 300)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
        .help("Download \(file.name)")
    }
}

struct EmojiPicker: View {
    let workspace: Workspace
    let onPick: (String) -> Void
    @State private var query = ""

    var body: some View {
        let choices = workspace.emojiChoices(query: query)
        VStack(spacing: 8) {
            TextField("Search emoji", text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 8), spacing: 4) {
                    ForEach(choices, id: \.name) { choice in
                        Button { onPick(choice.name) } label: {
                            Text(choice.glyph).scaledFont(21).frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .help(":\(choice.name):")
                    }
                }
            }
            .frame(height: 200)
            if choices.isEmpty {
                Text("No emoji found").scaledFont(12).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(10)
        .frame(width: 300)
    }
}
