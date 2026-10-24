import BoltunKit
import Foundation
import Observation

@MainActor
@Observable
final class ChannelFilesModel {
    typealias Fetch = @MainActor (ChannelFileQuery, Int) async -> [FileInfo]?

    private(set) var channelId = ""
    private(set) var filter: FileTypeFilter = .all
    var searchText = ""
    private(set) var appliedText = ""
    private(set) var files: [FileInfo] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isAtEnd = false
    private(set) var nextPage = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored let pageSize: Int

    init(pageSize: Int = ServerSession.channelFilesPageSize, fetch: @escaping Fetch) {
        self.pageSize = pageSize
        self.fetch = fetch
    }

    var query: ChannelFileQuery { ChannelFileQuery(channelId: channelId, text: appliedText, filter: filter) }

    var title: String { query.isSearch ? "Search Results" : "Recent files" }

    var emptyState: ChannelFilesEmptyState? {
        guard files.isEmpty, !isLoading else { return nil }
        return ChannelFilesEmptyState(query: query)
    }

    func open(channelId: String) async {
        self.channelId = channelId
        searchText = ""
        appliedText = ""
        await reload()
    }

    func select(filter: FileTypeFilter) async {
        guard filter != self.filter else { return }
        self.filter = filter
        await reload()
    }

    func submitSearch() async {
        appliedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        await reload()
    }

    func clearSearch() async {
        searchText = ""
        guard !appliedText.isEmpty else { return }
        appliedText = ""
        await reload()
    }

    func reload() async {
        generation += 1
        let current = generation
        files = []
        nextPage = 0
        isAtEnd = false
        isLoadingMore = false
        isLoading = true
        let page = await fetch(query, 0)
        guard current == generation else { return }
        isLoading = false
        apply(page)
    }

    func loadMore() async {
        guard !channelId.isEmpty, !isLoading, !isLoadingMore, !isAtEnd else { return }
        let current = generation
        isLoadingMore = true
        let page = await fetch(query, nextPage)
        guard current == generation else { return }
        isLoadingMore = false
        apply(page)
    }

    func loadMoreIfNeeded(after file: FileInfo) async {
        guard file.id == files.last?.id else { return }
        await loadMore()
    }

    private func apply(_ page: [FileInfo]?) {
        guard let page else {
            isAtEnd = true
            return
        }
        let known = Set(files.map(\.id))
        let fresh = page.filter { !known.contains($0.id) }
        files.append(contentsOf: fresh)
        nextPage += 1
        isAtEnd = fresh.isEmpty || page.count < pageSize
    }
}

enum ChannelFilesEmptyState: Equatable {
    case noFiles
    case noFilteredFiles
    case noResults(String)

    init(query: ChannelFileQuery) {
        if query.isSearch {
            self = .noResults(query.trimmedText)
        } else {
            self = query.filter == .all ? .noFiles : .noFilteredFiles
        }
    }

    var title: String {
        switch self {
        case .noFiles: return "No files yet"
        case .noFilteredFiles: return "No files found"
        case .noResults(let text): return "No file results for “\(text)”"
        }
    }

    var subtitle: String {
        switch self {
        case .noFiles: return "Files posted in this channel will show here."
        case .noFilteredFiles: return "This channel doesn't contains any file with the selected file format."
        case .noResults: return "Check the spelling or try another search."
        }
    }

    var systemImage: String {
        switch self {
        case .noFiles, .noFilteredFiles: return "doc.on.doc"
        case .noResults: return "magnifyingglass"
        }
    }
}

struct ChannelFileRowModel: Equatable {
    var id: String
    var name: String
    var kind: FileKind
    var channelTag: String?
    var sender: String
    var sizeText: String
    var dateText: String
    var hasPost: Bool

    var details: String {
        [sender, sizeText, dateText].filter { !$0.isEmpty }.joined(separator: " • ")
    }

    @MainActor
    init(file: FileInfo, session: ServerSession, now: Date, calendar: Calendar) {
        id = file.id
        name = file.name
        kind = file.kind
        channelTag = Self.tag(for: session.channels[file.channelId]?.type)
        sender = file.userId.isEmpty ? "" : session.displayName(userId: file.userId)
        sizeText = ChannelFileFormatting.size(file.size)
        dateText = ChannelFileFormatting.date(file.createAt.mattermostDate, now: now, calendar: calendar)
        hasPost = !file.postId.isEmpty
    }

    static func tag(for type: ChannelType?) -> String? {
        switch type {
        case .direct: return "Direct Message"
        case .group: return "Group Message"
        default: return nil
        }
    }
}

enum ChannelFileFormatting {
    private static let units: [(String, Int64)] = [
        ("TB", 1_099_511_627_776), ("GB", 1_073_741_824), ("MB", 1_048_576), ("KB", 1024),
    ]
    private static let cache = FormatterCache()

    static func size(_ bytes: Int64) -> String {
        guard let unit = units.first(where: { bytes > $0.1 }) else { return "\(bytes) B" }
        return "\(bytes / unit.1) \(unit.0)"
    }

    static func date(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = formatted(date, "h:mm a", calendar: calendar)
        return "\(day(date, now: now, calendar: calendar)) at \(time)"
    }

    private static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "Yesterday" }
        if (2...6).contains(days) { return formatted(date, "EEEE", calendar: calendar) }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return formatted(date, "MMMM dd", calendar: calendar)
        }
        return formatted(date, "MMMM dd, yyyy", calendar: calendar)
    }

    private static func formatted(_ date: Date, _ format: String, calendar: Calendar) -> String {
        cache.formatter(format: format, calendar: calendar).string(from: date)
    }
}
