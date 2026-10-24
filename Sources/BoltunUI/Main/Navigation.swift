import AppKit
import BoltunMarkup
import Foundation

enum FuzzyMatcher {
    static func score(_ query: String, in candidate: String) -> Int? {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return 0 }
        let haystack = Array(candidate.lowercased())
        if let range = candidate.lowercased().range(of: String(needle)) {
            let offset = candidate.lowercased().distance(from: candidate.lowercased().startIndex, to: range.lowerBound)
            return 1000 - offset * 10 - (haystack.count - needle.count)
        }
        var score = 0
        var index = 0
        var previousMatch = -2
        for character in needle {
            var found = false
            while index < haystack.count {
                if haystack[index] == character {
                    score += previousMatch == index - 1 ? 15 : 5
                    if index == 0 || !haystack[index - 1].isLetter { score += 10 }
                    previousMatch = index
                    index += 1
                    found = true
                    break
                }
                index += 1
            }
            if !found { return nil }
        }
        return score - haystack.count
    }
}

struct QuickSwitchItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case open
        case `private`
        case direct
        case group
    }

    var id: String { channelId }
    var channelId: String
    var title: String
    var subtitle: String
    var kind: Kind
    var unread: Bool
    var mentions: Int
    var searchKey: String
}

enum QuickSwitcher {
    static func results(_ items: [QuickSwitchItem], query: String, limit: Int = 50) -> [QuickSwitchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            let unread = items.filter { $0.unread || $0.mentions > 0 }.sorted { $0.mentions > $1.mentions }
            let rest = items.filter { !($0.unread || $0.mentions > 0) }
            return Array((unread + rest).prefix(limit))
        }
        let scored = items.compactMap { item -> (QuickSwitchItem, Int)? in
            let best = [FuzzyMatcher.score(trimmed, in: item.title), FuzzyMatcher.score(trimmed, in: item.searchKey)].compactMap { $0 }.max()
            return best.map { (item, $0 + (item.unread ? 3 : 0)) }
        }
        return scored.sorted { $0.1 == $1.1 ? $0.0.title.localizedCaseInsensitiveCompare($1.0.title) == .orderedAscending : $0.1 > $1.1 }
            .prefix(limit).map(\.0)
    }

    static func moveSelection(_ index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + delta) % count + count) % count
    }
}

enum ChannelNavigator {
    static func adjacent(in ids: [String], from current: String?, offset: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return offset >= 0 ? ids.first : ids.last }
        return ids[((index + offset) % ids.count + ids.count) % ids.count]
    }

    static func nextUnread(in ids: [String], from current: String?, unread: Set<String>, forward: Bool) -> String? {
        guard !ids.isEmpty, !unread.isEmpty else { return nil }
        let start = current.flatMap { ids.firstIndex(of: $0) } ?? (forward ? -1 : ids.count)
        for step in 1...ids.count {
            let index = ((start + (forward ? step : -step)) % ids.count + ids.count) % ids.count
            if unread.contains(ids[index]) && ids[index] != current { return ids[index] }
        }
        return nil
    }
}

enum LinkAction: Equatable {
    case mention(String)
    case channel(String)
    case hashtag(String)
    case external(URL)
}

enum LinkRouter {
    static func action(for url: URL) -> LinkAction {
        let value = payload(of: url)
        switch url.scheme {
        case MarkupLink.mentionScheme: return .mention(value)
        case MarkupLink.channelScheme: return .channel(value)
        case MarkupLink.hashtagScheme: return .hashtag(value)
        default: return .external(url)
        }
    }

    static func payload(of url: URL) -> String {
        let raw = url.absoluteString
        guard let scheme = url.scheme else { return raw }
        var rest = String(raw.dropFirst(scheme.count + 1))
        while rest.hasPrefix("/") { rest.removeFirst() }
        while rest.hasSuffix("/") { rest.removeLast() }
        return rest.removingPercentEncoding ?? rest
    }
}

enum Permalink {
    static func channel(server: URL, teamName: String, channelName: String) -> String {
        server.appending(path: teamName).appending(path: "channels").appending(path: channelName).absoluteString
    }

    static func post(server: URL, teamName: String, postId: String) -> String {
        server.appending(path: teamName).appending(path: "pl").appending(path: postId).absoluteString
    }
}

enum DownloadDestination {
    static func uniqueURL(in directory: URL, filename: String, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let safe = filename.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let name = safe.isEmpty ? "download" : safe
        var candidate = directory.appending(path: name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 1
        while exists(candidate) {
            candidate = directory.appending(path: ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)")
            counter += 1
        }
        return candidate
    }

    static var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Downloads")
    }
}

enum MimeType {
    static func of(filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "pdf": return "application/pdf"
        case "txt", "log", "md": return "text/plain"
        case "json": return "application/json"
        case "zip": return "application/zip"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        default: return "application/octet-stream"
        }
    }
}
