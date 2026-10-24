import AppKit
import BoltunKit
import BoltunMarkup
import SwiftUI

struct TimelineItemView: View {
    let item: TimelineItem
    let workspace: Workspace
    var inThread = false

    var body: some View {
        switch item {
        case .date(let title):
            DateSeparator(title: title)
        case .newMessages:
            NewMessagesLine()
        case .replies(let count):
            HStack(spacing: 10) {
                Text(count == 1 ? "1 reply" : "\(count) replies")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        case .post(let model):
            MessageRow(model: model, workspace: workspace, inThread: inThread)
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
                .font(.system(size: 11.5, weight: .semibold))
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
                .font(.system(size: 11, weight: .bold))
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
    @State private var hovering: Bool
    @State private var pickerShown = false

    init(model: MessageRowModel, workspace: Workspace, inThread: Bool = false, hovering: Bool = false) {
        self.model = model
        self.workspace = workspace
        self.inThread = inThread
        _hovering = State(initialValue: hovering)
    }

    nonisolated static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        MainActor.assumeIsolated {
            lhs.model == rhs.model && lhs.inThread == rhs.inThread && lhs.workspace === rhs.workspace
        }
    }

    var post: Post { model.post }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            gutter
            VStack(alignment: .leading, spacing: 3) {
                if !model.isContinuation { header }
                if let reply = model.replyContext { ReplyIndicator(context: reply) { open(thread: reply.rootId) } }
                content
                if !post.isDeleted {
                    if !post.attachments.isEmpty { AttachmentsView(attachments: post.attachments) }
                    if !post.metadata.files.isEmpty { FilesView(files: post.metadata.files, workspace: workspace) }
                    if !model.reactions.isEmpty { reactions }
                    if model.replyCount > 0 && !inThread { replyButton }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .padding(.top, model.isContinuation ? 2 : 8)
        .padding(.bottom, 2)
        .background(background)
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
        if model.mentionsMe { return hovering ? Theme.mentionRowHover : Theme.mentionRow }
        return hovering ? Theme.hover : .clear
    }

    @ViewBuilder var gutter: some View {
        if model.isSystem && !model.isContinuation {
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 36, height: 22)
        } else if model.isContinuation {
            Text(hovering ? model.timeText.replacingOccurrences(of: " AM", with: "").replacingOccurrences(of: " PM", with: "") : "")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 36, alignment: .trailing)
                .padding(.top, 3)
                .help(model.fullTimeText)
        } else {
            Avatar(url: model.avatarURL, client: workspace.session.client, name: model.authorName, size: 36)
        }
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(model.isSystem ? "System" : model.authorName)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if post.overrideUsername != nil || post.props["from_bot"]?.boolValue == true {
                Text("BOT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.1)))
            }
            Text(model.timeText)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .help(model.fullTimeText)
            if post.isPinned {
                Label("Pinned", systemImage: "pin.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.away)
            }
        }
    }

    @ViewBuilder var content: some View {
        if post.isDeleted {
            Text("(message deleted)")
                .font(Theme.messageFont().italic())
                .foregroundStyle(Theme.textSecondary)
        } else if model.isSystem {
            Text(MessageRenderer.plainText(post.message))
                .font(Theme.messageFont())
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else if !model.blocks.isEmpty || post.isEdited {
            VStack(alignment: .leading, spacing: 2) {
                MessageBody(blocks: model.blocks, client: workspace.session.client, scale: 1)
                if post.isEdited {
                    Text("Edited")
                        .font(.system(size: 10.5))
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
                    .font(.system(size: 12))
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
        Button { open(thread: post.id) } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrowshape.turn.up.left.2")
                Text(model.replyCount == 1 ? "1 reply" : "\(model.replyCount) replies")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.link)
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 13, weight: .medium))
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
        if model.isMine {
            Divider()
            Button("Delete", role: .destructive) { workspace.requestDelete(post) }
        }
    }

    func open(thread rootId: String) {
        Task { await workspace.openThread(rootId: rootId) }
    }
}

struct ReplyIndicator: View {
    let context: ReplyContext
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 9))
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
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(reaction.isMine ? Theme.link : Theme.textSecondary)
            }
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Capsule().fill(reaction.isMine ? Theme.reactionMine : Theme.reactionBackground))
            .overlay(Capsule().strokeBorder(reaction.isMine ? Theme.reactionMineBorder : Color.clear))
        }
        .buttonStyle(.plain)
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
                                Text(field.0).font(.system(size: 12, weight: .semibold))
                                Text(field.1).foregroundStyle(Theme.textPrimary.opacity(0.9))
                            }
                        }
                    }
                    .font(Theme.messageFont())
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
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text([file.extension.uppercased(), FileSizeText.text(file.size)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11))
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
                            Text(choice.glyph).font(.system(size: 21)).frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .help(":\(choice.name):")
                    }
                }
            }
            .frame(height: 200)
            if choices.isEmpty {
                Text("No emoji found").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(10)
        .frame(width: 300)
    }
}
