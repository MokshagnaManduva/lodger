import Foundation

/// The only place in the engine allowed to create a timer.
///
/// Concentrating it here means the Rule 2 invariant is checkable by reading one
/// file, and `liveTimers` can be asserted in tests and shown in the diagnostics
/// HUD. If that count is non-zero while the pet is in a quiescent state, that is
/// the bug.
///
/// There is deliberately no repeating timer anywhere. A state schedules exactly
/// one wake for its own end; the next state schedules its own.
public final class Scheduler {

    /// Apple: "set the tolerance to at least 10 percent of the interval for a
    /// repeating timer... even a small amount of tolerance has a significant
    /// positive impact on the energy usage of your app."
    public static let leewayFraction = 0.10
    /// Long idles get generous slack so the system can coalesce our wake with
    /// something else that was going to happen anyway.
    public static let maxLeeway: TimeInterval = 5.0

    private var timer: DispatchSourceTimer?
    private let queue: DispatchQueue

    public private(set) var liveTimers = 0
    public private(set) var scheduledCount = 0

    public init(queue: DispatchQueue = .main) { self.queue = queue }

    deinit { timer?.cancel() }

    /// Arrange the single wake a plan asks for. `.none` cancels everything and
    /// leaves the process with nothing scheduled at all.
    public func apply(_ wake: Director.Wake, _ fire: @escaping () -> Void) {
        cancel()
        guard case .after(let interval) = wake, interval > 0 else { return }

        let leeway = min(Self.maxLeeway, max(0.01, interval * Self.leewayFraction))
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, leeway: .milliseconds(Int(leeway * 1000)))
        t.setEventHandler { [weak self] in
            self?.liveTimers = 0
            self?.timer = nil
            fire()
        }
        timer = t
        liveTimers = 1
        scheduledCount += 1
        t.resume()
    }

    public func cancel() {
        timer?.cancel()
        timer = nil
        liveTimers = 0
    }
}
