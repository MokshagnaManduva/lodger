import AppKit

/// Binds the pieces into a running character: panel, director, scheduler, pointer.
///
/// Note what this class does *not* contain: any per-frame loop. Sprite frames are
/// advanced by the render server, state changes by one scheduled wake, and pointer
/// reactions by events the OS already had to deliver. PointerMonitor additionally
/// refreshes input routing at silhouette boundaries and during continuous hover;
/// that narrowly scoped work does not drive the sprite animation.
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
    private var link: CADisplayLink?
    private var lastLinkTime: CFTimeInterval = 0
    private var motion: Motion
    private var screen: NSScreen?
    private var dragOffset: CGSize = .zero
    private var cachedWorld: Motion.World?
    private var walk: Walk?
    private var walkRemaining: Double = 0
    private var walkSpeed: Double = 0
    private var walkDirection: Guard.Side = .left
    private let displayScale: Int

    public let systemEvents = SystemEvents()
    public let audio = Audio()
    /// One for system-wide input, one for the cursor specifically.
    public let userIdle = IdleWatcher()
    public lazy var pointerIdle = IdleWatcher { [weak self] in
        guard let t = self?.lastPointerTime, t > 0 else { return 0 }
        return CACurrentMediaTime() - t
    }
    private var wants: [String: Double?] = [:]

    /// Values for the knobs the pack declared in `tuning`. Set by the host from its
    /// own settings store; the engine only ever divides durations by them.
    public var tuning: [String: Double] = [:] {
        didSet {
            director.tuning = tuning
            // A slider may supply an event threshold. Re-resolve what is watched
            // here, on the user's change, rather than ever re-reading it on a tick.
            guard started else { return }
            wants = loaded.pack.requestedEvents(tuning: tuning)
            rearmIdleWatchers()
        }
    }
    /// Values for the toggles the pack declared in `tuning`, read by its `flag`
    /// guards. Takes effect at the next event or timeout; nothing is scheduled.
    public var flags: [String: Bool] = [:] {
        didSet {
            director.flags = flags
            // Lets a pack respond to the switch itself - re-routing out of a
            // quiescent state, say - instead of waiting for its next event. Sent
            // only on a user's change, and dropped by `send` unless the current
            // state listens for it.
            if started, oldValue != flags { send("controls.changed") }
        }
    }
    private var started = false
    /// Host options, for any pack. None of these adds a timer.
    /// Window opacity, 0.05...1.
    public var opacity: Double = 1 {
        didSet { panel.alphaValue = CGFloat(min(1, max(0.05, opacity))) }
    }
    /// When false, the character never sets off walking by itself.
    public var allowsAutonomousWalking: Bool {
        get { director.allowsAutonomousWalking }
        set { director.allowsAutonomousWalking = newValue }
    }
    /// Pace to apply to timed states while on battery, or nil to ignore the power
    /// source. Watching it uses IOKit's change notification - nothing is polled -
    /// and the observer exists only while this is set or the pack asks for it.
    public var batteryPace: Double? {
        didSet { if started, oldValue != batteryPace { installSystemEvents() } }
    }
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

    public init(loaded: PackStore.Loaded, scale: Int? = nil,
                seed: UInt64 = 0x9E3779B97F4A7C15) {
        self.loaded = loaded
        let stage = loaded.pack.stage
        self.displayScale = scale ?? stage.defaultScale
        self.panel = PetPanel(cellSize: CGSize(width: stage.cell.w, height: stage.cell.h),
                              scale: self.displayScale,
                              margin: Body.attachmentMargin(for: loaded.pack))
        self.director = Director(pack: loaded.pack, seed: seed)
        // The pack's own defaults, so a host that sets nothing gets the authored
        // behaviour. (Property observers do not run during init.)
        self.tuning = loaded.pack.defaultTuning
        self.flags = loaded.pack.defaultFlags
        self.director.tuning = loaded.pack.defaultTuning
        self.director.flags = loaded.pack.defaultFlags
        self.motion = Motion(feet: .zero)
        self.pointer = PointerMonitor(panel: panel)
        self.pointer.scale = CGFloat(self.displayScale)
        // cellTopLeft is wired in start(), once the rig exists.
        self.pointer.hitTargets = { [weak self] in
            guard let self, let body = self.body else { return [] }
            return body.hitParts { body.visibleCell(of: $0) }.compactMap { hp in
                guard let m = self.masks[hp.texture] else { return nil }
                return PointerMonitor.Target(mask: m, cell: hp.cell, offset: hp.offset, mirrored: hp.mirrored)
            }
        }
        let clickView = installClickView()
        clickView.onClick = { [weak self] clicks in
            self?.send(clicks >= 2 ? "pointer.doubleClick" : "pointer.click")
        }
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

    /// Half the *character's* width, not the window's.
    ///
    /// The window is deliberately wider than the character during a walk so the rig
    /// can slide inside it. Using the window here would shrink the walkable world
    /// every time a stretch started, progressively trapping the pet.
    private var halfWidth: CGFloat { rigHalfWidth }

    /// The walkable surface for the display the pet is currently on.
    ///
    /// Cached. `NSScreen.screens` and `visibleFrame` are AppKit accessors, not
    /// arithmetic, and recomputing them inside a per-frame tick cost 38 us a frame.
    /// Invalidated on state entry, display reconfiguration, and screen changes -
    /// all of which are events, so nothing polls.
    public var world: Motion.World {
        if let w = cachedWorld { return w }
        let w: Motion.World
        let s = screen ?? Stage.screen(containing: motion.feet) ?? NSScreen.main
        w = s.map { Stage.world(on: $0, halfWidth: halfWidth) }
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
        if pointer.installed { pointer.sample(notify: false) }
    }

    public var isWalking: Bool { walk != nil }

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

        // Observers only for what the pack asks for.
        audio.load(pack: loaded.pack, root: loaded.root)
        wants = loaded.pack.requestedEvents(tuning: tuning)
        started = true
        installSystemEvents()

        userIdle.onIdle = { [weak self] secs in self?.send("user.idle", value: secs) }
        pointerIdle.onIdle = { [weak self] secs in self?.send("pointer.idle", value: secs) }
        pointer.onChange = { [weak self] r in self?.pointerMoved(r) }
        pointer.cellTopLeft = { [weak self] in self?.cellTopLeftOnScreen() ?? .zero }
        pointer.interactionFrame = { [weak self] in
            guard let self else { return .zero }
            let top = self.cellTopLeftOnScreen()
            let stage = self.loaded.pack.stage
            let scale = CGFloat(self.displayScale)
            return CGRect(x: top.x, y: top.y - CGFloat(stage.cell.h) * scale,
                          width: CGFloat(stage.cell.w) * scale, height: CGFloat(stage.cell.h) * scale)
        }
        pointer.animationUpdate = { [weak self] cursor in
            guard let self, let body = self.body, !body.isPaused else { return .none }
            if self.walk != nil { return .continuous }
            let top = self.cellTopLeftOnScreen()
            let scale = CGFloat(self.displayScale)
            return body.routingUpdate(cursor: CGPoint(x: (cursor.x - top.x) / scale,
                                                       y: (top.y - cursor.y) / scale), masks: self.masks)
        }
        apply(director.start())
        // Install after layers, masks and callbacks exist; never fall back to a
        // rectangular hit target during startup.
        if packUsesPointer { pointer.install() }
    }

    /// Observers only for what the pack, or a host option, asks for.
    private func installSystemEvents() {
        var w: SystemEvents.Wants = []
        if wants["system.wake"] != nil || wants["system.willSleep"] != nil { w.insert(.sleepWake) }
        if wants["power.lowPowerMode"] != nil || wants["power.onBattery"] != nil { w.insert(.power) }
        if wants["display.changed"] != nil { w.insert(.displays) }
        if wants["space.changed"] != nil { w.insert(.space) }
        // Occlusion always earns its place: it lets the engine stop animating behind
        // another window whether or not the pack asked to hear about it.
        w.insert(.occlusion)
        if batteryPace != nil { w.insert(.power) }
        systemEvents.onEvent = { [weak self] name, value in
            guard let self else { return }
            if name == "power.onBattery" { self.applyPace(onBattery: value == 1) }
            self.send(name, value: value)
        }
        systemEvents.onOcclusionChanged = { [weak self] hidden in
            self?.body?.setPaused(hidden)
            self?.pointer.sample(notify: false)
        }
        systemEvents.install(w, window: panel)
        applyPace(onBattery: batteryPace != nil && SystemEvents.onBattery())
    }

    private func applyPace(onBattery: Bool) {
        director.pace = onBattery ? (batteryPace ?? 1) : 1
    }

    public func stop() {
        started = false
        audio.stopAll()
        scheduler.cancel()
        userIdle.cancel()
        pointerIdle.cancel()
        systemEvents.uninstall()
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
        let hz: Double
        if case .fall = motion.kind {
            // Falling is physics, not sprite art: gravity integrates every tick
            // regardless of how many art frames the falling clip has. Pacing the
            // window move to the clip's own frame rate - the walking-era policy
            // below - clamped a 140 ms/frame, four-pose falling clip to ~8 Hz of
            // actual translation, which is the jitter this pack reported. Discrete
            // pose timing is unaffected: `apply`/`visibleCell` still hold each art
            // frame for its authored duration, independent of this cadence.
            hz = 60
        } else {
            // Move the window at the sprite's own frame rate, not the display's.
            //
            // Measured: a window move costs ~337 us of app time once the deferred
            // Core Animation commit is counted, which made 30 Hz locomotion 4.7% of
            // a core. Walking itself now runs in the render server (`beginWalk`
            // deliberately starts no display link), so this path is left for any
            // other clip-driven, per-tick motion and keeps its original pacing.
            hz = max(8.0, min(30.0, clipFrameRate))
        }
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

        let wasSettled = body?.springsSettled ?? true
        var settled = true
        timed("stepSprings") { settled = body?.stepSprings(dt) ?? true }
        if settled && !wasSettled { send("physics.settled") }
        if settled && !motion.needsTicking { stopLink() }
        if pointer.installed { pointer.sample(notify: false) }
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
    /// Where the pet is now.
    ///
    /// While a walk stretch is in flight the render server owns the position, so
    /// this is interpolated from elapsed time rather than read back. O(1), and only
    /// evaluated when something asks.
    public var feet: CGPoint {
        guard let w = walk else { return motion.feet }
        return CGPoint(x: w.x(at: Date()), y: motion.feet.y)
    }
    public var motionKind: Motion.Kind { motion.kind }

    /// Distance from the panel's bottom edge up to the character's soles, so the
    /// caller can stand the pet on a floor without knowing about the margin.
    public var groundOffsetFromBottom: CGFloat {
        let stage = loaded.pack.stage
        return (CGFloat(stage.cell.h) + panel.margin - CGFloat(stage.ground.y))
             * CGFloat(displayScale)
    }

    private var packUsesPointer: Bool {
        loaded.pack.states.values.contains { st in
            st.interrupts.contains { $0.on.name.hasPrefix("pointer.") }
        }
    }

    // MARK: state

    private func apply(_ plan: Director.Plan) {
        guard let clip = loaded.pack.clips[plan.clip] else { return }

        currentClip = clip

        if body == nil, let host = panel.contentView?.layer {
            body = Body(pack: loaded.pack, host: host, scale: displayScale) { [weak self] in self?.atlas(named: $0) }
        }
        endWalk()                       // adopt the position of any walk in flight
        body?.apply(state: plan.state, bodyClip: clip)
        cachedWorld = nil
        applyFacing(for: plan.state, clip: clip)
        if let s = loaded.pack.states[plan.state]?.sound { audio.play(s) }
        audio.schedule(clip: clip, defaultFrameMs: loaded.pack.stage.defaultFrameMs,
                       loop: clip.loop != .none)

        if case .walk(let speed, let dir) = plan.motion,
           case .after(let planned) = plan.wake {
            // Resolved up front and handed to the render server: no display link,
            // no per-frame window moves. See Walk.swift.
            beginWalk(speed: speed, directionSpec: dir, plannedSeconds: planned)
        } else {
            begin(plan.motion)
            let clipDriven = loaded.pack.states[plan.state]?.duration?.clipDriven ?? false
            scheduler.apply(plan.wake) { [weak self] in
                self?.durationElapsed(clipDriven: clipDriven)
            }
        }
        rearmIdleWatchers()
        syncDisplayLink()
        if pointer.installed { pointer.sample(notify: false) }
        onStateChange?(plan, scheduler)
    }

    // MARK: render-server locomotion

    private var rigHalfWidth: CGFloat { (body?.rigSize.width ?? panel.frame.width) / 2 }
    private var rigHeight: CGFloat { body?.rigSize.height ?? panel.frame.height }

    /// Top-left of the character's cell in screen coordinates, accounting for the
    /// rig's current slide inside a walk-wide window.
    private func cellTopLeftOnScreen() -> CGPoint {
        let scale = CGFloat(displayScale)
        let margin = panel.margin * scale
        // The model position is the end of a render-server walk. Hit testing
        // must use its current presentation position, including while paused.
        let rig = body?.rig
        let rigMinX = (rig?.presentation()?.position.x ?? rig?.position.x ?? rigHalfWidth) - rigHalfWidth
        return CGPoint(x: panel.frame.minX + rigMinX + margin,
                       y: panel.frame.minY + margin
                        + CGFloat(loaded.pack.stage.cell.h) * scale)
    }

    private func beginWalk(speed: Double, directionSpec: String, plannedSeconds: Double) {
        walkSpeed = speed
        walkRemaining = plannedSeconds
        switch directionSpec {
        case "left": walkDirection = .left
        case "right": walkDirection = .right
        case "toPointer": walkDirection = lastPointerSide ?? motion.facing
        case "away": walkDirection = (lastPointerSide ?? .left) == .left ? .right : .left
        default: walkDirection = Bool.random() ? .left : .right
        }
        motion.facing = walkDirection
        if let clip = currentClip { body?.setFacing(walkDirection, clip: clip) }
        motion.begin(.none, in: world)      // deliberately no display link
        startWalkStretch()
    }

    private func startWalkStretch() {
        let w = world
        let width = (screen ?? NSScreen.main)?.frame.width ?? 1440
        guard let stretch = Walk.resolve(from: motion.feet.x, direction: walkDirection,
                                         speed: walkSpeed, remainingSeconds: walkRemaining,
                                         world: w, displayWidth: Double(width)) else {
            // Pinned against the edge it is facing: report and let the pack decide.
            walk = nil
            send("edge.reached", value: walkDirection == .left ? 0 : 1)
            return
        }
        walk = stretch

        // One resize, then the window stays put for the whole stretch.
        panel.layout(feetMinX: CGFloat(stretch.minX), feetMaxX: CGFloat(stretch.maxX),
                     floorY: CGFloat(w.floor), halfWidth: rigHalfWidth,
                     height: rigHeight, groundOffsetFromBottom: groundOffsetFromBottom)

        guard let rig = body?.rig else { return }
        let from = CGFloat(stretch.startX - stretch.minX) + rigHalfWidth
        let to = CGFloat(stretch.endX - stretch.minX) + rigHalfWidth
        let y = rigHeight / 2
        rig.removeAnimation(forKey: "walk")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rig.position = CGPoint(x: to, y: y)     // model value = where it ends up
        CATransaction.commit()

        let slide = CABasicAnimation(keyPath: "position")
        slide.fromValue = NSValue(point: CGPoint(x: from, y: y))
        slide.toValue = NSValue(point: CGPoint(x: to, y: y))
        slide.duration = stretch.seconds
        slide.timingFunction = CAMediaTimingFunction(name: .linear)
        slide.isRemovedOnCompletion = false
        slide.fillMode = .forwards
        rig.add(slide, forKey: "walk")

        // The walk owns the single scheduled wake for its own duration, and hands
        // control back to the Director when the last stretch finishes.
        scheduler.apply(.after(stretch.seconds)) { [weak self] in
            self?.walkStretchFinished()
        }
        if pointer.installed { pointer.sample(notify: false) }
    }

    private func walkStretchFinished() {
        defer { if pointer.installed { pointer.sample(notify: false) } }
        guard let stretch = walk else { return }
        motion.feet.x = stretch.endX
        walkRemaining = stretch.remainingAfter(walkRemaining)

        if stretch.hitEdge {
            walk = nil
            send("edge.reached", value: stretch.direction == .left ? 0 : 1)
        } else if walkRemaining > 0.02 {
            startWalkStretch()              // chain the next stretch
        } else {
            walk = nil
            if let next = director.timeout(context()) { apply(next) }
        }
    }

    /// Freeze an in-flight walk: adopt the interpolated position and put the window
    /// back to its normal size. Called on every transition, so an interrupted walk
    /// leaves the pet where it visibly was, not at the stretch's end.
    private func endWalk() {
        guard let stretch = walk else { return }
        motion.feet.x = stretch.x(at: Date())
        walk = nil
        walkRemaining = 0
        body?.rig.removeAnimation(forKey: "walk")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body?.rig.position = CGPoint(x: rigHalfWidth, y: rigHeight / 2)
        CATransaction.commit()
        panel.layout(feetMinX: CGFloat(motion.feet.x), feetMaxX: CGFloat(motion.feet.x),
                     floorY: CGFloat(world.floor), halfWidth: rigHalfWidth,
                     height: rigHeight, groundOffsetFromBottom: groundOffsetFromBottom)
    }

    /// Resolve which way the character should face and mirror it.
    ///
    /// A walk sets `motion.facing` to its own direction, so `"keep"` in a walking
    /// state naturally means "face the way you are going".
    private func applyFacing(for state: String, clip: Pack.Clip) {
        guard let st = loaded.pack.states[state] else { return }
        switch st.facing {
        case "left":  motion.facing = .left
        case "right": motion.facing = .right
        case "toPointer":
            if let side = lastPointerSide {
                // Face the pointer: if it is to our left, look left.
                motion.facing = side
            }
        default: break        // "keep"
        }
        body?.setFacing(motion.facing, clip: clip)
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

    /// A state's own duration ran out. Give the pack its chance to interrupt on
    /// `state.timeout` - and on `clip.ended` when the duration came from the clip -
    /// before falling through to the weighted `next` list.
    private func durationElapsed(clipDriven: Bool) {
        let ctx = context()
        if let plan = director.deliver(event: "state.timeout", ctx) { apply(plan); return }
        if clipDriven, let plan = director.deliver(event: "clip.ended", ctx) {
            apply(plan); return
        }
        if let next = director.timeout(ctx) { apply(next) }
    }

    /// Re-armed on every state change, so a pet that just did something starts
    /// counting from now rather than inheriting the previous state's clock.
    private func rearmIdleWatchers() {
        if let secs = wants["user.idle"] ?? nil { userIdle.arm(after: secs) }
        else { userIdle.cancel() }
        if let secs = wants["pointer.idle"] ?? nil { pointerIdle.arm(after: secs) }
        else { pointerIdle.cancel() }
    }

    private func send(_ event: String, value: Double? = nil) {
        // pointer.near and pointer.fast arrive on every mouse-move event, and
        // building a guard context reads the calendar. Skip all of it unless the
        // state actually listens for this event.
        guard let st = loaded.pack.states[director.current],
              st.interrupts.contains(where: { $0.on.name == event }) else { return }
        if let plan = director.deliver(event: event, value: value, context()) {
            apply(plan)
        }
    }

    /// Minutes since midnight, recomputed at most once a minute. `Calendar` is not
    /// arithmetic, and this is read from the guard context.
    private nonisolated(unsafe) static var clockCache: (minute: Int, until: CFTimeInterval) = (0, 0)
    private static func minutesSinceMidnight() -> Int {
        let now = CACurrentMediaTime()
        if now < clockCache.until { return clockCache.minute }
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        clockCache = (m, now + 20)
        return m
    }

    private func context() -> Guard.Context {
        var c = Guard.Context()
        c.pointerDistance = lastDistance.isFinite ? lastDistance : nil
        c.pointerSide = lastPointerSide
        c.facing = motion.facing
        c.perched = false
        c.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        c.edge = .floor
        c.minutesSinceMidnight = Self.minutesSinceMidnight()
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
    private var pointerVelocity = PointerVelocity()
    private var lastPointerTime: CFTimeInterval = 0

    private func pointerMoved(_ r: PointerMonitor.Reading) {
        lastDistance = r.distance
        lastPointerSide = r.side

        // Cursor speed comes only from actual mouse events, never a polling timer.
        let now = CACurrentMediaTime()
        if let speed = pointerVelocity.sample(at: NSEvent.mouseLocation, time: now), speed > 1 {
            send("pointer.fast", value: speed)
        }
        lastPointerTime = now
        if let clip = currentClip,
           loaded.pack.states[director.current]?.facing == "toPointer",
           motion.facing != r.side {
            applyFacing(for: director.current, clip: clip)
            pointer.sample(notify: false)
        }
        if r.inside != wasInside {
            wasInside = r.inside
            send(r.inside ? "pointer.enter" : "pointer.exit")
        }
        send("pointer.near", value: r.distance)
    }

    private func atlas(named: String) -> CGImage? {
        if let a = atlases[named] { return a }
        guard let tex = loaded.pack.textures[named],
              let url = try? PackFiles.file(tex.file, in: loaded.root),
              let img = SpriteLayer.atlas(at: url)
        else { return nil }
        atlases[named] = img
        return img
    }
}

/// Clicks only reach here while `ignoresMouseEvents` is false, which the pointer
/// monitor flips based on the alpha mask - so a click on a transparent pixel goes
/// to whatever is behind the pet, as it should.
public final class ClickForwardingView: NSView {
    public var onClick: ((Int) -> Void)?
    public var onDragBegin: ((CGPoint) -> Void)?
    public var onDrag: ((CGPoint) -> Void)?
    public var onDragEnd: (() -> Void)?
    private var dragging = false
    private var downPoint = CGPoint.zero
    private var clickCount = 0

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func mouseDown(with event: NSEvent) {
        dragging = false
        downPoint = NSEvent.mouseLocation
        clickCount = event.clickCount
    }
    public override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        if !dragging { dragging = true; onDragBegin?(downPoint) }
        onDrag?(p)
    }
    public override func mouseUp(with event: NSEvent) {
        if dragging { dragging = false; onDragEnd?() }
        else { onClick?(clickCount) }
    }
}
