import Foundation

/// Kinematics for walking, falling and being dragged.
///
/// Pure: no window, no screen, no clock. It is given a world and a timestep and
/// returns a new state plus the events that occurred. That keeps every edge case -
/// landing, hitting a wall, crossing a display - testable without a run loop, and
/// keeps the per-frame code small enough to audit.
public struct Motion: Sendable {

    /// The walkable surface, in screen points. `floor` is the y the pet's soles rest
    /// on; `left`/`right` are the x limits for its centre.
    public struct World: Sendable, Equatable {
        public var floor: Double
        public var left: Double
        public var right: Double
        public init(floor: Double, left: Double, right: Double) {
            self.floor = floor; self.left = left; self.right = right
        }
    }

    public enum Kind: Sendable, Equatable {
        case none
        case walk(speed: Double, direction: Guard.Side)
        case fall(gravity: Double, terminal: Double)
        case drag
    }

    public enum Event: Sendable, Equatable {
        case edgeReached(Guard.Side)
        case landed
    }

    /// Feet position: x is the centre of the pet, y is the soles.
    public var feet: CGPoint
    public var velocity: CGVector = .zero
    public var facing: Guard.Side = .left
    public var kind: Kind = .none

    public init(feet: CGPoint, facing: Guard.Side = .left) {
        self.feet = feet
        self.facing = facing
    }

    /// True while the pet is under its own power - i.e. while a display link is
    /// justified. `none` and `drag` are driven by something else.
    public var needsTicking: Bool {
        switch kind {
        case .none, .drag: return false
        case .walk, .fall: return true
        }
    }

    public mutating func begin(_ kind: Kind, in world: World) {
        self.kind = kind
        switch kind {
        case .walk(_, let dir):
            facing = dir
            velocity = .zero
        case .fall:
            velocity = .zero
        case .none, .drag:
            velocity = .zero
        }
    }

    /// Advance one step. Returns whatever the engine should turn into pack events.
    public mutating func step(_ dt: TimeInterval, in world: World) -> [Event] {
        guard dt > 0 else { return [] }
        var events: [Event] = []

        switch kind {
        case .none, .drag:
            return []

        case .walk(let speed, let direction):
            facing = direction
            let dx = (direction == .left ? -speed : speed) * dt
            feet.x += dx
            feet.y = world.floor
            // Clamp first, then report, so the pet never ends up outside the world
            // even for the frame in which it turns around.
            if feet.x <= world.left {
                feet.x = world.left
                events.append(.edgeReached(.left))
            } else if feet.x >= world.right {
                feet.x = world.right
                events.append(.edgeReached(.right))
            }

        case .fall(let gravity, let terminal):
            velocity.dy -= gravity * dt
            if velocity.dy < -terminal { velocity.dy = -terminal }
            feet.y += velocity.dy * dt
            feet.x += velocity.dx * dt
            if feet.x < world.left { feet.x = world.left; velocity.dx = 0 }
            if feet.x > world.right { feet.x = world.right; velocity.dx = 0 }
            if feet.y <= world.floor {
                feet.y = world.floor
                velocity = .zero
                events.append(.landed)
            }
        }
        return events
    }

    /// Reposition without physics, e.g. while being dragged. Returns the delta so
    /// the caller can hand it to the float springs, which is what makes a companion
    /// trail behind rather than teleport.
    public mutating func moveTo(_ point: CGPoint) -> CGVector {
        let d = CGVector(dx: point.x - feet.x, dy: point.y - feet.y)
        feet = point
        return d
    }

    /// Bring the pet back inside the world - after a display change, a wake, or a
    /// restore from a position that no longer exists. The pet must never be
    /// unreachable.
    @discardableResult
    public mutating func rescue(into world: World) -> Bool {
        var moved = false
        if feet.x < world.left { feet.x = world.left; moved = true }
        if feet.x > world.right { feet.x = world.right; moved = true }
        if feet.y < world.floor { feet.y = world.floor; moved = true }
        return moved
    }
}
