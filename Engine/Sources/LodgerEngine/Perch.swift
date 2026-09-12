import CoreGraphics

/// Deciding what a pet may sit on, and where the top of it is.
///
/// Pure, so the policy is testable without a permission grant or a second app on
/// screen. The AX plumbing that watches a chosen window lives in `PerchTracker`.
///
/// Note the permission split, which is better than it first appears: window
/// *geometry* comes from `CGWindowList` and needs no permission at all, so the pet
/// can hit-test what it was dropped onto before anything is granted. Only
/// *tracking* a window's movement needs Accessibility. That means the permission
/// can be requested at the moment the user drops the pet on a window, with the
/// window named in the prompt, rather than at first launch for no visible reason.
public enum Perch {

    /// A window the pet might sit on, as reported by `CGWindowList`.
    public struct Candidate: Sendable, Equatable {
        public let windowID: UInt32
        public let pid: pid_t
        public let ownerName: String
        /// Top-left origin, as `CGWindowList` reports it (y grows downward).
        public let bounds: CGRect
        /// `CGWindowList` layer. 0 is a normal application window; the Dock, the
        /// menu bar and other chrome sit on higher layers.
        public let layer: Int
        public let onScreen: Bool

        public init(windowID: UInt32, pid: pid_t, ownerName: String, bounds: CGRect,
                    layer: Int, onScreen: Bool) {
            self.windowID = windowID; self.pid = pid; self.ownerName = ownerName
            self.bounds = bounds; self.layer = layer; self.onScreen = onScreen
        }
    }

    /// The smallest window worth sitting on. A pet perched on a tiny palette looks
    /// like a bug, and tiny windows are usually chrome rather than content.
    public static let minSize = CGSize(width: 200, height: 120)

    /// Is this a window the pet may sit on?
    ///
    /// Engine policy, never pack policy: a pack says *"when I lose my perch, play
    /// these states"* and never names a window or sees window metadata.
    public static func perchable(_ c: Candidate, ownPID: pid_t,
                                 minSize: CGSize = Perch.minSize) -> Bool {
        guard c.onScreen else { return false }
        guard c.pid != ownPID else { return false }          // never ourselves
        guard c.layer == 0 else { return false }             // Dock, menu bar, HUDs
        guard c.bounds.width >= minSize.width,
              c.bounds.height >= minSize.height else { return false }
        return true
    }

    /// Pick the frontmost perchable window under a point.
    ///
    /// `candidates` must be front-to-back, which is the order `CGWindowList`
    /// returns. Called once, at drag-drop - never on a timer.
    public static func target(under point: CGPoint, in candidates: [Candidate],
                              ownPID: pid_t, screenHeight: CGFloat) -> Candidate? {
        candidates.first { c in
            guard perchable(c, ownPID: ownPID) else { return false }
            return flip(c.bounds, screenHeight: screenHeight).contains(point)
        }
    }

    /// `CGWindowList` reports y growing downward from the top of the primary
    /// display; `NSWindow` and `NSEvent.mouseLocation` grow upward from its bottom.
    public static func flip(_ r: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: screenHeight - r.maxY, width: r.width, height: r.height)
    }

    /// The walkable surface along the top edge of a window, in screen coordinates.
    public static func surface(of bounds: CGRect, screenHeight: CGFloat,
                               halfWidth: CGFloat) -> Motion.World {
        let f = flip(bounds, screenHeight: screenHeight)
        return Motion.World(floor: f.maxY,
                            left: f.minX + halfWidth,
                            right: f.maxX - halfWidth)
    }

    /// Is the perch still usable? Anything else is a `perch.lost`.
    public static func stillValid(_ c: Candidate, ownPID: pid_t,
                                 screens: [CGRect], minSize: CGSize = Perch.minSize) -> Bool {
        guard perchable(c, ownPID: ownPID, minSize: minSize) else { return false }
        // Off every display counts as lost: the pet must never be unreachable.
        return screens.contains { $0.intersects(c.bounds) }
    }
}
