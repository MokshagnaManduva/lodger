import AppKit

/// Cursor tracking and per-pixel hit testing.
///
/// Two decisions worth not undoing:
///
/// 1. **We never rely on the window server routing clicks through transparent
///    pixels.** That behaviour is undocumented and regressed on Sonoma and again
///    on Tahoe 26.3. The window stays `ignoresMouseEvents = true` and flips only
///    while the cursor is inside the character's silhouette.
/// 2. **Mouse-move monitoring needs no TCC permission.** Apple's *Monitoring
///    Events* guide gates only *key* events on accessibility. `CGEventTap` and
///    `IOHIDDeviceOpen` are the permission-gated APIs and are never used.
///
/// A global monitor sees events aimed at other apps; it goes deaf once the cursor
/// is over our own window, so a local monitor covers the exit.
public final class PointerMonitor {

    public struct Reading: Sendable {
        /// Cursor position in the pet's cell coordinates, origin top-left.
        public let local: CGPoint
        /// Distance in screen points from the cursor to the pet's frame.
        public let distance: Double
        public let inside: Bool
        public let side: Guard.Side
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var panel: NSWindow?

    public private(set) var installed = false
    public private(set) var isOverSilhouette = false
    public var onChange: ((Reading) -> Void)?

    /// One entry per hit-testable part, resolved lazily so frames and offsets can
    /// change without reinstalling. The cursor counts as inside if it is over the
    /// opaque pixels of **any** of them - which is how a free-floating companion
    /// becomes clickable rather than only the body.
    public var hitTargets: (() -> [Target])?

    public struct Target {
        public let mask: HitMask
        public let cell: Int
        /// This part's offset from the body's cell, in cell pixels (y down).
        public let offset: CGPoint
        public let mirrored: Bool
        public init(mask: HitMask, cell: Int, offset: CGPoint, mirrored: Bool = false) {
            self.mask = mask; self.cell = cell; self.offset = offset; self.mirrored = mirrored
        }
    }
    /// Cell-sized interaction geometry, independent of a walk's wide host window.
    public var interactionFrame: (() -> CGRect)?
    public var scale: CGFloat = 1
    /// Top-left of the character's cell in screen coordinates.
    ///
    /// A closure rather than a stored value because during a walk the art slides
    /// inside a wider window, so this changes continuously while the window does
    /// not move. Evaluated once per mouse-move event, never on a tick.
    public var cellTopLeft: (() -> CGPoint)?

    public init(panel: NSWindow) { self.panel = panel }

    /// Install only when some reachable state actually cares about the pointer.
    /// A pack with no pointer interrupts should cost nothing here.
    public func install() {
        guard !installed else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.sample()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            self?.sample(); return e
        }
        installed = true
        sample()
    }

    public func uninstall() {
        if let g = globalMonitor { NSEvent.removeMonitor(g) }
        if let l = localMonitor { NSEvent.removeMonitor(l) }
        globalMonitor = nil; localMonitor = nil
        installed = false
        panel?.ignoresMouseEvents = true
        isOverSilhouette = false
    }

    deinit { uninstall() }

    public func sample(notify: Bool = true) {
        guard let panel else { return }
        let cursor = NSEvent.mouseLocation
        let topLeft = cellTopLeft?() ?? CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        let reading = Self.read(cursor: cursor, frame: interactionFrame?() ?? panel.frame,
                                cellTopLeft: topLeft, scale: scale,
                                targets: hitTargets?() ?? [])
        if reading.inside != isOverSilhouette {
            isOverSilhouette = reading.inside
            // The whole hit-testing strategy, in one line.
            panel.ignoresMouseEvents = !reading.inside
        }
        if notify { onChange?(reading) }
    }

    /// Pure, so it can be tested without a window or a run loop.
    public static func read(cursor: CGPoint, frame: CGRect, cellTopLeft: CGPoint,
                            scale: CGFloat, targets: [Target]) -> Reading {
        // Screen coords are y-up; cell coords are y-down from the cell's top-left.
        let localX = (cursor.x - cellTopLeft.x) / scale
        let localY = (cellTopLeft.y - cursor.y) / scale
        let local = CGPoint(x: localX, y: localY)

        let dx = max(frame.minX - cursor.x, 0, cursor.x - frame.maxX)
        let dy = max(frame.minY - cursor.y, 0, cursor.y - frame.maxY)
        let distance = (dx * dx + dy * dy).squareRoot()

        var inside = false
        if targets.isEmpty {
            inside = frame.contains(cursor)     // no masks: fall back to the frame
        } else {
            for t in targets {
                let column = Int((localX - t.offset.x).rounded(.down))
                let x = t.mirrored ? t.mask.cellWidth - 1 - column : column
                let y = Int((localY - t.offset.y).rounded(.down))
                if t.mask.opaque(cell: t.cell, x: x, y: y) { inside = true; break }
            }
        }
        let side: Guard.Side = cursor.x < frame.midX ? .left : .right
        return Reading(local: local, distance: distance, inside: inside, side: side)
    }
}


/// Event-driven velocity estimator. Accumulate high-frequency mouse events until
/// the interval is meaningful; resetting on every sub-4ms event loses fast mice.
public struct PointerVelocity {
    private var point: CGPoint?
    private var time: TimeInterval = 0
    public init() {}
    public mutating func sample(at next: CGPoint, time now: TimeInterval) -> Double? {
        guard let previous = point else { point = next; time = now; return nil }
        let dt = now - time
        guard dt > 0, dt <= 0.25 else { point = next; time = now; return nil }
        guard dt >= 0.004 else { return nil }
        point = next; time = now
        return hypot(next.x - previous.x, next.y - previous.y) / dt
    }
}
