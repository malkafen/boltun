import BoltunKit
import BoltunMarkup
import SwiftUI

struct MessageBody: View {
    let blocks: [MessageBlock]
    let client: APIClient?
    var scale: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block, client: client, scale: scale)
            }
        }
    }
}

struct BlockView: View {
    let block: MessageBlock
    let client: APIClient?
    var scale: Double = 1
    @Environment(\.fontScale) private var fontScale

    var effectiveScale: Double { scale * fontScale }

    static func headingSize(level: Int) -> CGFloat {
        let sizes: [CGFloat] = [22, 19, 17, 15, 14, 13.5]
        return sizes[max(0, min(level - 1, sizes.count - 1))]
    }

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(Theme.messageFont(scale: effectiveScale))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let text):
            Text(text)
                .font(.system(size: Self.headingSize(level: level) * effectiveScale, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code, scale: effectiveScale)
        case .quote(let blocks):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.quoteBar).frame(width: 3)
                MessageBody(blocks: blocks, client: client, scale: scale)
                    .opacity(0.85)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ordered ? "\(start + index)." : "•")
                            .font(Theme.messageFont(scale: effectiveScale))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .frame(minWidth: 16, alignment: .trailing)
                        MessageBody(blocks: item, client: client, scale: scale)
                    }
                }
            }
        case .table(let header, let rows):
            TableBlockView(header: header, rows: rows, scale: effectiveScale)
        case .thematicBreak:
            Rectangle().fill(Theme.border).frame(height: 1).padding(.vertical, 4)
        case .image(let url, let alt):
            RemoteImage(url: url, client: client, maxPixel: 900, contentMode: .fit) {
                RoundedRectangle(cornerRadius: 6).fill(Theme.codeBackground).frame(width: 160, height: 100)
                    .overlay(Image(systemName: "photo").foregroundStyle(Theme.textSecondary))
            }
            .frame(maxWidth: 420, maxHeight: 320, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .help(alt)
        }
    }
}

struct CodeBlockView: View {
    let language: String?
    let code: String
    var scale: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language)
                    .scaledFont(10.5, weight: .semibold)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(Theme.codeFont(scale: scale))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.codeBackground))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.separator))
    }
}

struct TableBlockView: View {
    let header: [AttributedString]
    let rows: [[AttributedString]]
    var scale: Double = 1

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        cellView(cell, bold: true)
                    }
                }
                .background(Color.white.opacity(0.05))
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(0..<max(header.count, row.count), id: \.self) { index in
                            cellView(index < row.count ? row[index] : AttributedString(""), bold: false)
                        }
                    }
                }
            }
            .overlay(Rectangle().strokeBorder(Theme.border))
        }
    }

    func cellView(_ text: AttributedString, bold: Bool) -> some View {
        Text(text)
            .font(.system(size: 13 * scale, weight: bold ? .semibold : .regular))
            .foregroundStyle(Theme.textPrimary)
            .textSelection(.enabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .border(Theme.separator, width: 0.5)
    }
}
