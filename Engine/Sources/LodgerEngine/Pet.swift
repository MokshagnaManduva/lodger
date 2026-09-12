import AppKit

/// Binds the pieces into a running character: panel, director, scheduler, pointer.
///
/// Note what this class does *not* contain: any per-frame loop. Sprite frames are
/// advanced by the render server, state changes by one scheduled wake, and pointer
/// reactions by events the OS already had to deliver. There is nowhere here for a
/// poll to hide.
public final class Pet {

    public let loaded: PackStore.Loaded
    public let panel: PetPanel
    public let director: Director
    public let scheduler = Scheduler()
    public let pointer: PointerMonitor

    private var body: Body?
    private var atlases: [String: CGImage] = [:]
    private var masks: [String: HitMask] = [:]
    private var currentClip: Pack.Clip?
    private var clipStartedAt = Date()
    private var link: CADisplayLink?
    private var lastLinkTime: CFTimeInterval = 0
    private var motion: Motion
    private var screen: NSScreen?
    private var dragOffset: CGSize = .zero
    private var cachedWorld: Motion.World?
    /// Measurement only: `LODGER_ABLATE=window` skips the window move,
    /// `=springs` skips float displacement, `=both` skips both. Used to attribute
    /// locomotion cost rather than guess at it.
    private let ablate = ProcessInfo.processInfo.environment["LODGER_ABLATE"] ?? ""
    /// Measurement only. Accumulated wall time inside each phase of the tick.
    public private(set) var profile: [String: Double] = [:]
    private let profiling = ProcessInfo.processInfo.environment["LODGER_PROFILE"] != nil
    @inline(__always)
    private func timed(_ key: String, _ work: () -> Void) {
        guard profiling else { work(); return }
        let t = DispatchTime.now().uptimeNanoseconds
        work()
        profile[key, default: 0] += Double(DispatchTime.now().uptimeNanoseconds - t) / 1e9
    }
    public private(set) var springTicks = 0
    public private(set) var linkStarts = 0
    private var lastDistance: Double = .infinity
    private var wasInside = false

    /// Called on every state change, for the diagnostics HUD. Never on a timer.
    public var onStateChange: ((Director.Plan, Scheduler) -> Void)?

    public init(loaded: PackStore.Loaded, seed: UInt64 = 0x9E3779B97F4A7C15) {
        self.loaded = loaded
        let stage = loaded.pack.stage
        self.panel = PetPanel(cellSize: CGSize(width: stage.cell.w, height: stage.cell.h),
                              scale: stage.defaultScale,
                              margin: Body.attachmentMargin(for: loaded.pack))
        self.director = Director(pack: loaded.pack, seed: seed)
        self.motion = Motion(feet: .zero)
        self.pointer = PointerMonitor(panel: panel)
        self.pointer.scale = CGFloat(stage.defaultScale)
        self.pointer.margin = CGFloat(Body.attachmentMargin(for: loaded.pack))
        self.pointer.currentMask = { [weak self] in
            guard let self, let clip = self.currentClip,
                  let m = self.masks[clip.texture] else { return nil }
            return (m, self.visibleCell(of: clip))
        }
        let clickView = installClickView()
        clickView.onClick = { [weak self] in self?.send("pointer.click") }
        clickView.onDragBegin = { [weak self] p in self?.beginDrag(at: p) }
        clickView.onDrag = { [weak self] p in self?.continueDrag(to: p) }
        clickView.onDragEnd = { [weak self] in self?.endDrag() }
    }

    private func installClickView() -> ClickForwardingView {
        let v = ClickForwardingView(frame: panel.contentView?.bounds ?? .zero)
        v.wantsLayer = true
        v.layer?.backgroundColor = .clear
        panel.contentView = v
        return v
    }

    // MARK: world

    private var halfWidth: CGFloat { panel.frame.width / 2 }

    /// The walkable surface for the display the pet is currently on.
    ///
    /// Cached. `NSScreen.screens` and `visibleFrame` are AppKit accessors, not
    /// arithmetic, and recomputing them inside a per-frame tick cost 38 us a frame.
    /// Invalidated on state entry, display reconfiguration, and screen changes -
    /// all of which are events, so nothing polls.
    public var world: Motion.World {
        if let w = cachedWorld { return w }
        let s = screen ?? Stage.screen(containing: motion.feet) ?? NSScreen.main
        let w = s.map { Stage.world(on: $0, halfWidth: halfWidth) }
             ?? Motion.World(floor: 0, left: 0, right: 0)
        cachedWorld = w
        return w
    }

    public func invalidateWorld() { cachedWorld = nil }

    /// Put the pet on the floor of the display under `point`.
    public func place(at point: CGPoint) {
        screen = Stage.screen(containing: point)
        cachedWorld = nil
        motion.feet = point
        motion.rescue(into: world)
        syncWindow()
    }

    private func syncWindow() {
        panel.placeFeet(at: motion.feet, groundOffsetFromBottom: groundOffsetFromBottom)
    }

    // MARK: lifecycle

    public func start() {
        for (name, tex) in loaded.pack.textures where tex.preload {
            _ = atlas(named: name)
        }
        if screen == nil, let main = NSScreen.main {
            place(at: CGPoint(x: main.visibleFrame.midX, y: main.visibleFrame.minY))
        }
        for name in loaded.pack.hitMasks.keys {
            masks[name] = try? PackStore(searchPaths: []).hitMask(
                for: loaded, texture: name) ?? nil
        }
        // Install the pointer monitor only if some state actually reacts to it.
        if packUsesPointer { pointer.install() }
        pointer.onChange = { [weak self] r in self?.pointerMoved(r) }
        apply(director.start())
    }

    public func stop() {
        scheduler.cancel()
        stopLink()
        pointer.uninstall()
        panel.orderOut(nil)
    }

    // MARK: display link — exists only while a spring is unsettled

    /// The one place a per-frame callback can appear.
    ///
    /// Two things can justify it: a float still in motion, or the pet moving under
    /// its own power. It is torn down the instant neither is true, so an idle pet
    /// has no display link at all. Being dragged does not count - that is driven by
    /// mouse events the OS already delivers.
    private func syncDisplayLink() {
        let springsBusy = !(body?.springsSettled ?? true)
        if springsBusy || motion.needsTicking { startLink() } else { stopLink() }
    }

    private func startLink() {
        guard link == nil, let view = panel.contentView else { return }
        let l = view.displayLink(target: self, selector: #selector(tick))
        // Move the window at the sprite's own frame rate, not the display's.
        //
        // Measured: a window move costs ~337 us of app time once the deferred Core
        // Animation commit is counted, which made 30 Hz locomotion 4.7% of a core.
        // A pixel-art walk cycle advances at about 9 fps and translates in whole
        // pixels, so stepping the window in time with the footfalls is both cheaper
        // and more faithful to the style than smoothly sliding it at display rate.
        let hz = max(8.0, min(30.0, clipFrameRate))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: Float(max(8, hz - 4)),
                                                     maximum: Float(hz),
                                                     preferred: Float(hz))
        lastLinkTime = 0
        l.add(to: .main, forMode: .common)
        link = l
        linkStarts += 1
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ sender: CADisplayLink) {
        springTicks += 1
        let dt = lastLinkTime == 0 ? 1.0 / 60.0 : sender.targetTimestamp - lastLinkTime
        lastLinkTime = sender.targetTimestamp

        if motion.needsTicking {
            let before = motion.feet
            var events: [Motion.Event] = []
            timed("kinematics") { events = motion.step(dt, in: world) }
            let moved = CGVector(dx: motion.feet.x - before.x, dy: motion.feet.y - before.y)
            if moved.dx != 0 || moved.dy != 0 {
                if ablate != "window" && ablate != "both" {
                    timed("windowMove") { syncWindow() }
                }
                if ablate != "springs" && ablate != "both" {
                    // A companion trails the body rather than teleporting with it.
                    timed("displaceFloats") {
                        body?.displaceFloats(by: CGVector(dx: -moved.dx, dy: moved.dy))
                    }
                }
            }
            for e in events { deliver(e) }
        }

        var settled = true
        timed("stepSprings") { settled = body?.stepSprings(dt) ?? true }
        if settled && !motion.needsTicking { stopLink() }
    }

    private func deliver(_ e: Motion.Event) {
        switch e {
        case .landed:
            send("physics.landed")
        case .edgeReached(let side):
            // Walking off one display continues onto the next rather than stopping
            // at an invisible wall.
            if let s = screen, let next = Stage.neighbour(of: s, on: side) {
                screen = next
                cachedWorld = nil
                let w = Stage.world(on: next, halfWidth: halfWidth)
                motion.feet.x = side == .left ? w.right : w.left
                motion.feet.y = w.floor
                syncWindow()
            } else {
                send("edge.reached", value: side == .left ? 0 : 1)
            }
        }
    }

    /// Call when the window moves so followers trail instead of teleporting.
    public func windowMoved(by delta: CGVector) {
        body?.displaceFloats(by: delta)
        syncDisplayLink()
    }

    /// Frames per second of the clip currently showing, used to pace locomotion.
    private var clipFrameRate: Double {
        guard let clip = currentClip, !clip.frames.isEmpty else { return 30 }
        let ms = clip.durations(default: loaded.pack.stage.defaultFrameMs).reduce(0, +)
        guard ms > 0 else { return 30 }
        return Double(clip.frames.count) / (Double(ms) / 1000)
    }

    public var hasDisplayLink: Bool { link != nil }
    public var feet: CGPoint { motion.feet }
    public var motionKind: Motion.Kind { motion.kind }

    /// Distance from the panel's bottom edge up to the character's soles, so the
    /// caller can stand the pet on a floor without knowing about the margin.
    public var groundOffsetFromBottom: CGFloat {
        let stage = loaded.pack.stage
        return (CGFloat(stage.cell.h) + panel.margin - CGFloat(stage.ground.y))
             * CGFloat(stage.defaultScale)
    }

    private var packUsesPointer: Bool {
        loaded.pack.states.values.contains { st in
            st.interrupts.contains { $0.on.name.hasPrefix("pointer.") }
        }
    }

    // MARK: state

    /// Which atlas cell is on screen right now.
    ///
    /// The render server owns frame advancement, so this is derived from elapsed
    /// time rather than read back - O(1), computed only when a mouse-move event we
    /// were already handling asks for it. Never polled.
    private func visibleCell(of clip: Pack.Clip) -> Int {
        let ms = clip.durations(default: loaded.pack.stage.defaultFrameMs)
        let total = ms.reduce(0, +)
        guard total > 0, clip.frames.count > 1 else { return clip.frames.first?.cell ?? 0 }
        var t = Int(Date().timeIntervalSince(clipStartedAt) * 1000)
        if clip.loop == .none { t = min(t, total - 1) }
        else if clip.loop == .pingpong {
            let cycle = total * 2
            t %= cycle
            if t >= total { t = cycle - 1 - t }        // reverse leg
        } else { t %= total }
        var acc = 0
        for (i, d) in ms.enumerated() {
            acc += d
            if t < acc { return clip.frames[i].cell }
        }
        return clip.frames.last?.cell ?? 0
    }

    private func apply(_ plan: Director.Plan) {
        guard let clip = loaded.pack.clips[plan.clip] else { return }

        currentClip = clip
        clipStartedAt = Date()

        if body == nil, let host = panel.contentView?.layer {
            body = Body(pack: loaded.pack, host: host) { [weak self] in self?.atlas(named: $0) }
        }
        body?.apply(state: plan.state, bodyClip: clip)
        cachedWorld = nil
        begin(plan.motion)
        syncDisplayLink()

        scheduler.apply(plan.wake) { [weak self] in
            guard let self else { return }
            if let next = self.director.timeout(self.context()) { self.apply(next) }
        }
        onStateChange?(plan, scheduler)
    }

    private func begin(_ spec: Pack.MotionSpec) {
        switch spec {
        case .none:
            motion.begin(.none, in: world)
        case .drag:
            motion.begin(.drag, in: world)
        case .fall(let g, let t):
            motion.begin(.fall(gravity: g, terminal: t), in: world)
        case .walk(let speed, let dir):
            let side: Guard.Side
            switch dir {
            case "left": side = .left
            case "right": side = .right
            case "toPointer": side = lastPointerSide ?? motion.facing
            case "away": side = (lastPointerSide ?? .left) == .left ? .right : .left
            default: side = Bool.random() ? .left : .right
            }
            motion.begin(.walk(speed: speed, direction: side), in: world)
        }
    }

    private func send(_ event: String, value: Double? = nil) {
        if let plan = director.deliver(event: event, value: value, context()) {
            apply(plan)
        }
    }

    private func context() -> Guard.Context {
        var c = Guard.Context()
        c.pointerDistance = lastDistance.isFinite ? lastDistance : nil
        c.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let cal = Calendar.current.dateComponents([.hour, .minute], from: Date())
        c.minutesSinceMidnight = (cal.hour ?? 0) * 60 + (cal.minute ?? 0)
        return c
    }

    private func beginDrag(at cursor: CGPoint) {
        dragOffset = CGSize(width: motion.feet.x - cursor.x, height: motion.feet.y - cursor.y)
        send("pointer.grab")
    }

    private func continueDrag(to cursor: CGPoint) {
        guard case .drag = motion.kind else { return }
        let target = CGPoint(x: cursor.x + dragOffset.width, y: cursor.y + dragOffset.height)
        let onScreen = Stage.screen(containing: target)
        if onScreen != screen { screen = onScreen; cachedWorld = nil }
        let d = motion.moveTo(target)
        syncWindow()
        body?.displaceFloats(by: CGVector(dx: -d.dx * 0.35, dy: d.dy * 0.35))
        syncDisplayLink()
    }

    private func endDrag() {
        guard case .drag = motion.kind else { return }
        send("pointer.release")
    }

    private var lastPointerSide: Guard.Side?

    private func pointerMoved(_ r: PointerMonitor.Reading) {
        lastDistance = r.distance
        lastPointerSide = r.side
        if r.inside != wasInside {
            wasInside = r.inside
            send(r.inside ? "pointer.enter" : "pointer.exit")
        }
        send("pointer.near", value: r.distance)
    }

    private func atlas(named: String) -> CGImage? {
        if let a = atlases[named] { return a }
        guard let tex = loaded.pack.textures[named],
              let img = SpriteLayer.atlas(at: loaded.root.appendingPathComponent(tex.file))
        else { return nil }
        atlases[named] = img
        return img
    }
}

/// Clicks only reach here while `ignoresMouseEvents` is false, which the pointer
/// monitor flips based on the alpha mask - so a click on a transparent pixel goes
/// to whatever is behind the pet, as it should.
public final class ClickForwardingView: NSView {
    public var onClick: (() -> Void)?
    public var onDragBegin: ((CGPoint) -> Void)?
    public var onDrag: ((CGPoint) -> Void)?
    public var onDragEnd: (() -> Void)?
    private var dragging = false

    public override func mouseDown(with event: NSEvent) {
        dragging = false
        onClick?()
    }
    public override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        if !dragging { dragging = true; onDragBegin?(p) }
        onDrag?(p)
    }
    public override func mouseUp(with event: NSEvent) {
        if dragging { dragging = false; onDragEnd?() }
    }
}
