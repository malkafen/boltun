import BoltunKit
import CoreFoundation
import Foundation
import Observation

@MainActor
@Observable
public final class AutomationProbe {
    public static let shared = AutomationProbe()

    struct Stall: Equatable {
        var start: Double
        var end: Double

        var duration: Double { end - start }
    }

    @ObservationIgnored let clock: () -> Double
    @ObservationIgnored let stallThreshold: Double
    @ObservationIgnored let stallLimit: Int
    @ObservationIgnored private(set) var isActive = false
    @ObservationIgnored private(set) var stalls: [Stall] = []
    @ObservationIgnored private var passStart: Double?
    @ObservationIgnored private var pendingPosts: Set<String> = []
    @ObservationIgnored private var pendingIntros: Set<String> = []
    @ObservationIgnored private var observer: CFRunLoopObserver?
    @ObservationIgnored private var connections: ValueObserver<Bool>?
    private(set) var commandAt: Double = 0
    private(set) var postsShownAt: [String: Double] = [:]
    private(set) var introShownAt: [String: Double] = [:]
    private(set) var connectedAt: Double?

    init(clock: @escaping () -> Double = { Date().timeIntervalSince1970 }, stallThreshold: Double = 0.004, stallLimit: Int = 20_000) {
        self.clock = clock
        self.stallThreshold = stallThreshold
        self.stallLimit = stallLimit
    }

    func start(model: AppModel, runLoop: CFRunLoop? = CFRunLoopGetMain()) {
        guard !isActive else { return }
        isActive = true
        let connections = ValueObserver(read: { Self.allConnected(model) }) { [weak self] connected in
            guard connected, let self, self.connectedAt == nil else { return }
            self.connectedAt = self.clock()
        }
        connections.start()
        self.connections = connections
        if let runLoop { observe(runLoop) }
    }

    static func allConnected(_ model: AppModel) -> Bool {
        !model.servers.isEmpty && model.servers.allSatisfy { model.session(for: $0.id)?.connection == .connected }
    }

    private func observe(_ runLoop: CFRunLoop) {
        let activities: CFRunLoopActivity = [.beforeTimers, .beforeSources, .beforeWaiting, .afterWaiting]
        let observer = CFRunLoopObserverCreateWithHandler(nil, activities.rawValue, true, CFIndex.max) { [weak self] _, activity in
            MainActor.assumeIsolated { self?.runLoop(activity) }
        }
        CFRunLoopAddObserver(runLoop, observer, .commonModes)
        self.observer = observer
    }

    func runLoop(_ activity: CFRunLoopActivity) {
        let now = clock()
        if activity == .afterWaiting {
            passStart = now
            return
        }
        if let passStart { record(Stall(start: passStart, end: now)) }
        if activity == .beforeWaiting {
            passStart = nil
            flushPending(at: now)
        } else {
            passStart = now
        }
    }

    private func record(_ stall: Stall) {
        guard stall.duration >= stallThreshold else { return }
        stalls.append(stall)
        if stalls.count > stallLimit { stalls.removeFirst(stalls.count / 2) }
    }

    func commandReceived() {
        guard isActive else { return }
        commandAt = clock()
    }

    func rowsVisible(channelId: String, ids: [String]) {
        guard isActive, ids.contains(where: TimelineItem.isPostId) else { return }
        pendingPosts.insert(channelId)
    }

    func introVisible(channelId: String) {
        guard isActive else { return }
        pendingIntros.insert(channelId)
    }

    func flushPending(at now: Double) {
        for channelId in pendingPosts where (postsShownAt[channelId] ?? -1) < commandAt {
            postsShownAt[channelId] = now
        }
        for channelId in pendingIntros where (introShownAt[channelId] ?? -1) < commandAt {
            introShownAt[channelId] = now
        }
        pendingPosts.removeAll()
        pendingIntros.removeAll()
    }

    func longestStall(from start: Double, to end: Double) -> Double {
        stalls.lazy.filter { $0.end > start && $0.start < end }.map(\.duration).max() ?? 0
    }
}
