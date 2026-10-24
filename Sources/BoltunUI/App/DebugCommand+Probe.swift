import Foundation

extension DebugCommand {
    public enum ProbeRequest: Equatable, Sendable {
        case posts(sinceLaunch: Bool, timeout: Double)
        case connected(timeout: Double)
        case history(count: Int?, timeout: Double)
        case freeze(since: Double?)
    }

    public static let defaultProbeTimeout: Double = 30

    var isProbe: Bool {
        if case .probe = self { return true }
        return false
    }

    static func makeProbe(action: String, query: [String: String]) -> DebugCommand? {
        guard action == "probe" else { return nil }
        let timeout = query["timeout"].flatMap(Double.init).map { max(0, $0) } ?? defaultProbeTimeout
        switch query["wait"] {
        case "posts":
            return .probe(.posts(sinceLaunch: query["since"] == "launch", timeout: timeout))
        case "connected":
            return .probe(.connected(timeout: timeout))
        case "history":
            return .probe(.history(count: query["count"].flatMap(Int.init), timeout: timeout))
        case nil:
            guard flag(query["freeze"]) else { return nil }
            return .probe(.freeze(since: query["since"].flatMap(Double.init)))
        default:
            return nil
        }
    }
}
