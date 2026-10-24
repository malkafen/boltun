import BoltunKit
import BoltunMarkup
import Foundation
import Observation

struct PendingUpload: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case uploading
        case uploaded(FileInfo)
        case failed
    }

    var id = UUID()
    var filename: String
    var size: Int64
    var state: State

    var fileInfo: FileInfo? {
        if case .uploaded(let info) = state { return info }
        return nil
    }
}

@MainActor
@Observable
final class ComposerState {
    let target: ComposerTarget
    let session: ServerSession
    private(set) var text = ""
    private(set) var cursor = 0
    private(set) var textRevision = 0
    var uploads: [PendingUpload] = []
    private(set) var editingPostId: String?
    private(set) var suggestions: [AutocompleteSuggestion] = []
    var selectedIndex = 0
    private(set) var query: AutocompleteQuery?
    private(set) var pendingSends = 0
    private(set) var focusRevision = 0
    var editorHeight: CGFloat = 20

    @ObservationIgnored private var suggestionTask: Task<Void, Never>?
    @ObservationIgnored private var sendChain: Task<Void, Never>?
    @ObservationIgnored private var draftBeforeEdit = ""
    @ObservationIgnored var debounce: Duration = .milliseconds(90)

    init(target: ComposerTarget, session: ServerSession) {
        self.target = target
        self.session = session
    }

    var maxLength: Int { session.config.maxPostSize }

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var remaining: Int { maxLength - text.count }

    var isOverLimit: Bool { remaining < 0 }

    var showsLimit: Bool { remaining < 200 }

    var isUploading: Bool { uploads.contains { $0.state == .uploading } }

    var uploadedFileIds: [String] { uploads.compactMap { $0.fileInfo?.id } }

    var canSend: Bool {
        guard !isOverLimit, !isUploading else { return false }
        if editingPostId != nil { return !trimmedText.isEmpty }
        return !trimmedText.isEmpty || !uploadedFileIds.isEmpty
    }

    var hasSuggestions: Bool { !suggestions.isEmpty }

    var keyContext: ComposerKeyContext {
        ComposerKeyContext(isEmpty: text.isEmpty, hasSuggestions: hasSuggestions, isEditing: editingPostId != nil)
    }

    func requestFocus() {
        focusRevision += 1
    }

    func userEdited(text newText: String, cursor newCursor: Int) {
        let changed = newText != text
        text = newText
        cursor = newCursor
        refreshQuery()
        if changed && !newText.isEmpty && editingPostId == nil {
            session.userTyping(channelId: target.channelId, parentId: target.rootId)
        }
    }

    func userMovedCursor(_ newCursor: Int) {
        guard newCursor != cursor else { return }
        cursor = newCursor
        refreshQuery()
    }

    func replaceText(_ newText: String, cursor newCursor: Int? = nil) {
        text = newText
        cursor = newCursor ?? (newText as NSString).length
        textRevision += 1
        refreshQuery()
    }

    @discardableResult
    func perform(_ command: ComposerCommand) -> Bool {
        switch command {
        case .send:
            submit()
            return true
        case .insertNewline, .passThrough:
            return false
        case .editLastPost:
            return editLastPost()
        case .selectPreviousSuggestion:
            selectedIndex = QuickSwitcher.moveSelection(selectedIndex, by: -1, count: suggestions.count)
            return true
        case .selectNextSuggestion:
            selectedIndex = QuickSwitcher.moveSelection(selectedIndex, by: 1, count: suggestions.count)
            return true
        case .acceptSuggestion:
            guard suggestions.indices.contains(selectedIndex) else { return false }
            accept(suggestions[selectedIndex])
            return true
        case .dismissSuggestions:
            clearSuggestions()
            return true
        case .cancelEdit:
            cancelEdit()
            return true
        }
    }

    func send() async {
        await submit()?.value
    }

    @discardableResult
    func submit() -> Task<Void, Never>? {
        guard canSend else { return nil }
        let message = trimmedText
        let operation: @MainActor () async -> Void
        if let postId = editingPostId {
            let restore = text
            let draft = draftBeforeEdit
            replaceText(draft)
            editingPostId = nil
            draftBeforeEdit = ""
            operation = { [weak self] in
                guard let self, !(await self.session.edit(postId: postId, message: message)) else { return }
                guard self.editingPostId == nil, self.text == draft else { return }
                self.draftBeforeEdit = draft
                self.editingPostId = postId
                self.replaceText(restore)
            }
        } else {
            let fileIds = uploadedFileIds
            let previousText = text
            let previousUploads = uploads
            replaceText("")
            uploads = []
            operation = { [weak self] in
                guard let self, !(await self.session.send(message, channelId: self.target.channelId, rootId: self.target.rootId, fileIds: fileIds)) else { return }
                self.replaceText(self.text.isEmpty ? previousText : self.text + "\n" + previousText)
                self.uploads += previousUploads
            }
        }
        let previous = sendChain
        pendingSends += 1
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await operation()
            self?.pendingSends -= 1
        }
        sendChain = task
        return task
    }

    func lastOwnPost() -> Post? {
        let posts = target.isThread ? session.threadPosts(rootId: target.rootId) : session.timelinePosts(channelId: target.channelId)
        return posts.last { $0.userId == session.myId && !$0.isSystemMessage && !$0.isDeleted && (target.isThread || !$0.isReply) }
            ?? posts.last { $0.userId == session.myId && !$0.isSystemMessage && !$0.isDeleted }
    }

    @discardableResult
    func editLastPost() -> Bool {
        guard let post = lastOwnPost() else { return false }
        beginEditing(post)
        return true
    }

    func beginEditing(_ post: Post) {
        if editingPostId == nil { draftBeforeEdit = text }
        editingPostId = post.id
        replaceText(post.message)
        requestFocus()
    }

    func cancelEdit() {
        guard editingPostId != nil else { return }
        editingPostId = nil
        replaceText(draftBeforeEdit)
        draftBeforeEdit = ""
    }

    func accept(_ suggestion: AutocompleteSuggestion) {
        guard let query else { return }
        let result = AutocompleteParser.apply(suggestion, to: text, query: query)
        replaceText(result.text, cursor: result.cursor)
        clearSuggestions()
    }

    func clearSuggestions() {
        suggestionTask?.cancel()
        suggestionTask = nil
        suggestions = []
        selectedIndex = 0
        query = nil
    }

    func refreshQuery() {
        let next = AutocompleteParser.query(in: text, cursor: cursor)
        guard next != query else { return }
        query = next
        suggestionTask?.cancel()
        guard let next else {
            suggestions = []
            selectedIndex = 0
            return
        }
        setSuggestions(localSuggestions(for: next))
        guard next.kind != .emoji else { return }
        let delay = debounce
        suggestionTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            let remote = await self.remoteSuggestions(for: next)
            guard !Task.isCancelled, self.query == next else { return }
            self.setSuggestions(Self.merge(self.suggestions, remote))
        }
    }

    private func setSuggestions(_ list: [AutocompleteSuggestion]) {
        let previous = suggestions.indices.contains(selectedIndex) ? suggestions[selectedIndex].id : nil
        suggestions = Array(list.prefix(12))
        selectedIndex = previous.flatMap { id in suggestions.firstIndex { $0.id == id } } ?? 0
    }

    static func merge(_ first: [AutocompleteSuggestion], _ second: [AutocompleteSuggestion]) -> [AutocompleteSuggestion] {
        var seen = Set(first.map(\.id))
        var result = first
        for item in second where !seen.contains(item.id) {
            seen.insert(item.id)
            result.append(item)
        }
        return result
    }

    func localSuggestions(for query: AutocompleteQuery) -> [AutocompleteSuggestion] {
        let prefix = query.prefix.lowercased()
        switch query.kind {
        case .user:
            var result = session.users.values
                .filter { !$0.isDeactivated && Self.userMatches($0, prefix: prefix) }
                .sorted { $0.username < $1.username }
                .prefix(8)
                .map(userSuggestion)
            for (name, detail) in Self.specialMentions where name.hasPrefix(prefix) && !prefix.isEmpty {
                result.append(AutocompleteSuggestion(id: "special:\(name)", kind: .user, title: "@\(name)", subtitle: detail, replacement: "@\(name)"))
            }
            return result
        case .channel:
            return session.channels.values
                .filter { !$0.type.isDirectOrGroup && $0.teamId == session.currentTeamId && session.members[$0.id] != nil && !$0.isArchived }
                .filter { prefix.isEmpty || $0.name.lowercased().hasPrefix(prefix) || $0.displayName.lowercased().hasPrefix(prefix) }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                .prefix(8)
                .map(channelSuggestion)
        case .emoji:
            var result: [AutocompleteSuggestion] = Emoji.search(prefix, limit: 10).map {
                AutocompleteSuggestion(id: "emoji:\($0.name)", kind: .emoji, title: ":\($0.name):", subtitle: "", replacement: ":\($0.name):", glyph: $0.glyph)
            }
            for item in EmojiGlyph.frequent where item.name.hasPrefix(prefix) {
                result.append(AutocompleteSuggestion(id: "emoji:\(item.name)", kind: .emoji, title: ":\(item.name):", subtitle: "", replacement: ":\(item.name):", glyph: item.glyph))
            }
            for emoji in session.customEmojis.values.sorted(by: { $0.name < $1.name }) where emoji.name.hasPrefix(prefix) {
                result.append(AutocompleteSuggestion(id: "emoji:\(emoji.name)", kind: .emoji, title: ":\(emoji.name):", subtitle: "Custom", replacement: ":\(emoji.name):", customEmojiId: emoji.id))
            }
            return Self.merge([], result)
        }
    }

    func remoteSuggestions(for query: AutocompleteQuery) async -> [AutocompleteSuggestion] {
        switch query.kind {
        case .user:
            return await session.autocompleteUsers(query.prefix, channelId: target.channelId).filter { !$0.isDeactivated }.map(userSuggestion)
        case .channel:
            return await session.autocompleteChannels(query.prefix).filter { !$0.type.isDirectOrGroup && !$0.isArchived }.map(channelSuggestion)
        case .emoji:
            return []
        }
    }

    static let specialMentions = [
        ("here", "Notifies everyone online in this channel"),
        ("channel", "Notifies everyone in this channel"),
        ("all", "Notifies everyone in this channel"),
    ]

    static func userMatches(_ user: User, prefix: String) -> Bool {
        guard !prefix.isEmpty else { return true }
        return user.username.lowercased().hasPrefix(prefix)
            || user.firstName.lowercased().hasPrefix(prefix)
            || user.lastName.lowercased().hasPrefix(prefix)
            || user.nickname.lowercased().hasPrefix(prefix)
    }

    func userSuggestion(_ user: User) -> AutocompleteSuggestion {
        let full = [user.fullName, user.nickname.isEmpty ? "" : "(\(user.nickname))"].filter { !$0.isEmpty }.joined(separator: " ")
        return AutocompleteSuggestion(id: "user:\(user.id)", kind: .user, title: "@\(user.username)", subtitle: full, replacement: "@\(user.username)", userId: user.id)
    }

    func channelSuggestion(_ channel: Channel) -> AutocompleteSuggestion {
        AutocompleteSuggestion(id: "channel:\(channel.id)", kind: .channel, title: channel.displayName.isEmpty ? channel.name : channel.displayName, subtitle: "~\(channel.name)", replacement: "~\(channel.name)")
    }

    func attach(fileURLs: [URL]) {
        for url in fileURLs {
            guard let data = try? Data(contentsOf: url) else { continue }
            attach(data: data, filename: url.lastPathComponent)
        }
    }

    func attach(data: Data, filename: String, mimeType: String? = nil) {
        let upload = PendingUpload(filename: filename, size: Int64(data.count), state: .uploading)
        uploads.append(upload)
        let mime = mimeType ?? MimeType.of(filename: filename)
        Task { [weak self] in
            guard let self else { return }
            let info = await self.session.upload(channelId: self.target.channelId, filename: filename, data: data, mimeType: mime)
            guard let index = self.uploads.firstIndex(where: { $0.id == upload.id }) else { return }
            self.uploads[index].state = info.map { .uploaded($0) } ?? .failed
        }
    }

    func insert(_ string: String) {
        let ns = text as NSString
        let location = min(cursor, ns.length)
        let updated = ns.replacingCharacters(in: NSRange(location: location, length: 0), with: string)
        replaceText(updated, cursor: location + (string as NSString).length)
        requestFocus()
    }

    func removeUpload(_ id: UUID) {
        uploads.removeAll { $0.id == id }
    }
}
