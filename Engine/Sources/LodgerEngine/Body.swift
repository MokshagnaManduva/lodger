import AppKit
import QuartzCore

/// The layered character: one `CALayer` per part, in declaration z-order.
///
/// ## The synchronisation problem, and why sockets are still free
///
/// A socket - a rigidly held prop - has to sit on a named anchor that **moves every
/// frame**. But the body's frames are advanced by the render server, so the app
/// process does not know which frame is on screen. Asking would mean sampling the
/// presentation layer every frame, which is exactly the poll Rule 2 forbids.
///
/// The answer is not to ask. The socket gets its *own* discrete keyframe animation
/// on `position`, built from the same `keyTimes` and duration as the parent's
/// `contentsRect` animation, and both are committed in the same transaction. The
/// render server then advances them together. The prop tracks a moving anchor
/// perfectly, and the app still does nothing per frame.
///
/// ## Why a float's target ignores per-frame anchor jitter
///
/// A `float` follower aims at the **mean** of its anchor across the clip, not the
/// per-frame value. If it chased the per-frame anchor, an idle breathing loop would
/// nudge the target a pixel or two forever, the spring would never settle, and the
/// display link would never be torn down - a Rule 2 violation hiding inside a
/// cosmetic detail. Per-frame variation is what the ambient bob is for. The spring
/// wakes when the *clip* changes or the window moves, settles, and sleeps.
public final class Body {

    public struct Part {
        public let decl: Pack.Part
        public let layer: CALayer
        public var spring: Spring?
        public var restCentre: CGPoint = .zero     // layer position when at rest
    }

    public private(set) var parts: [Part] = []
    public private(set) var springsSettled = true

    /// The layer every part hangs from.
    ///
    /// Locomotion animates *this* across a walk segment, so the whole character
    /// translates with one committed animation and the app does no per-frame work.
    /// It is a layer of our own because animating an `NSView`'s backing layer is
    /// fragile - AppKit manages that one.
    ///
    /// Verified experimentally: a position animation here composes with the
    /// per-frame `position` animations Body installs on socket children. Child
    /// positions are relative, so both run and the absolute position is their sum.
    public let rig = CALayer()

    private let pack: Pack
    private let scale: CGFloat
    private let cell: CGSize
    private let panelSize: CGSize
    private let margin: CGFloat
    private let atlas: (String) -> CGImage?

    /// How far outside the cell the art can travel, in cell pixels. A window sized
    /// exactly to the cell clips a drifting float; this is what the panel pads by.
    public static func attachmentMargin(for pack: Pack) -> Int {
        let drift = pack.parts.compactMap { p -> Double? in
            guard p.bind.mode == "float" else { return nil }
            return p.bind.maxOffset + max(abs(p.bind.rest.x), abs(p.bind.rest.y))
        }.max() ?? 0
        return Int(drift.rounded(.up))
    }

    public init(pack: Pack, host: CALayer, atlas: @escaping (String) -> CGImage?) {
        self.pack = pack
        self.scale = CGFloat(pack.stage.defaultScale)
        self.cell = CGSize(width: pack.stage.cell.w, height: pack.stage.cell.h)
        self.margin = CGFloat(Body.attachmentMargin(for: pack))
        self.panelSize = CGSize(width: (cell.width + margin * 2) * scale,
                                height: (cell.height + margin * 2) * scale)
        self.atlas = atlas

        rig.frame = CGRect(origin: .zero, size: panelSize)
        host.addSublayer(rig)

        // Declaration order is z-order unless a part overrides it.
        let ordered = pack.parts.enumerated()
            .sorted { ($0.element.z ?? $0.offset, $0.offset) < ($1.element.z ?? $1.offset, $1.offset) }
        for (_, decl) in ordered {
            let layer = CALayer()
            // Each part layer is one cell, centred in the padded panel.
            layer.frame = CGRect(x: margin * scale, y: margin * scale,
                                 width: cell.width * scale, height: cell.height * scale)
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
            rig.addSublayer(layer)
            var p = Part(decl: decl, layer: layer)
            if case let b = decl.bind, b.mode == "float" {
                p.spring = Spring(stiffness: b.stiffness, damping: b.damping, mass: b.mass,
                                  maxOffset: b.maxOffset, sleepThreshold: b.sleepThreshold)
            }
            parts.append(p)
        }
    }

    /// The rig's natural size in points. The window may be wider during a walk; the
    /// rig slides inside it.
    public var rigSize: CGSize { panelSize }

    /// Convert a cell-space offset (y down) into a layer centre (y up).
    private func centre(dx: Double, dy: Double) -> CGPoint {
        CGPoint(x: panelSize.width / 2 + CGFloat(dx) * scale,
                y: panelSize.height / 2 - CGFloat(dy) * scale)
    }

    private func anchor(_ name: String, on clip: Pack.Clip, frame i: Int) -> CGPoint? {
        guard i < clip.frames.count, let p = clip.frames[i].anchors[name] else { return nil }
        return CGPoint(x: p.x, y: p.y)
    }

    /// An attachment is authored **in place**: drawn in a cell the same size as the
    /// body's, already where it belongs at the clip's first frame. The anchor then
    /// supplies *motion* only - the part moves by `anchor[i] - anchor[0]`.
    ///
    /// The alternative (place the part's pivot onto the parent's absolute anchor)
    /// was tried first and is worse: it needs a pivot declared on every attachment,
    /// it is easy to get wrong by tens of pixels, and getting it wrong pushes the
    /// art outside the window where it is silently clipped.
    private func baseAnchor(_ name: String, on clip: Pack.Clip) -> CGPoint {
        anchor(name, on: clip, frame: 0)
            ?? CGPoint(x: pack.stage.ground.x, y: pack.stage.ground.y)
    }

    // MARK: applying a state

    public func apply(state: String, bodyClip: Pack.Clip) {
        let bodyMs = bodyClip.durations(default: pack.stage.defaultFrameMs)
        let bodyKeyTimes = SpriteLayer.keyTimes(durationsMs: bodyMs)
        let bodyDuration = Double(bodyMs.reduce(0, +)) / 1000
        let repeats = bodyClip.loop != .none
        let autoreverse = bodyClip.loop == .pingpong

        for i in parts.indices {
            let p = parts[i]
            let decl = p.decl
            let visible = decl.visible(in: state)
            p.layer.isHidden = !visible
            guard visible else {
                p.layer.removeAllAnimations()
                continue
            }

            switch decl.bind.mode {
            case "body":
                install(clip: bodyClip, on: p.layer)
                p.layer.position = centre(dx: 0, dy: 0)
                parts[i].restCentre = p.layer.position

            case "overlay":
                if let name = decl.bind.clip, let c = pack.clips[name] {
                    install(clip: c, on: p.layer)
                }
                p.layer.position = centre(dx: 0, dy: 0)
                parts[i].restCentre = p.layer.position

            case "socket":
                applySocket(&parts[i], bodyClip: bodyClip, keyTimes: bodyKeyTimes,
                            duration: bodyDuration, repeats: repeats, autoreverse: autoreverse)

            case "float":
                applyFloat(&parts[i], bodyClip: bodyClip)

            default:
                p.layer.isHidden = true
            }
        }
        refreshSettled()
    }

    private func install(clip: Pack.Clip, on layer: CALayer) {
        guard let tex = pack.textures[clip.texture], let image = atlas(clip.texture) else { return }
        if layer.contents as AnyObject? !== image { layer.contents = image }
        SpriteLayer.install(clip: clip, texture: tex,
                            defaultFrameMs: pack.stage.defaultFrameMs, into: layer)
    }

    private func applySocket(_ p: inout Part, bodyClip: Pack.Clip, keyTimes: [NSNumber],
                             duration: Double, repeats: Bool, autoreverse: Bool) {
        let bind = p.decl.bind
        let ownClip = bind.clip.flatMap { pack.clips[$0] }
        let clip = bind.frames == "clip" ? (ownClip ?? bodyClip) : bodyClip
        install(clip: clip, on: p.layer)

        let off = bind.offset
        guard let anchorName = bind.anchor else { return }
        let base = baseAnchor(anchorName, on: bodyClip)

        // One position per body frame, animated on the body's own timeline so the
        // render server keeps them in lockstep. No per-frame work in this process.
        var centres: [CGPoint] = []
        for i in bodyClip.frames.indices {
            let a = anchor(anchorName, on: bodyClip, frame: i) ?? base
            centres.append(centre(dx: a.x - base.x + off.x, dy: a.y - base.y + off.y))
        }
        p.layer.removeAnimation(forKey: "socket")
        guard let first = centres.first else { return }
        p.layer.position = first
        p.restCentre = first
        guard centres.count > 1, duration > 0 else { return }

        let move = CAKeyframeAnimation(keyPath: "position")
        move.values = centres.map { NSValue(point: $0) }
        move.keyTimes = keyTimes
        move.calculationMode = .discrete
        move.duration = duration
        move.repeatCount = repeats ? .infinity : 1
        move.autoreverses = autoreverse
        move.isRemovedOnCompletion = false
        move.fillMode = .forwards
        p.layer.add(move, forKey: "socket")
    }

    private func applyFloat(_ p: inout Part, bodyClip: Pack.Clip) {
        let bind = p.decl.bind
        if let name = bind.clip, let c = pack.clips[name] { install(clip: c, on: p.layer) }

        // Mean anchor across the clip - deliberately not the per-frame value.
        var sum = CGPoint.zero, n = 0
        if let anchorName = bind.anchor {
            for i in bodyClip.frames.indices {
                if let a = anchor(anchorName, on: bodyClip, frame: i) {
                    sum.x += a.x; sum.y += a.y; n += 1
                }
            }
        }
        let base = bind.anchor.map { baseAnchor($0, on: bodyClip) }
            ?? CGPoint(x: pack.stage.ground.x, y: pack.stage.ground.y)
        let mean = n > 0 ? CGPoint(x: sum.x / Double(n), y: sum.y / Double(n)) : base
        let target = centre(dx: mean.x - base.x + bind.rest.x,
                            dy: mean.y - base.y + bind.rest.y)

        if p.restCentre != target {
            // The clip changed the target: let the follower drift over rather than
            // teleport, which is the whole point of a float.
            if p.restCentre != .zero {
                p.spring?.displace(by: CGVector(dx: p.restCentre.x - target.x,
                                                dy: p.restCentre.y - target.y))
            }
            p.restCentre = target
        }
        p.layer.position = target
        installBob(on: p.layer, bind: bind, centre: target)
    }

    /// The ambient bob is a plain `CABasicAnimation`: committed once, run by the
    /// render server, no CPU. It is what a settled float does instead of ticking.
    private func installBob(on layer: CALayer, bind: Pack.Bind, centre: CGPoint) {
        layer.removeAnimation(forKey: "bob")
        let bob = bind.bob
        guard bob.amplitudeX > 0 || bob.amplitudeY > 0, bob.periodMs > 0 else { return }
        let a = CAKeyframeAnimation(keyPath: "position")
        a.values = [
            NSValue(point: centre),
            NSValue(point: CGPoint(x: centre.x + CGFloat(bob.amplitudeX) * scale,
                                   y: centre.y - CGFloat(bob.amplitudeY) * scale)),
            NSValue(point: centre),
            NSValue(point: CGPoint(x: centre.x - CGFloat(bob.amplitudeX) * scale,
                                   y: centre.y + CGFloat(bob.amplitudeY) * scale)),
            NSValue(point: centre),
        ]
        a.calculationMode = .cubicPaced
        a.duration = Double(bob.periodMs) / 1000
        a.repeatCount = .infinity
        a.timeOffset = a.duration * bob.phase
        a.isRemovedOnCompletion = false
        layer.add(a, forKey: "bob")
    }

    // MARK: springs

    /// Nudge every float, e.g. because the window moved.
    public func displaceFloats(by d: CGVector) {
        for i in parts.indices where parts[i].spring != nil {
            parts[i].spring?.displace(by: d)
        }
        refreshSettled()
    }

    /// Integrate. Returns true once every spring is at rest, which is the engine's
    /// signal to tear the display link down.
    @discardableResult
    public func stepSprings(_ dt: TimeInterval) -> Bool {
        // Early out before touching Core Animation at all. A transaction commit per
        // tick for zero unsettled springs is pure waste, and the locomotion tick
        // calls this every frame.
        guard parts.contains(where: { !($0.spring?.settled ?? true) }) else {
            springsSettled = true
            return true
        }
        var all = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for i in parts.indices {
            guard var s = parts[i].spring, !s.settled else { continue }
            s.step(dt)
            parts[i].spring = s
            let c = parts[i].restCentre
            parts[i].layer.position = CGPoint(x: c.x + s.offset.x, y: c.y + s.offset.y)
            if s.settled {
                // Back to rest: hand motion back to the render server.
                installBob(on: parts[i].layer, bind: parts[i].decl.bind, centre: c)
            } else {
                all = false
            }
        }
        CATransaction.commit()
        springsSettled = all
        return all
    }

    private func refreshSettled() {
        springsSettled = parts.allSatisfy { $0.spring?.settled ?? true }
    }
}
