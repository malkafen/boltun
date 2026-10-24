final class SourceMap {
    private let text: String
    private lazy var bytes: [UInt8] = Array(text.utf8)
    private lazy var lineStarts: [Int] = Self.lineStarts(of: bytes)

    init(_ text: String) {
        self.text = text
    }

    func hasDoubleTilde(line: Int, column: Int) -> Bool {
        guard line >= 1, line <= lineStarts.count, column >= 1 else { return false }
        let offset = lineStarts[line - 1] + column - 1
        guard offset + 1 < bytes.count else { return false }
        return bytes[offset] == UInt8(ascii: "~") && bytes[offset + 1] == UInt8(ascii: "~")
    }

    private static func lineStarts(of bytes: [UInt8]) -> [Int] {
        var starts = [0]
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == UInt8(ascii: "\n") {
                starts.append(index)
            } else if byte == UInt8(ascii: "\r") {
                if index < bytes.count, bytes[index] == UInt8(ascii: "\n") {
                    index += 1
                }
                starts.append(index)
            }
        }
        return starts
    }
}
