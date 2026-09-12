import AppKit

/// Screen geometry: where the floor is, and which display the pet is on.
///
/// The floor is the top of the Dock when the Dock is on the bottom edge, and the
/// bottom of the screen otherwise. `NSScreen.visibleFrame` already accounts for
/// both the Dock and the menu bar, so it is the whole answer - no Dock probing, no
/// polling, and it stays correct when the Dock is hidden, moved or resized.
public enum Stage {

    /// The world a pet standing on `screen` can walk in. `halfWidth` is half the
    /// pet's on-screen width, so its silhouette stays fully on the display.
    public static func world(on screen: NSScreen, halfWidth: CGFloat) -> Motion.World {
        let f = screen.visibleFrame
        return Motion.World(floor: f.minY,
                            left: f.minX + halfWidth,
                            right: f.maxX - halfWidth)
    }

    /// The screen a point is on, falling back to the one it is nearest. Never nil
    /// while any screen exists, so a pet can always be rescued somewhere visible.
    public static func screen(containing point: CGPoint) -> NSScreen? {
        if let hit = NSScreen.screens.first(where: { $0.frame.contains(point) }) { return hit }
        return NSScreen.screens.min { a, b in
            distance(from: point, to: a.frame) < distance(from: point, to: b.frame)
        } ?? NSScreen.main
    }

    private static func distance(from p: CGPoint, to r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Is there a display immediately beyond `side` that the pet could step onto?
    /// Used so walking off the edge of one display continues onto the next rather
    /// than stopping at an invisible wall.
    public static func neighbour(of screen: NSScreen, on side: Guard.Side) -> NSScreen? {
        let f = screen.frame
        return NSScreen.screens.filter { other in
            guard other != screen else { return false }
            let vertical = other.frame.maxY > f.minY && other.frame.minY < f.maxY
            guard vertical else { return false }
            return side == .left ? other.frame.maxX <= f.minX + 1
                                 : other.frame.minX >= f.maxX - 1
        }.min { a, b in
            side == .left ? a.frame.maxX > b.frame.maxX : a.frame.minX < b.frame.minX
        }
    }
}
