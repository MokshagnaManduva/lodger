import Foundation
import CoreGraphics

/// Fires once when activity has been absent for a threshold.
///
/// This is the only place in the engine that schedules a timer for something other
/// than a state's own duration, so it is worth justifying.
///
/// There is no "the user went idle" notification on macOS. The obvious alternative
/// is to sample idle time every second, which is precisely the poll Rule 2 forbids.
/// Instead: ask how long the system has already been idle (a cheap query needing no
/// permission), schedule **one** wake for exactly the remaining time, and on waking
/// ask again. If the user was active in between, the answer is small and the watcher
/// reschedules for the new remainder rather than firing.
///
/// So with a 300-second threshold this wakes at most once every five minutes while
/// the machine is in use, and exactly once when it is not. Generous leeway lets the
/// system coalesce those wakes with something it was going to do anyway.
public final class IdleWatcher {

    /// Seconds since the last activity of the kind being watched.
    public typealias IdleProvider = () -> TimeInterval

    /// System-wide input idle time: keyboard, mouse, trackpad. Needs no permission -
    /// unlike a global *key* monitor, which would need Accessibility.
    public static func systemInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                eventType: .init(rawValue: ~0)!)
    }

    public var onIdle: ((TimeInterval) -> Void)?

    private let provider: IdleProvider
    private var timer: DispatchSourceTimer?
    private var threshold: TimeInterval = 0
    private var fired = false

    public private(set) var scheduledCount = 0
    public var isArmed: Bool { timer != nil }

    public init(provider: @escaping IdleProvider = IdleWatcher.systemInput) {
        self.provider = provider
    }

    deinit { cancel() }

    /// Arm for `seconds`.
    ///
    /// **Idempotent.** The engine calls this on every state change, and re-arming a
    /// watcher that is already counting would reset it - so with a pet that changes
    /// state every couple of seconds, a five-minute idle threshold could never
    /// elapse. `user.idle` means the *user* has gone quiet, not that the pet has.
    public func arm(after seconds: TimeInterval) {
        guard seconds > 0 else { cancel(); return }
        if isArmed, !fired, threshold == seconds { return }   // already counting
        cancel()
        threshold = seconds
        fired = false
        schedule(in: max(0.5, seconds - provider()))
    }

    public func cancel() {
        timer?.cancel()
        timer = nil
    }

    private func schedule(in delay: TimeInterval) {
        let t = DispatchSource.makeTimerSource(queue: .main)
        // Generous leeway: nothing here is time-critical, and coalescing is free.
        let leeway = min(30.0, max(1.0, delay * 0.2))
        t.schedule(deadline: .now() + delay, leeway: .milliseconds(Int(leeway * 1000)))
        t.setEventHandler { [weak self] in self?.check() }
        timer = t
        scheduledCount += 1
        t.resume()
    }

    private func check() {
        timer = nil
        let idle = provider()
        if idle >= threshold {
            guard !fired else { return }
            fired = true
            onIdle?(idle)
        } else {
            // The user was active while we slept: wait out the remainder instead of
            // sampling again in a second.
            schedule(in: max(0.5, threshold - idle))
        }
    }
}
