import Foundation

/// A damped spring for `float` attachments - a companion that drifts rather than
/// being held.
///
/// Pure and testable: no clock, no layer, no timer. Integration is semi-implicit
/// Euler with substepping, which stays stable at the stiffnesses packs are likely
/// to use without needing a tiny fixed timestep.
///
/// The property that matters for Rule 2 is `settled`. A drifting attachment that
/// could never come to rest would hold a display link open forever, which is
/// exactly the always-running work the project forbids. So the solver reports when
/// it is done, the engine tears the display link down, and the part's remaining
/// motion is an ambient bob running as a render-server animation at no CPU cost.
public struct Spring: Sendable {
    public var stiffness: Double
    public var damping: Double
    public var mass: Double
    public var maxOffset: Double
    /// Speed in px/s below which the spring is considered at rest.
    public var sleepThreshold: Double

    public private(set) var offset: CGPoint = .zero      // displacement from target
    public private(set) var velocity: CGVector = .zero
    public private(set) var settled = true

    public init(stiffness: Double = 90, damping: Double = 12, mass: Double = 1,
                maxOffset: Double = 24, sleepThreshold: Double = 0.15) {
        self.stiffness = max(0.0001, stiffness)
        self.damping = max(0, damping)
        self.mass = max(0.0001, mass)
        self.maxOffset = max(0, maxOffset)
        self.sleepThreshold = max(0.0001, sleepThreshold)
    }

    /// Kick the follower - used when the parent jumps, so it trails rather than
    /// teleporting.
    public mutating func displace(by d: CGVector) {
        offset.x += d.dx
        offset.y += d.dy
        clamp()
        settled = false
    }

    public mutating func reset() {
        offset = .zero; velocity = .zero; settled = true
    }

    /// Advance by `dt` seconds. Returns true once the spring has come to rest, at
    /// which point the caller should stop stepping it.
    @discardableResult
    public mutating func step(_ dt: TimeInterval) -> Bool {
        guard !settled, dt > 0 else { return settled }

        // Substep so a long frame cannot make a stiff spring explode.
        let maxStep = 1.0 / 240.0
        var remaining = min(dt, 0.25)
        while remaining > 0 {
            let h = min(maxStep, remaining)
            remaining -= h
            let ax = (-stiffness * offset.x - damping * velocity.dx) / mass
            let ay = (-stiffness * offset.y - damping * velocity.dy) / mass
            velocity.dx += ax * h
            velocity.dy += ay * h
            offset.x += velocity.dx * h
            offset.y += velocity.dy * h
        }
        clamp()

        let speed = (velocity.dx * velocity.dx + velocity.dy * velocity.dy).squareRoot()
        let displacement = (offset.x * offset.x + offset.y * offset.y).squareRoot()
        if speed < sleepThreshold && displacement < sleepThreshold {
            // Snap rather than asymptote, so "settled" is a real state and not a
            // permanently-almost-there one.
            offset = .zero
            velocity = .zero
            settled = true
        }
        return settled
    }

    private mutating func clamp() {
        let d = (offset.x * offset.x + offset.y * offset.y).squareRoot()
        guard d > maxOffset, d > 0 else { return }
        let k = maxOffset / d
        offset.x *= k; offset.y *= k
        // Kill outward velocity at the limit so it does not fight the clamp.
        let nx = offset.x / maxOffset, ny = offset.y / maxOffset
        let outward = velocity.dx * nx + velocity.dy * ny
        if outward > 0 {
            velocity.dx -= outward * nx
            velocity.dy -= outward * ny
        }
    }
}
