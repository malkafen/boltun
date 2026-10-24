import AppKit
import BoltunKit
import SwiftUI

public struct BoltunApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup("Boltun") {
            Text("Boltun")
                .frame(minWidth: 800, minHeight: 500)
                .preferredColorScheme(.dark)
        }
    }
}
