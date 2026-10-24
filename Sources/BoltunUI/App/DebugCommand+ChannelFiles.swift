import BoltunKit
import Foundation

extension DebugCommand {
    public enum ChannelFileAction: String, Equatable, Sendable {
        case preview
        case open
        case download
        case copyLink = "copy-link"
    }

    static func makeChannelFiles(action: String, query: [String: String]) -> DebugCommand? {
        switch action {
        case "channel-files":
            return .channelFiles(on: query["on"].map(flag) ?? true)
        case "channel-files-filter":
            return query["type"].flatMap(fileTypeFilter).map { .channelFilesFilter($0) }
        case "channel-files-search":
            return .channelFilesSearch(query["q"] ?? "")
        case "channel-files-more":
            return .channelFilesMore
        case "channel-file":
            guard let position = index(query["index"]) else { return nil }
            let fileAction = query["action"].map { ChannelFileAction(rawValue: $0.lowercased()) } ?? .preview
            return fileAction.map { .channelFile(index: position, action: $0) }
        case "quick-look-close":
            return .quickLookClose
        default:
            return nil
        }
    }

    static func fileTypeFilter(_ value: String) -> FileTypeFilter? {
        let normalized = value.lowercased()
        if normalized == "videos" { return .video }
        return FileTypeFilter(rawValue: normalized)
    }
}
