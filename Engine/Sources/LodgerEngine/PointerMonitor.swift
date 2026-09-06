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

    /// Resolved lazily so the caller can swap frames without reinstalling.
    public var currentMask: (() -> (HitMask, Int)?)?
    public var scale: CGFloat = 1
    /// Cell-space inset of the artwork inside the (padded) window.
    public var margin: CGFloat = 0

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

    public func sample() {
        guard let panel else { return }
        let reading = Self.read(cursor: NSEvent.mouseLocation, frame: panel.frame,
                                scale: scale, margin: margin, mask: currentMask?())
        if reading.inside != isOverSilhouette {
            isOverSilhouette = reading.inside
            // The whole hit-testing strategy, in one line.
            panel.ignoresMouseEvents = !reading.inside
        }
        onChange?(reading)
    }

    /// Pure, so it can be tested without a window or a run loop.
    public static func read(cursor: CGPoint, frame: CGRect, scale: CGFloat,
                            margin: CGFloat = 0, mask: (HitMask, Int)?) -> Reading {
        // Screen coords are y-up; cell coords are y-down from the top-left, and the
        // artwork is inset by the attachment margin.
        let localX = (cursor.x - frame.minX) / scale - margin
        let localY = (frame.maxY - cursor.y) / scale - margin
        let local = CGPoint(x: localX, y: localY)

        let dx = max(frame.minX - cursor.x, 0, cursor.x - frame.maxX)
        let dy = max(frame.minY - cursor.y, 0, cursor.y - frame.maxY)
        let distance = (dx * dx + dy * dy).squareRoot()

        var inside = false
        if let (m, cell) = mask {
            inside = m.opaque(cell: cell, x: Int(localX.rounded(.down)),
                              y: Int(localY.rounded(.down)))
        } else if frame.contains(cursor) {
            inside = true                       // no mask: fall back to the frame
        }
        let side: Guard.Side = cursor.x < frame.midX ? .left : .right
        return Reading(local: local, distance: distance, inside: inside, side: side)
    }
}
