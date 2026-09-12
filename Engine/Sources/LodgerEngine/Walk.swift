import Foundation

/// A single stretch of walking, resolved up front so it can be handed to the
/// render server as one committed animation.
///
/// Locomotion used to move the window every tick, which measured at ~340-450 us a
/// move once the deferred Core Animation commit was counted - 2.4% of a core while
/// walking. Resolving the whole stretch in advance means one window resize and one
/// animation instead, and no display link at all.
///
/// Pure: no window, no layer, no clock beyond the start date it is given. Every
/// awkward case - clamping at a screen edge, splitting a long walk, finding the
/// position mid-stretch for a grab - is testable without a run loop.
public struct Walk: Sendable, Equatable {
    public let startX: Double
    public let endX: Double
    public let seconds: Double
    public let startedAt: Date
    /// The stretch ended because it ran into the edge of the world.
    public let hitEdge: Bool
    /// The stretch was cut short by the span cap, not by the edge or the duration.
    public let capped: Bool
    public let direction: Guard.Side

    /// A walk is never allowed to span an arbitrary distance.
    ///
    /// The window has to be wide enough to contain the whole stretch, and a
    /// near-full-screen transparent window is exactly what the Tahoe 26.3
    /// hit-testing regression broke. So long walks are split into chained stretches:
    /// a handful of window resizes, and no window much wider than the pet.
    public static func spanCap(displayWidth: Double) -> Double {
        min(displayWidth / 3, 400)
    }

    /// Resolve the next stretch. Returns nil when there is nowhere to go, which
    /// happens when the pet is already pinned against the edge it is facing.
    public static func resolve(from x: Double, direction: Guard.Side, speed: Double,
                               remainingSeconds: Double, world: Motion.World,
                               displayWidth: Double, now: Date = Date()) -> Walk? {
        guard speed > 0, remainingSeconds > 0 else { return nil }
        let cap = spanCap(displayWidth: displayWidth)
        let wanted = speed * remainingSeconds
        let travel = min(wanted, cap)

        let unclamped = direction == .left ? x - travel : x + travel
        let end = min(max(unclamped, world.left), world.right)
        let span = abs(end - x)
        guard span > 0.5 else { return nil }

        let seconds = span / speed
        // Clamped by the world, not merely by the cap or the clock.
        let hitEdge = (direction == .left && end <= world.left + 0.001)
                   || (direction == .right && end >= world.right - 0.001)
        let capped = !hitEdge && travel < wanted - 0.001

        return Walk(startX: x, endX: end, seconds: seconds, startedAt: now,
                    hitEdge: hitEdge, capped: capped, direction: direction)
    }

    /// Where the pet is now. Derived from elapsed time rather than read back from
    /// the render server, so asking is O(1) and nothing polls.
    public func x(at now: Date) -> Double {
        guard seconds > 0 else { return endX }
        let t = min(max(now.timeIntervalSince(startedAt) / seconds, 0), 1)
        return startX + (endX - startX) * t
    }

    public var minX: Double { min(startX, endX) }
    public var maxX: Double { max(startX, endX) }
    public var span: Double { maxX - minX }

    /// Seconds still owed to the walking state once this stretch finishes.
    public func remainingAfter(_ remainingSeconds: Double) -> Double {
        max(0, remainingSeconds - seconds)
    }
}
