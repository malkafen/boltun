import AppKit
import SwiftUI
import Testing
@testable import BoltunKit
@testable import BoltunUI

@Suite(.serialized)
@MainActor
struct MainSnapshotTests {
    @Test func mainWindowWithMockData() async {
        let (model, _) = Fixture.appModel()
        let rep = await Snapshot.render(MainView(model: model), size: CGSize(width: 1280, height: 800), name: "main-mock", settle: .milliseconds(900))
        #expect(rep.pixelsWide >= 1280)
        #expect(Snapshot.distinctColors(rep) > 12)
    }
}
