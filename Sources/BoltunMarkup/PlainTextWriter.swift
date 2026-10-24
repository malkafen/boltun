import Foundation

enum PlainTextWriter {
    static func text(of blocks: [MessageBlock]) -> String {
        lines(of: blocks).joined(separator: "\n")
    }

    private static func lines(of blocks: [MessageBlock]) -> [String] {
        blocks.flatMap(lines(of:))
    }

    private static func lines(of block: MessageBlock) -> [String] {
        switch block {
        case .paragraph(let text), .heading(_, let text):
            return [String(text.characters)]
        case .code(_, let code):
            return [code]
        case .quote(let blocks):
            return lines(of: blocks)
        case .list(let ordered, let start, let items):
            return items.enumerated().flatMap { offset, item in
                listItemLines(item, marker: ordered ? "\(start + offset). " : "- ")
            }
        case .table(let header, let rows):
            return ([header] + rows).map { cells in cells.map { String($0.characters) }.joined(separator: " | ") }
        case .thematicBreak:
            return []
        case .image(let url, let alt):
            return [alt.isEmpty ? url.lastPathComponent : alt]
        }
    }

    private static func listItemLines(_ item: [MessageBlock], marker: String) -> [String] {
        let content = lines(of: item)
        guard let first = content.first else { return [marker.trimmingCharacters(in: .whitespaces)] }
        let indent = String(repeating: " ", count: marker.count)
        return [marker + first] + content.dropFirst().map { indent + $0 }
    }
}
