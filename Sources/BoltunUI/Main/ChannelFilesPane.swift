import BoltunKit
import SwiftUI

struct ChannelFilesPane: View {
    let workspace: Workspace
    let channelId: String
    let model: ChannelFilesModel

    init(workspace: Workspace, channelId: String, model: ChannelFilesModel? = nil) {
        self.workspace = workspace
        self.channelId = channelId
        self.model = model ?? workspace.channelFiles
    }

    var body: some View {
        let session = workspace.session
        let channelName = session.channels[channelId].map { session.displayName(channel: $0) } ?? ""
        VStack(spacing: 0) {
            PaneHeader(title: "Files", subtitle: channelName) { workspace.closeRightPane() }
            ChannelFilesSearchBar(model: model)
            HStack(spacing: 8) {
                Text(model.title).scaledFont(13, weight: .semibold).foregroundStyle(Theme.textPrimary)
                Spacer()
                ChannelFilesFilterMenu(model: model)
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .frame(height: 36)
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching...").scaledFont(12).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let empty = model.emptyState {
            ChannelFilesEmptyView(state: empty)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.files, id: \.id) { file in
                        ChannelFileRow(workspace: workspace, file: file)
                            .onAppear { Task { await model.loadMoreIfNeeded(after: file) } }
                    }
                    if model.isLoadingMore {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}

struct ChannelFilesSearchBar: View {
    @Bindable var model: ChannelFilesModel

    var body: some View {
        SearchField(text: $model.searchText, placeholder: "Search files") {
            Task { await model.submitSearch() }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .onChange(of: model.searchText) { _, text in
            guard text.isEmpty, model.query.isSearch else { return }
            Task { await model.clearSearch() }
        }
    }
}

struct ChannelFilesFilterMenu: View {
    let model: ChannelFilesModel

    var body: some View {
        Menu {
            ForEach(FileTypeFilter.allCases, id: \.self) { filter in
                Toggle(filter.title, isOn: Binding(
                    get: { model.filter == filter },
                    set: { _ in Task { await model.select(filter: filter) } }
                ))
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .scaledFont(13, weight: .medium)
                .foregroundStyle(model.filter == .all ? Theme.textSecondary : Theme.link)
                .overlay(alignment: .topTrailing) {
                    if model.filter != .all {
                        Circle().fill(Theme.link).frame(width: 6, height: 6).offset(x: 3, y: -2)
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Filter")
        .accessibilityLabel("Filter")
    }
}

struct ChannelFilesEmptyView: View {
    let state: ChannelFilesEmptyState

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: state.systemImage).scaledFont(30).foregroundStyle(Theme.textSecondary)
            Text(state.title).scaledFont(15, weight: .semibold).foregroundStyle(Theme.textPrimary)
            Text(state.subtitle).scaledFont(12.5).foregroundStyle(Theme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ChannelFileRow: View {
    let workspace: Workspace
    let file: FileInfo
    @State private var hovering = false

    var body: some View {
        let row = workspace.channelFileRow(file)
        HStack(spacing: 12) {
            ChannelFileThumbnail(file: file, client: workspace.session.client)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .scaledFont(13.5, weight: .semibold)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let tag = row.channelTag { ChannelFileTag(text: tag) }
                    Text(row.details)
                        .scaledFont(12)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 4)
            if workspace.preparingPreviews.contains(file.id) || workspace.downloading.contains(file.id) {
                ProgressView().controlSize(.small)
            }
            if hovering {
                if row.hasPost { ChannelFileActionsMenu(workspace: workspace, file: file) }
                IconButton(systemName: "arrow.down.to.line", help: "Download") {
                    Task { await workspace.download(file) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Theme.hover : .clear)
        .contentShape(Rectangle())
        .onTapGesture { Task { await workspace.previewChannelFile(file) } }
        .onHover { hovering = $0 }
        .help(row.name)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct ChannelFileActionsMenu: View {
    let workspace: Workspace
    let file: FileInfo

    var body: some View {
        Menu {
            Button("Open in channel") { Task { await workspace.openInChannel(file) } }
            Button("Copy link") { workspace.copyLink(file) }
        } label: {
            Image(systemName: "ellipsis")
                .scaledFont(13, weight: .medium)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("More Actions")
    }
}

struct ChannelFileTag: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .scaledFont(9.5, weight: .semibold)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.14)))
    }
}

struct ChannelFileThumbnail: View {
    let file: FileInfo
    let client: APIClient
    var size: CGFloat = 36

    var body: some View {
        if let url = Self.thumbnailURL(for: file, client: client) {
            RemoteImage(url: url, client: client, maxPixel: size * 3, contentMode: .fill) {
                ChannelFileIcon(kind: file.kind, size: size)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            ChannelFileIcon(kind: file.kind, size: size)
        }
    }

    static func thumbnailURL(for file: FileInfo, client: APIClient) -> URL? {
        guard file.kind == .image else { return nil }
        if file.extension.lowercased() == "gif" && !file.hasPreviewImage { return client.fileURL(id: file.id) }
        return client.fileThumbnailURL(id: file.id)
    }
}

struct ChannelFileIcon: View {
    let kind: FileKind
    var size: CGFloat = 36

    var body: some View {
        let style = Self.style(for: kind)
        Image(systemName: style.symbol)
            .font(.system(size: size * 0.62, weight: .regular))
            .foregroundStyle(style.color)
            .frame(width: size, height: size)
    }

    static func style(for kind: FileKind) -> (symbol: String, color: Color) {
        switch kind {
        case .text: return ("doc.plaintext", Theme.textSecondary)
        case .image: return ("photo", Color(red: 0.55, green: 0.44, blue: 0.86))
        case .audio: return ("waveform", Color(red: 0.89, green: 0.45, blue: 0.20))
        case .video: return ("film", Color(red: 0.89, green: 0.45, blue: 0.20))
        case .spreadsheet: return ("tablecells", Color(red: 0.20, green: 0.62, blue: 0.35))
        case .code: return ("chevron.left.forwardslash.chevron.right", Theme.textSecondary)
        case .word: return ("doc.richtext", Color(red: 0.33, green: 0.56, blue: 0.95))
        case .presentation: return ("rectangle.on.rectangle", Color(red: 0.89, green: 0.45, blue: 0.20))
        case .pdf: return ("doc.richtext", Color(red: 0.86, green: 0.27, blue: 0.29))
        case .patch: return ("plusminus", Color(red: 0.33, green: 0.56, blue: 0.95))
        case .svg: return ("square.on.circle", Color(red: 0.55, green: 0.44, blue: 0.86))
        case .other: return ("doc", Theme.textSecondary)
        }
    }
}

struct ChannelFilesHeaderButton: View {
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: active ? "doc.text.fill" : "doc.text")
                .scaledFont(11.5, weight: .medium)
                .foregroundStyle(active ? Theme.link : hovering ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(background))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Channel files")
        .accessibilityLabel("Channel files")
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if active { return Theme.link.opacity(0.16) }
        return hovering ? Color.white.opacity(0.08) : .clear
    }
}
