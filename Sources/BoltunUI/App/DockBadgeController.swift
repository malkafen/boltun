import BoltunKit
import Foundation
import Observation

@MainActor
public final class ValueObserver<Value: Equatable> {
    let read: @MainActor () -> Value
    let onChange: @MainActor (Value) -> Void
    public private(set) var value: Value?
    private var started = false

    public init(read: @escaping @MainActor () -> Value, onChange: @escaping @MainActor (Value) -> Void) {
        self.read = read
        self.onChange = onChange
    }

    public func start() {
        guard !started else { return }
        started = true
        track(initial: true)
    }

    private func track(initial: Bool = false) {
        let next = withObservationTracking {
            read()
        } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
        guard initial || next != value else { return }
        value = next
        onChange(next)
    }
}

@MainActor
public final class DockBadgeController {
    let observer: ValueObserver<String?>

    public init(model: AppModel, apply: @escaping @MainActor (String?) -> Void) {
        observer = ValueObserver(read: { model.badgeLabel }, onChange: apply)
    }

    public var currentLabel: String? { observer.value ?? nil }

    public func start() {
        observer.start()
    }
}
