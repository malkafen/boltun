import AppKit
import BoltunKit
import SwiftUI

struct ComposerView: View {
    let state: ComposerState
    let workspace: Workspace
    var placeholder: String
    @State private var emojiShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.editingPostId != nil {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                    Text("Editing message").fontWeight(.semibold)
                    Text("· Esc to cancel, Enter to save").foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Cancel") { state.cancelEdit() }.buttonStyle(.plain).foregroundStyle(Theme.link)
                }
                .scaledFont(11.5)
                .foregroundStyle(Theme.warning)
                .padding(.horizontal, 4)
                .padding(.bottom, 5)
            }
            VStack(alignment: .leading, spacing: 8) {
                if !state.uploads.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(state.uploads) { upload in
                                UploadChip(upload: upload) { state.removeUpload(upload.id) }
                            }
                        }
                    }
                }
                ZStack(alignment: .topLeading) {
                    ComposerTextView(state: state)
                        .frame(height: state.editorHeight)
                    if state.text.isEmpty {
                        Text(placeholder)
                            .scaledFont(13.5)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                }
                HStack(spacing: 2) {
                    IconButton(systemName: "paperclip", help: "Attach files") { pickFiles() }
                    IconButton(systemName: "face.smiling", help: "Emoji") { emojiShown = true }
                        .popover(isPresented: $emojiShown, arrowEdge: .top) {
                            EmojiPicker(workspace: workspace) { name in
                                emojiShown = false
                                workspace.recordEmoji(name)
                                state.insert(":\(name): ")
                            }
                        }
                    Spacer()
                    if state.showsLimit {
                        Text("\(state.remaining)")
                            .scaledFont(11, weight: .medium)
                            .monospacedDigit()
                            .foregroundStyle(state.isOverLimit ? Theme.mention : Theme.textSecondary)
                            .help("Maximum \(state.maxLength) characters")
                            .padding(.trailing, 6)
                    }
                    Button { state.submit() } label: {
                        Image(systemName: state.editingPostId == nil ? "paperplane.fill" : "checkmark")
                            .scaledFont(12, weight: .semibold)
                            .foregroundStyle(state.canSend ? .white : Theme.textSecondary)
                            .frame(width: 32, height: 26)
                            .background(RoundedRectangle(cornerRadius: 5).fill(state.canSend ? Theme.accent : Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!state.canSend)
                    .help(state.editingPostId == nil ? "Send (Enter)" : "Save (Enter)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.inputBackground))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(state.editingPostId == nil ? Theme.border : Theme.warning.opacity(0.6)))
            .overlay(alignment: .top) {
                if state.hasSuggestions {
                    Color.clear
                        .frame(height: 0)
                        .overlay(alignment: .bottom) {
                            AutocompletePopup(state: state, client: workspace.session.client)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 6)
                        }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in state.attach(fileURLs: urls) }
        }
    }
}

struct UploadChip: View {
    let upload: PendingUpload
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch upload.state {
                case .uploading: ProgressView().controlSize(.small)
                case .uploaded: Image(systemName: "doc.fill").foregroundStyle(Theme.accent)
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.mention)
                }
            }
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(upload.filename).scaledFont(12, weight: .semibold).lineLimit(1).truncationMode(.middle)
                Text(upload.state == .failed ? "Upload failed" : upload.state == .uploading ? "Uploading…" : FileSizeText.text(upload.size))
                    .scaledFont(10.5)
                    .foregroundStyle(upload.state == .failed ? Theme.mention : Theme.textSecondary)
            }
            .frame(maxWidth: 160, alignment: .leading)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
    }
}

struct AutocompletePopup: View {
    let state: ComposerState
    let client: APIClient

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .scaledFont(10.5, weight: .semibold)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(state.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            row(suggestion, selected: index == state.selectedIndex)
                                .id(suggestion.id)
                                .contentShape(Rectangle())
                                .onTapGesture { state.accept(suggestion) }
                        }
                    }
                }
                .frame(maxHeight: 260)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: state.selectedIndex) { _, index in
                    if state.suggestions.indices.contains(index) { proxy.scrollTo(state.suggestions[index].id) }
                }
            }
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.popover))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 3)
    }

    var title: String {
        switch state.query?.kind {
        case .user: return "PEOPLE"
        case .channel: return "CHANNELS"
        case .emoji: return "EMOJI"
        case nil: return ""
        }
    }

    func row(_ suggestion: AutocompleteSuggestion, selected: Bool) -> some View {
        HStack(spacing: 8) {
            switch suggestion.kind {
            case .user:
                if let userId = suggestion.userId {
                    Avatar(url: client.profileImageURL(userId: userId), client: client, name: suggestion.title.replacingOccurrences(of: "@", with: ""), size: 20)
                } else {
                    Image(systemName: "megaphone").frame(width: 20)
                }
            case .channel:
                Image(systemName: "globe").frame(width: 20).foregroundStyle(Theme.textSecondary)
            case .emoji:
                EmojiGlyphView(name: suggestion.title.trimmingCharacters(in: CharacterSet(charactersIn: ":")), glyph: suggestion.glyph, customEmojiId: suggestion.customEmojiId, client: client, size: 16)
                    .frame(width: 20)
            }
            Text(suggestion.title).scaledFont(13, weight: .semibold).foregroundStyle(Theme.textPrimary)
            Text(suggestion.subtitle).scaledFont(12).foregroundStyle(Theme.textSecondary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 30)
        .background(selected ? Theme.accent.opacity(0.28) : .clear)
    }
}
