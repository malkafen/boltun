import Foundation
import Testing
@testable import BoltunMarkup

@Suite struct PlainTextTests {
    @Test func stripsInlineMarkdown() {
        #expect(MessageRenderer.plainText("**bold** _it_ ~~s~~ `code` [link](https://x.io) :rocket:") == "bold it s code link 🚀")
    }

    @Test func emptyMessage() {
        #expect(MessageRenderer.plainText("") == "")
    }

    @Test func flattensBlocks() {
        let message = """
        # Title
        > quoted
        > > deeper

        ```swift
        let x = 1
        ```

        ---

        1. one
        2. two
           - nested
        - [x] done

        | a | b |
        |---|---|
        | 1 | 2 |

        ![diagram](https://x.io/files/arch.png)

        ![](https://x.io/files/raw.png)
        """
        #expect(MessageRenderer.plainText(message) == """
        Title
        quoted
        deeper
        let x = 1
        1. one
        2. two
           - nested
        - ☑ done
        a | b
        1 | 2
        diagram
        raw.png
        """)
    }

    @Test func emptyListItemKeepsMarker() {
        #expect(MessageRenderer.plainText("1.\n2. b") == "1.\n2. b")
    }

    @Test func usesContextForChannelNames() {
        let context = MarkupContext(channelDisplayNames: ["dev": "Developers"])
        #expect(MessageRenderer.plainText("see ~dev", context: context) == "see ~Developers")
        #expect(MessageRenderer.plainText("see ~dev") == "see ~dev")
    }

    @Test func plainTextOfBlocks() {
        #expect(MessageRenderer.plainText(of: [.paragraph("a"), .thematicBreak, .code(language: nil, code: "b")]) == "a\nb")
    }
}
