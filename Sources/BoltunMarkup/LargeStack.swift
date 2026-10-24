import Foundation
import Synchronization

enum LargeStack {
    static let stackSize = 512 << 20
    static let nestingDelimiterLimit = 128

    static func mayNestDeeply(_ text: String) -> Bool {
        var count = 0
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: ">"), UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "~"), UInt8(ascii: "["),
                 UInt8(ascii: "-"), UInt8(ascii: "+"), UInt8(ascii: "."), UInt8(ascii: ")"):
                count += 1
                if count >= nestingDelimiterLimit {
                    return true
                }
            default:
                continue
            }
        }
        return false
    }

    static func run<Value: Sendable>(_ work: @escaping @Sendable () -> Value) -> Value {
        let result = Mutex<Value?>(nil)
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            let value = work()
            result.withLock { $0 = value }
            done.signal()
        }
        thread.stackSize = stackSize
        thread.start()
        done.wait()
        return result.withLock { $0! }
    }
}
