import Foundation
import Markdown

struct MarkupRenderer {
    private let source: String
    private let context: MarkupContext
    private let decorator: TextDecorator
    private let sourceMap: SourceMap

    init(source: String, context: MarkupContext) {
        self.source = source
        self.context = context
        self.decorator = TextDecorator(context: context)
        self.sourceMap = SourceMap(source)
    }

    func render() -> [MessageBlock] {
        let document = Document(parsing: source, options: [.disableSmartOpts])
        return blocks(of: document, depth: 0)
    }

    static let maxDepth = 24

    private func blocks(of parent: Markup, depth: Int) -> [MessageBlock] {
        parent.children.flatMap { blocks(for: $0, depth: depth) }
    }

    private func blocks(for node: Markup, depth: Int) -> [MessageBlock] {
        if depth > Self.maxDepth {
            let text = MarkupText.flattened(node)
            return text.isEmpty ? [] : [.paragraph(decorator.decorate(text, attributes: AttributeContainer()))]
        }
        switch node {
        case let paragraph as Paragraph:
            return blocks(forParagraph: paragraph)
        case let heading as Heading:
            return [.heading(level: heading.level, inline(heading, style: InlineStyle()))]
        case let code as CodeBlock:
            return [.code(language: languageName(code.language), code: trimmingTrailingNewlines(code.code))]
        case let quote as BlockQuote:
            return [.quote(blocks(of: quote, depth: depth + 1))]
        case let list as OrderedList:
            return [.list(ordered: true, start: Int(clamping: list.startIndex), items: list.listItems.map { items(for: $0, depth: depth + 1) })]
        case let list as UnorderedList:
            return [.list(ordered: false, start: 1, items: list.listItems.map { items(for: $0, depth: depth + 1) })]
        case let table as Table:
            return [blocks(forTable: table)]
        case is ThematicBreak:
            return [.thematicBreak]
        case let html as HTMLBlock:
            let text = trimmingTrailingNewlines(html.rawHTML)
            return text.isEmpty ? [] : [.paragraph(AttributedString(text))]
        default:
            return blocks(of: node, depth: depth + 1)
        }
    }

    private func blocks(forParagraph paragraph: Paragraph) -> [MessageBlock] {
        if let images = standaloneImages(in: paragraph) {
            return images
        }
        let text = inline(paragraph, style: InlineStyle())
        return text.characters.isEmpty ? [] : [.paragraph(text)]
    }

    private func standaloneImages(in paragraph: Paragraph) -> [MessageBlock]? {
        var images: [Image] = []
        for child in paragraph.children {
            switch child {
            case let image as Image:
                images.append(image)
            case is SoftBreak, is LineBreak:
                continue
            case let text as Text where text.string.allSatisfy(\.isWhitespace):
                continue
            default:
                return nil
            }
        }
        guard !images.isEmpty else { return nil }
        let blocks = images.compactMap { image -> MessageBlock? in
            guard let url = resolvedURL(image.source) else { return nil }
            return .image(url: url, alt: image.plainText)
        }
        return blocks.count == images.count ? blocks : nil
    }

    private func items(for item: ListItem, depth: Int) -> [MessageBlock] {
        let content = blocks(of: item, depth: depth)
        guard let checkbox = item.checkbox else { return content }
        let mark = checkbox == .checked ? "☑" : "☐"
        if case .paragraph(let text)? = content.first {
            return [.paragraph(AttributedString("\(mark) ") + text)] + content.dropFirst()
        }
        return [.paragraph(AttributedString(mark))] + content
    }

    private func blocks(forTable table: Table) -> MessageBlock {
        let header: [AttributedString] = table.head.cells.map { inline($0, style: InlineStyle()) }
        let rows: [[AttributedString]] = table.body.rows.map { row in row.cells.map { inline($0, style: InlineStyle()) } }
        return .table(header: header, rows: rows)
    }

    private func languageName(_ info: String?) -> String? {
        guard let word = info?.split(whereSeparator: \.isWhitespace).first else { return nil }
        return String(word)
    }

    private func trimmingTrailingNewlines(_ text: String) -> String {
        var result = Substring(text)
        while let last = result.last, last.isNewline {
            result = result.dropLast()
        }
        return String(result)
    }
}

extension MarkupRenderer {
    struct InlineStyle {
        var intent: InlinePresentationIntent = []
        var link: URL?
        var decorates = true
        var depth = 0

        var attributes: AttributeContainer {
            var container = AttributeContainer()
            if !intent.isEmpty {
                container.inlinePresentationIntent = intent
            }
            if let link {
                container.link = link
            }
            return container
        }

        func adding(_ extra: InlinePresentationIntent) -> InlineStyle {
            var style = nested
            style.intent.formUnion(extra)
            return style
        }

        var nested: InlineStyle {
            var style = self
            style.depth += 1
            return style
        }
    }

    enum InlineItem {
        case text(String)
        case node(Markup)
    }

    private func inline(_ parent: Markup, style: InlineStyle) -> AttributedString {
        if style.depth > Self.maxDepth {
            return styledText(MarkupText.flattened(parent), style: style)
        }
        var result = AttributedString()
        for item in inlineItems(of: parent) {
            switch item {
            case .text(let text):
                result.append(styledText(text, style: style))
            case .node(let node):
                result.append(inline(node: node, style: style))
            }
        }
        return result
    }

    private func inlineItems(of parent: Markup) -> [InlineItem] {
        var items: [InlineItem] = []
        var pending = ""
        func flush() {
            if !pending.isEmpty {
                items.append(.text(pending))
                pending = ""
            }
        }
        func collect(_ parent: Markup, depth: Int) {
            for child in parent.children {
                switch child {
                case let text as Text:
                    pending += text.string
                case let strike as Strikethrough where isSingleTilde(strike):
                    pending += "~"
                    if depth < Self.maxDepth {
                        collect(strike, depth: depth + 1)
                    } else {
                        pending += MarkupText.flattened(strike)
                    }
                    pending += "~"
                default:
                    flush()
                    items.append(.node(child))
                }
            }
        }
        collect(parent, depth: 0)
        flush()
        return items
    }

    private func isSingleTilde(_ strike: Strikethrough) -> Bool {
        guard let start = strike.range?.lowerBound else { return false }
        return !sourceMap.hasDoubleTilde(line: start.line, column: start.column)
    }

    private func styledText(_ text: String, style: InlineStyle) -> AttributedString {
        style.decorates ? decorator.decorate(text, attributes: style.attributes) : AttributedString(text, attributes: style.attributes)
    }

    private func inline(node: Markup, style: InlineStyle) -> AttributedString {
        switch node {
        case let emphasis as Emphasis:
            return inline(emphasis, style: style.adding(.emphasized))
        case let strong as Strong:
            return inline(strong, style: style.adding(.stronglyEmphasized))
        case let strike as Strikethrough:
            return inline(strike, style: style.adding(.strikethrough))
        case let code as InlineCode:
            return AttributedString(code.code, attributes: style.adding(.code).attributes)
        case is SoftBreak, is LineBreak:
            return AttributedString("\n")
        case let link as Link:
            return inline(link: link, style: style)
        case let image as Image:
            return inline(image: image, style: style)
        case let html as InlineHTML:
            return AttributedString(html.rawHTML, attributes: style.attributes)
        default:
            return inline(node, style: style.nested)
        }
    }

    private func inline(link: Link, style: InlineStyle) -> AttributedString {
        var linkStyle = style.nested
        linkStyle.decorates = false
        if let url = resolvedURL(link.destination) {
            linkStyle.link = url
        }
        let content = inline(link, style: linkStyle)
        if content.characters.isEmpty, let destination = link.destination {
            return AttributedString(destination, attributes: linkStyle.attributes)
        }
        return content
    }

    private func inline(image: Image, style: InlineStyle) -> AttributedString {
        var imageStyle = style
        imageStyle.decorates = false
        if let url = resolvedURL(image.source) {
            imageStyle.link = url
        }
        let alt = image.plainText
        return AttributedString(alt.isEmpty ? (image.source ?? "") : alt, attributes: imageStyle.attributes)
    }

    private static let blockedSchemes: Set<String> = ["javascript", "vbscript", "data", "file"]

    private func resolvedURL(_ destination: String?) -> URL? {
        guard let raw = destination?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        guard let url = URL(string: raw) ?? raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap({ URL(string: $0) }) else {
            return nil
        }
        if let scheme = url.scheme?.lowercased() {
            return Self.blockedSchemes.contains(scheme) ? nil : url
        }
        if let server = context.serverURL {
            return URL(string: raw, relativeTo: server)?.absoluteURL ?? url
        }
        return url
    }
}
