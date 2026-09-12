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
    private var walk: Walk?
    private var walkRemaining: Double = 0
    private var walkSpeed: Double = 0
    private var walkDirection: Guard.Side = .left

    // MARK: perching
    //
    // Off by default, so the app ships asking for nothing. See CLAUDE.md 4a.
    public var perchMode = false
    public let perchTracker = PerchTracker()
    public let systemEvents = SystemEvents()
    /// One for system-wide input, one for the cursor specifically.
    public let userIdle = IdleWatcher()
    public lazy var pointerIdle = IdleWatcher { [weak self] in
        guard let t = self?.lastPointerTime, t > 0 else { return 0 }
        return CACurrentMediaTime() - t
    }
    private var wants: [String: Double?] = [:]
    private var perchedOn: Perch.Candidate?
    public var isPerched: Bool { perchedOn != nil }

    /// Does the loaded pack want perching at all? A pack that never declares the
    /// capability behaves identically whether the mode is on or off, because
    /// `perch.acquired` simply never fires for it.
    public var packSupportsPerching: Bool {
        loaded.pack.requires.contains("windowEdges")
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
        // cellTopLeft is wired in start(), once the rig exists.
        self.pointer.currentMask = { [weak self] in
            guard let self, let clip = self.currentClip,
                  let m = self.masks[clip.texture] else { return nil }
            return (m, self.visibleCell(of: clip))
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
        if let perch = perchedOn {
            // Perched: the walkable surface is the top edge of that one window.
            w = Perch.surface(of: perch.bounds,
                              screenHeight: WindowFinder.primaryScreenHeight,
                              halfWidth: halfWidth)
        } else {
            let s = screen ?? Stage.screen(containing: motion.feet) ?? NSScreen.main
            w = s.map { Stage.world(on: $0, halfWidth: halfWidth) }
             ?? Motion.World(floor: 0, left: 0, right: 0)
        }
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
        // Install the pointer monitor only if some state actually reacts to it.
        if packUsesPointer { pointer.install() }

        // Observers only for what the pack asks for.
        wants = loaded.pack.requestedEvents
        var w: SystemEvents.Wants = []
        if wants["system.wake"] != nil || wants["system.willSleep"] != nil { w.insert(.sleepWake) }
        if wants["power.lowPowerMode"] != nil || wants["power.onBattery"] != nil { w.insert(.power) }
        if wants["display.changed"] != nil { w.insert(.displays) }
        if wants["space.changed"] != nil { w.insert(.space) }
        // Occlusion always earns its place: it lets the engine stop animating behind
        // another window whether or not the pack asked to hear about it.
        w.insert(.occlusion)
        systemEvents.onEvent = { [weak self] name, value in self?.send(name, value: value) }
        systemEvents.onOcclusionChanged = { [weak self] hidden in
            self?.body?.setPaused(hidden)
        }
        systemEvents.install(w, window: panel)

        userIdle.onIdle = { [weak self] secs in self?.send("user.idle", value: secs) }
        pointerIdle.onIdle = { [weak self] secs in self?.send("pointer.idle", value: secs) }
        pointer.onChange = { [weak self] r in self?.pointerMoved(r) }
        pointer.cellTopLeft = { [weak self] in self?.cellTopLeftOnScreen() ?? .zero }
        perchTracker.onMoved = { [weak self] c in self?.perchMoved(to: c) }
        perchTracker.onLost = { [weak self] in self?.perchLost() }
        apply(director.start())
    }

    public func stop() {
        scheduler.cancel()
        userIdle.cancel()
        pointerIdle.cancel()
        systemEvents.uninstall()
        perchTracker.detach()
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

        let wasSettled = body?.springsSettled ?? true
        var settled = true
        timed("stepSprings") { settled = body?.stepSprings(dt) ?? true }
        if settled && !wasSettled { send("physics.settled") }
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
        endWalk()                       // adopt the position of any walk in flight
        body?.apply(state: plan.state, bodyClip: clip)
        cachedWorld = nil

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
        onStateChange?(plan, scheduler)
    }

    // MARK: render-server locomotion

    private var rigHalfWidth: CGFloat { (body?.rigSize.width ?? panel.frame.width) / 2 }
    private var rigHeight: CGFloat { body?.rigSize.height ?? panel.frame.height }

    /// Top-left of the character's cell in screen coordinates, accounting for the
    /// rig's current slide inside a walk-wide window.
    private func cellTopLeftOnScreen() -> CGPoint {
        let scale = CGFloat(loaded.pack.stage.defaultScale)
        let margin = panel.margin * scale
        let rigMinX = (body?.rig.position.x ?? rigHalfWidth) - rigHalfWidth
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
    }

    private func walkStretchFinished() {
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
        c.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        c.perched = isPerched
        c.edge = isPerched ? .windowTop : .floor
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
        // The drop is the perch selection. Enumerate windows exactly here - once,
        // inside a user interaction - and never on a timer.
        if tryPerch(at: NSEvent.mouseLocation) { return }
        send("pointer.release")
    }

    /// Returns true if the pet took a perch, in which case `perch.acquired` was
    /// sent instead of `pointer.release`.
    @discardableResult
    private func tryPerch(at cursor: CGPoint) -> Bool {
        guard perchMode, packSupportsPerching else { return false }
        let h = WindowFinder.primaryScreenHeight
        guard let target = Perch.target(under: cursor, in: WindowFinder.windows(),
                                        ownPID: ProcessInfo.processInfo.processIdentifier,
                                        screenHeight: h) else { return false }
        switch perchTracker.attach(to: target) {
        case .attached:
            perchedOn = target
            cachedWorld = nil
            let w = world
            motion.feet = CGPoint(x: min(max(motion.feet.x, w.left), w.right), y: w.floor)
            syncWindow()
            send("perch.acquired")
            return true
        case .needsPermission:
            // Ask now, with the user having just aimed at a specific window, rather
            // than at launch for no visible reason. The pet falls this time.
            PerchTracker.requestPermission()
            return false
        case .notFound:
            return false
        }
    }

    private func perchMoved(to c: Perch.Candidate) {
        perchedOn = c
        cachedWorld = nil
        guard walk == nil else { endWalk(); return }   // re-seat, then let the state re-plan
        let w = world
        motion.feet = CGPoint(x: min(max(motion.feet.x, w.left), w.right), y: w.floor)
        syncWindow()
    }

    /// One handler for every way a perch can go away: the window moved off-screen,
    /// was minimised, hidden, closed, resized too small, or went full screen.
    private func perchLost() {
        guard perchedOn != nil else { return }
        endWalk()
        perchedOn = nil
        cachedWorld = nil
        send("perch.lost")
    }

    /// Turn window perching on or off. Dropping the perch is a `perch.lost`, so the
    /// pack's own fall-and-land states bring the pet back to the floor.
    public func setPerchMode(_ on: Bool) {
        perchMode = on
        if !on { perchTracker.detach(); perchLost() }
    }

    private var lastPointerSide: Guard.Side?
    private var lastPointerPoint: CGPoint?
    private var lastPointerTime: CFTimeInterval = 0

    private func pointerMoved(_ r: PointerMonitor.Reading) {
        lastDistance = r.distance
        lastPointerSide = r.side

        // Cursor speed, derived from events we are already handling. No sampling.
        let now = CACurrentMediaTime()
        let here = NSEvent.mouseLocation
        if let last = lastPointerPoint, lastPointerTime > 0 {
            let dt = now - lastPointerTime
            if dt > 0.004 {
                let d = ((here.x - last.x) * (here.x - last.x)
                       + (here.y - last.y) * (here.y - last.y)).squareRoot()
                let speed = d / dt
                if speed > 1 { send("pointer.fast", value: speed) }
            }
        }
        lastPointerPoint = here
        lastPointerTime = now
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
    public var onClick: ((Int) -> Void)?
    public var onDragBegin: ((CGPoint) -> Void)?
    public var onDrag: ((CGPoint) -> Void)?
    public var onDragEnd: (() -> Void)?
    private var dragging = false

    public override func mouseDown(with event: NSEvent) {
        dragging = false
        onClick?(event.clickCount)
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
