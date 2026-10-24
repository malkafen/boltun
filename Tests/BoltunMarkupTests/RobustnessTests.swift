import Foundation
import Markdown
import Testing
@testable import BoltunMarkup

@Suite struct RobustnessTests {
    static let richContext = MarkupContext(
        myUsername: "boltun",
        mentionKeys: ["@boltun", "boltun", "deploy", "@channel"],
        channelDisplayNames: ["town-square": "Town Square"],
        customEmojiNames: ["party_parrot"],
        serverURL: URL(string: "https://chat.example.com")
    )

    @Test(arguments: [
        "@", "~", ":", "#", "::", "@@", "~~", "**", "`", "```", "[", "](", "![", "<", ">", "|", "-", "1.", "\\", "&", ";",
        "<3", ":-", "\u{0}", "\r\n", "\r", "\t", "~~~", "**unclosed", "_a", "[a](", "![a](b", "| a |\n|", "> > > >",
        "~a\r\n~b~", "x ~a\u{0}b~ c", "🏳️‍🌈@me", "e\u{301}@b", "\u{202E}abc", "\u{FEFF}#tag", "@\u{301}", ":smile\u{301}:",
    ])
    func survivesTrickyInput(_ message: String) {
        let blocks = MessageRenderer.render(message, context: Self.richContext)
        _ = MessageRenderer.plainText(of: blocks)
        _ = MessageRenderer.plainText(message)
    }

    @Test func survivesHugeMessage() {
        let unit = "**@boltun** see ~town-square #release :rocket: https://x.io/a?b=c `code` ~a b~ _x_\n"
        let message = String(String(repeating: unit, count: 16_384 / unit.count + 1).prefix(16_384))
        let blocks = MessageRenderer.render(message, context: Self.richContext)
        #expect(!blocks.isEmpty)
        #expect(MessageRenderer.plainText(of: blocks).contains("🚀"))
    }

    static let deepMessages: [String] = [
        String(repeating: ">", count: 200) + " deep @boltun",
        String(repeating: ">", count: 16_000) + " deep @boltun",
        (0..<60).map { String(repeating: "  ", count: $0) + "- deep" }.joined(separator: "\n"),
        String(repeating: "- ", count: 8_000) + "deep",
        String(repeating: "1. ", count: 5_000) + "deep",
        String(repeating: "*", count: 8_000) + "deep" + String(repeating: "*", count: 8_000),
        String(repeating: "_", count: 100) + "deep" + String(repeating: "_", count: 100),
        String(repeating: "~a ", count: 2_000) + "deep" + String(repeating: " a~", count: 2_000),
        String(repeating: "[", count: 8_000) + "deep" + String(repeating: "]", count: 8_000),
        String(repeating: "[![", count: 2_000) + "deep" + String(repeating: "](u)](v)", count: 2_000),
    ]

    @Test(arguments: deepMessages)
    func survivesDeepNesting(_ message: String) {
        let blocks = MessageRenderer.render(message, context: Self.richContext)
        #expect(MessageRenderer.plainText(of: blocks).contains("deep"))
    }

    @Test func flattensContentBeyondMaximumDepth() {
        let prefix = String(repeating: "> ", count: MarkupRenderer.maxDepth + 3)
        let message = ["**bold** `code` @boltun", "", "```", "block", "```"].map { prefix + $0 }.joined(separator: "\n")
        var blocks = MessageRenderer.render(message, context: Self.richContext)
        var depth = 0
        while case .quote(let inner) = blocks.first {
            blocks = inner
            depth += 1
        }
        #expect(depth == MarkupRenderer.maxDepth + 1)
        guard case .paragraph(let text) = blocks.first else {
            Issue.record("expected flattened paragraph, got \(blocks)")
            return
        }
        #expect(String(text.characters) == "bold code @boltun\nblock")
        #expect(highlighted(text) == ["@boltun"])
    }

    @Test func flattensInlineContentBeyondMaximumDepth() {
        let depth = MarkupRenderer.maxDepth + 4
        let message = String(repeating: "*a ", count: depth) + "<b>x</b>`c`" + String(repeating: " a*", count: depth)
        let blocks = MessageRenderer.render(message)
        #expect(MessageRenderer.plainText(of: blocks) == String(repeating: "a ", count: depth) + "<b>x</b>c" + String(repeating: " a", count: depth))
    }

    @Test func flattenedTextHandlesBlocks() {
        #expect(MarkupText.flattened(Document(parsing: "a\nb\n\n    code\n\n<div>\nx\n</div>")) == "a\nb\ncode\n<div>\nx\n</div>")
    }

    @Test func detectsDelimiterHeavyMessages() {
        #expect(!LargeStack.mayNestDeeply("plain **text** with - a few. delimiters"))
        #expect(LargeStack.mayNestDeeply(String(repeating: ">", count: LargeStack.nestingDelimiterLimit)))
        #expect(!LargeStack.mayNestDeeply(String(repeating: ">", count: LargeStack.nestingDelimiterLimit - 1)))
    }

    @Test func largeStackPathMatchesDirectRendering() {
        let message = String(repeating: "**@boltun** - item. ", count: 30)
        #expect(LargeStack.mayNestDeeply(message))
        #expect(MessageRenderer.render(message, context: Self.richContext) == MarkupRenderer(source: message, context: Self.richContext).render())
        #expect(LargeStack.run { 42 } == 42)
    }

    @Test func survivesRandomInput() {
        var generator = SeededGenerator(seed: 0xB0_17_00)
        let alphabet: [String] = "abc XYZ019 @~#:;<>*_`[]()!|\\-+.=/\n\t&ü😀\u{301}\u{200D}".map(String.init) + ["http://", "www.", ":smile:", "```", "~~", "- [ ] ", "1. ", "> ", "| a |", "\r\n"]
        for _ in 0..<500 {
            let length = Int.random(in: 0..<120, using: &generator)
            let message = (0..<length).map { _ in alphabet.randomElement(using: &generator)! }.joined()
            let blocks = MessageRenderer.render(message, context: Self.richContext)
            _ = MessageRenderer.plainText(of: blocks)
        }
    }

    @Test func rendersThousandTypicalMessagesQuickly() {
        let samples = [
            "Hey @boltun, can you check ~town-square? :+1:",
            "Deploy finished :white_check_mark: see https://ci.example.com/build/42",
            "**Release notes**\n- fixed crash\n- improved _performance_\n- [x] docs",
            "```swift\nlet value = compute()\n```",
            "> quoted reply\nand my answer #release",
            "| a | b |\n|---|---|\n| 1 | 2 |",
            "lol :joy::joy: that's great :)",
            "plain message without any markup at all, just text that is a bit longer than usual",
        ]
        let messages = (0..<1_000).map { "\(samples[$0 % samples.count]) \($0)" }
        let start = ContinuousClock.now
        for message in messages {
            _ = MessageRenderer.render(message, context: Self.richContext)
        }
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(1), "rendering 1000 messages took \(elapsed)")
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
