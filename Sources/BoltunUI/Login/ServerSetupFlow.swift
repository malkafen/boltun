import BoltunKit
import SwiftUI

public struct ServerSetupFlow: View {
    public enum Stage: Equatable {
        case addServer
        case login(UUID)
    }

    let model: AppModel
    let onFinish: () -> Void
    @State private var stage: Stage

    public init(model: AppModel, stage: Stage = .addServer, onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
        _stage = State(initialValue: stage)
    }

    public var body: some View {
        Group {
            switch stage {
            case .addServer:
                AddServerView(model: model, onAdded: added, onCancel: onFinish)
            case .login(let serverId):
                LoginView(model: model, serverId: serverId, onSuccess: onFinish, onCancel: onFinish)
                    .id(serverId)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func added(_ server: ServerConfig) {
        if model.needsLogin.contains(server.id) {
            stage = .login(server.id)
        } else {
            onFinish()
        }
        Task { await model.select(serverId: server.id) }
    }
}
