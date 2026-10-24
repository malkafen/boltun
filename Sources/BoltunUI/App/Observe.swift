import Foundation
import Observation

@MainActor
enum Observe {
    static func until(timeout: Duration, _ condition: @escaping @MainActor () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline, await nextChange(of: condition, deadline: deadline) else { return condition() }
        }
        return true
    }

    static func nextChange(of condition: @escaping @MainActor () -> Bool, deadline: ContinuousClock.Instant) async -> Bool {
        let signal = Signal()
        return await withCheckedContinuation { continuation in
            signal.continuation = continuation
            withObservationTracking {
                _ = condition()
            } onChange: {
                Task { @MainActor in signal.fire(true) }
            }
            signal.timeout = Task { @MainActor in
                try? await Task.sleep(until: deadline, clock: .continuous)
                signal.fire(false)
            }
        }
    }

    @MainActor
    final class Signal {
        var continuation: CheckedContinuation<Bool, Never>?
        var timeout: Task<Void, Never>?

        func fire(_ changed: Bool) {
            guard let continuation else { return }
            self.continuation = nil
            timeout?.cancel()
            continuation.resume(returning: changed)
        }
    }
}
