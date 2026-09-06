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
    }

    private func installClickView() -> ClickForwardingView {
        let v = ClickForwardingView(frame: panel.contentView?.bounds ?? .zero)
        v.wantsLayer = true
        v.layer?.backgroundColor = .clear
        panel.contentView = v
        return v
    }

    // MARK: lifecycle

    public func start() {
        for (name, tex) in loaded.pack.textures where tex.preload {
            _ = atlas(named: name)
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

    /// The one place a per-frame callback can appear. It is created when a float
    /// is in motion and torn down the instant every spring settles, so an idle pet
    /// has no display link at all.
    private func syncDisplayLink() {
        guard let body else { return }
        if body.springsSettled { stopLink() } else { startLink() }
    }

    private func startLink() {
        guard link == nil, let view = panel.contentView else { return }
        let l = view.displayLink(target: self, selector: #selector(tickSprings))
        lastLinkTime = 0
        l.add(to: .main, forMode: .common)
        link = l
        linkStarts += 1
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    @objc private func tickSprings(_ sender: CADisplayLink) {
        guard let body else { return }
        springTicks += 1
        let dt = lastLinkTime == 0 ? 1.0 / 60.0 : sender.targetTimestamp - lastLinkTime
        lastLinkTime = sender.targetTimestamp
        if body.stepSprings(dt) { stopLink() }
    }

    /// Call when the window moves so followers trail instead of teleporting.
    public func windowMoved(by delta: CGVector) {
        body?.displaceFloats(by: delta)
        syncDisplayLink()
    }

    public var hasDisplayLink: Bool { link != nil }

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
        syncDisplayLink()

        scheduler.apply(plan.wake) { [weak self] in
            guard let self else { return }
            if let next = self.director.timeout(self.context()) { self.apply(next) }
        }
        onStateChange?(plan, scheduler)
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

    private func pointerMoved(_ r: PointerMonitor.Reading) {
        lastDistance = r.distance
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
    public override func mouseDown(with event: NSEvent) { onClick?() }
}
