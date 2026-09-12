import AppKit

/// The window a character lives in.
///
/// One panel per visible pet, sized to the cell - never a full-screen overlay.
/// A full-screen transparent window is what the Tahoe 26.3 hit-testing
/// regression broke, is worse for the compositor, and is worse for other apps.
///
/// `ignoresMouseEvents` starts **true** and is flipped only while the cursor is
/// inside the character's silhouette. See CLAUDE.md 4 for why the engine owns
/// hit testing rather than trusting the window server.
public final class PetPanel: NSPanel {

    public let margin: CGFloat

    /// `margin` pads the window beyond the cell so a drifting `float` attachment is
    /// not clipped by the window edge. Still one small window - never a full-screen
    /// overlay, which is what the Tahoe 26.3 hit-testing regression broke.
    public init(cellSize: CGSize, scale: Int, margin: Int = 0) {
        self.margin = CGFloat(margin)
        let size = CGSize(width: (cellSize.width + CGFloat(margin) * 2) * CGFloat(scale),
                          height: (cellSize.height + CGFloat(margin) * 2) * CGFloat(scale))
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isMovableByWindowBackground = false
        ignoresMouseEvents = true                 // click-through by contract
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        // Deliberately NOT isGeometryFlipped: it also changes how a layer's own
        // contents are oriented, which tangles with contentsRect. Pack coordinates
        // are top-left, so convert explicitly at the point of use instead.
        view.layer?.backgroundColor = .clear
        contentView = view
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    /// The sprite layer, sized to fill the panel.
    public func makeSpriteLayer(atlas: CGImage) -> CALayer {
        let layer = CALayer()
        layer.frame = contentView?.bounds ?? .zero
        layer.contents = atlas
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        contentView?.layer?.addSublayer(layer)
        return layer
    }

    /// Place the pet's feet at `point` in screen coordinates, snapping to whole
    /// logical pixels so a pixel-art sprite never lands on a half pixel.
    /// Moving a window is an IPC round-trip to the window server, so it is the most
    /// expensive thing a walking pet does. Pixel-art positions are whole logical
    /// pixels anyway, so skip the call whenever the rounded origin has not changed.
    @discardableResult
    public func placeFeet(at point: CGPoint, groundOffsetFromBottom: CGFloat) -> Bool {
        let origin = CGPoint(x: (point.x - frame.width / 2).rounded(),
                             y: (point.y - groundOffsetFromBottom).rounded())
        guard origin != frame.origin else { return false }
        setFrameOrigin(origin)
        return true
    }
}
