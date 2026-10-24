import Foundation
import Markdown

enum MarkupText {
    static func flattened(_ root: Markup) -> String {
        var result = ""
        var stack: [Markup] = [root]
        while let node = stack.popLast() {
            switch node {
            case let text as Text:
                result += text.string
            case let code as InlineCode:
                result += code.code
            case let code as CodeBlock:
                appendLine(code.code, to: &result)
            case let html as InlineHTML:
                result += html.rawHTML
            case let html as HTMLBlock:
                appendLine(html.rawHTML, to: &result)
            case is SoftBreak, is LineBreak:
                result += "\n"
            default:
                if node is BlockMarkup {
                    appendLine("", to: &result)
                }
                stack.append(contentsOf: node.children.reversed())
            }
        }
        return result.trimmingCharacters(in: .newlines)
    }

    private static func appendLine(_ line: String, to result: inout String) {
        if !result.isEmpty && !result.hasSuffix("\n") {
            result += "\n"
        }
        result += line
    }
}
