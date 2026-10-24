import Foundation

public enum FileTypeFilter: String, CaseIterable, Sendable {
    case all
    case documents
    case spreadsheets
    case presentations
    case code
    case images
    case audio
    case video

    public var title: String {
        switch self {
        case .all: return "All file types"
        case .documents: return "Documents"
        case .spreadsheets: return "Spreadsheets"
        case .presentations: return "Presentations"
        case .code: return "Code"
        case .images: return "Images"
        case .audio: return "Audio"
        case .video: return "Videos"
        }
    }

    public var extensions: [String] {
        switch self {
        case .all: return []
        case .documents: return ["doc", "pdf", "docx", "odt", "rtf", "txt"]
        case .spreadsheets: return ["xls", "xlsx", "ods"]
        case .presentations: return ["ppt", "pptx", "odp"]
        case .code: return ["py", "go", "java", "kt", "c", "cpp", "h", "html", "js", "ts", "cs", "vb", "php", "pl", "r", "rb", "sql", "swift", "json"]
        case .images: return ["png", "jpg", "jpeg", "bmp", "tiff", "svg", "xcf"]
        case .audio: return ["ogg", "mp3", "wav", "flac"]
        case .video: return ["ogm", "mp4", "avi", "webm", "mov", "mkv", "mpeg", "mpg"]
        }
    }
}

public enum FileKind: String, Sendable {
    case text
    case image
    case audio
    case video
    case spreadsheet
    case code
    case word
    case presentation
    case pdf
    case patch
    case svg
    case other

    static let textTypes: Set<String> = ["txt", "rtf", "vtt"]
    static let imageTypes: Set<String> = ["jpg", "gif", "bmp", "png", "jpeg", "tiff", "tif", "webp"]
    static let audioTypes: Set<String> = ["mp3", "wav", "wma", "m4a", "flac", "aac", "ogg", "m4r"]
    static let videoTypes: Set<String> = ["mp4", "avi", "webm", "mkv", "wmv", "mpg", "mov", "flv"]
    static let presentationTypes: Set<String> = ["ppt", "pptx"]
    static let spreadsheetTypes: Set<String> = ["xlsx", "csv"]
    static let wordTypes: Set<String> = ["doc", "docx"]
    static let codeTypes: Set<String> = [
        "applescript", "as", "atom", "bas", "bash", "boot", "c", "c++", "cake", "cc", "cjsx", "cl2", "clj", "cljc", "cljs",
        "cljs.hl", "cljscm", "cljx", "_coffee", "coffee", "cpp", "cs", "csharp", "cson", "css", "d", "dart", "delphi", "dfm",
        "di", "diff", "django", "docker", "dockerfile", "dpr", "erl", "ex", "exs", "f90", "f95", "freepascal", "fs", "fsharp",
        "gcode", "gemspec", "go", "groovy", "gyp", "h", "h++", "handlebars", "hbs", "hic", "hpp", "hs", "html",
        "html.handlebars", "html.hbs", "hx", "iced", "irb", "java", "jinja", "jl", "js", "json", "jsp", "jsx", "kt", "ktm",
        "kts", "lazarus", "less", "lfm", "lisp", "log", "lpr", "lua", "m", "mak", "matlab", "md", "mk", "mkd", "mkdown", "ml",
        "mm", "nc", "obj-c", "objc", "osascript", "pas", "pascal", "perl", "php", "php3", "php4", "php5", "php6", "pl",
        "plist", "podspec", "pp", "ps", "ps1", "py", "r", "rb", "rs", "rss", "ruby", "scala", "scm", "scpt", "scss", "sh",
        "sld", "sql", "st", "styl", "swift", "tex", "thor", "v", "vb", "vbnet", "vbs", "veo", "xhtml", "xml", "xsl", "yaml",
        "zsh",
    ]

    public static func of(extension value: String) -> FileKind {
        let ext = value.lowercased()
        let ordered: [(Set<String>, FileKind)] = [
            (textTypes, .text), (imageTypes, .image), (audioTypes, .audio), (videoTypes, .video),
            (spreadsheetTypes, .spreadsheet), (codeTypes, .code), (wordTypes, .word), (presentationTypes, .presentation),
            (["pdf"], .pdf), (["patch"], .patch), (["svg"], .svg),
        ]
        return ordered.first { $0.0.contains(ext) }?.1 ?? .other
    }
}

extension FileInfo {
    public var kind: FileKind {
        if !`extension`.isEmpty { return FileKind.of(extension: `extension`) }
        return mimeType.hasPrefix("image/") ? .image : .other
    }
}

public struct ChannelFileQuery: Equatable, Sendable {
    public var channelId: String
    public var text: String
    public var filter: FileTypeFilter

    public init(channelId: String, text: String = "", filter: FileTypeFilter = .all) {
        self.channelId = channelId
        self.text = text
        self.filter = filter
    }

    public var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isSearch: Bool { !trimmedText.isEmpty }

    public var terms: String {
        let scope = trimmedText.isEmpty ? "channel:\(channelId)" : "\(trimmedText) channel:\(channelId)"
        return ([scope] + filter.extensions.map { "ext:\($0)" }).joined(separator: " ")
    }
}

public struct FileSearchRequest: Encodable, Equatable, Sendable {
    public var terms: String
    public var isOrSearch: Bool
    public var includeDeletedChannels: Bool
    public var timeZoneOffset: Int
    public var page: Int
    public var perPage: Int

    public init(terms: String, isOrSearch: Bool = false, includeDeletedChannels: Bool = true, timeZoneOffset: Int, page: Int, perPage: Int) {
        self.terms = terms
        self.isOrSearch = isOrSearch
        self.includeDeletedChannels = includeDeletedChannels
        self.timeZoneOffset = timeZoneOffset
        self.page = page
        self.perPage = perPage
    }

    enum CodingKeys: String, CodingKey {
        case terms, page
        case isOrSearch = "is_or_search"
        case includeDeletedChannels = "include_deleted_channels"
        case timeZoneOffset = "time_zone_offset"
        case perPage = "per_page"
    }
}

public struct FileSearchResults: Codable, Sendable {
    public var order: [String]
    public var fileInfos: [String: FileInfo]

    public init(order: [String], fileInfos: [String: FileInfo]) {
        self.order = order
        self.fileInfos = fileInfos
    }

    enum CodingKeys: String, CodingKey {
        case order
        case fileInfos = "file_infos"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = c.value(.order, default: [])
        fileInfos = c.value(.fileInfos, default: [:])
    }

    public var orderedFiles: [FileInfo] { order.compactMap { fileInfos[$0] } }
}
