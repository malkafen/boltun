import BoltunKit
import SwiftUI

public struct MainView: View {
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Text(model.selectedServer?.name ?? "Boltun")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.content)
    }
}
