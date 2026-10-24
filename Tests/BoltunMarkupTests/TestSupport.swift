import Foundation
import Testing
@testable import BoltunMarkup

func paragraph(_ message: String, _ context: MarkupContext = MarkupContext()) -> AttributedString {
    let blocks = MessageRenderer.render(message, context: context)
    guard blocks.count == 1, case .paragraph(let text) = blocks[0] else {
        Issue.record("expected one paragraph, got \(blocks)")
        return AttributedString()
    }
    return text
}

func text(_ message: String, _ context: MarkupContext = MarkupContext()) -> String {
    String(paragraph(message, context).characters)
}

func links(in text: AttributedString) -> [(text: String, url: String)] {
    text.runs[\.link].compactMap { url, range in
        url.map { (String(text[range].characters), $0.absoluteString) }
    }
}

func linkPairs(_ message: String, _ context: MarkupContext = MarkupContext()) -> [String] {
    links(in: paragraph(message, context)).map { "\($0.text)=\($0.url)" }
}

func intent(of fragment: String, in text: AttributedString) -> InlinePresentationIntent? {
    guard let range = text.range(of: fragment) else {
        Issue.record("missing fragment \(fragment)")
        return nil
    }
    return text[range].inlinePresentationIntent
}

func highlighted(_ text: AttributedString) -> [String] {
    text.highlightedMentionRanges.map { String(text[$0].characters) }
}

func attributed(_ string: String, _ intent: InlinePresentationIntent? = nil) -> AttributedString {
    var result = AttributedString(string)
    if let intent {
        result.inlinePresentationIntent = intent
    }
    return result
}
