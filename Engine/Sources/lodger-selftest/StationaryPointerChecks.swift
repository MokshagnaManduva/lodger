import AppKit
import LodgerEngine

func runStationaryPointerChecks() throws {
    section("stationary cursor — animation-driven routing")
    func clip(_ loop: String, frames: String = "{\"cell\":0,\"ms\":100},{\"cell\":1,\"ms\":200},{\"cell\":2,\"ms\":300}") throws -> Pack.Clip {
        try JSONDecoder().decode(Pack.Clip.self, from: Data("{\"texture\":\"body\",\"loop\":\"\(loop)\",\"frames\":[\(frames)]}".utf8))
    }
    let forever = ClipTimeline(clip: try clip("forever"), defaultFrameMs: 250)
    check(forever.sample(at: 0.05).index == 0 && near(forever.sample(at: 0.05).nextBoundary!, 0.05), "unequal frame holds share the rendering clock")
    check(forever.sample(at: 0.15).index == 1 && forever.sample(at: 0.65).index == 0, "loop wraps to first frame")
    check(near(forever.nextChange(at: 0.05, values: [false, false, true])!, 0.25), "skip boundaries with unchanged opacity")
    check(forever.nextChange(at: 0.05, values: [true, true, true]) == nil, "constant opaque pixel schedules no wake")
    check(forever.nextChange(at: 0.05, values: [false, false, false]) == nil, "constant transparent pixel schedules no wake")
    let finite = ClipTimeline(clip: try clip("none"), defaultFrameMs: 250)
    check(finite.sample(at: 0.4).index == 2 && finite.sample(at: 0.4).nextBoundary == nil, "finite clip holds its final frame without another wake")
    check(finite.nextChange(at: 5, values: [false, false, true]) == nil, "finished finite clip does not restart a routing timer")
    let pingpong = ClipTimeline(clip: try clip("pingpong"), defaultFrameMs: 250)
    check(pingpong.sample(at: 0.7).index == 2 && pingpong.sample(at: 0.95).index == 1, "ping-pong uses reversed authored frame durations")
    check(near(pingpong.sample(at: 0.4).nextBoundary!, 0.5), "ping-pong skips unchanged turnaround frame")
    check(near(pingpong.nextChange(at: 1.15, values: [false, true, false])!, 0.15), "ping-pong first frame spans loop seam")
    let single = ClipTimeline(clip: try clip("forever", frames: "{\"cell\":0}"), defaultFrameMs: 250)
    check(single.sample(at: 100).nextBoundary == nil, "single-frame clip has no animation wake")

    // No mouse events are generated here: the fixed test cursor stays on one
    // pixel while the real routing scheduler advances both masks and window flag.
    let panel = PetPanel(cellSize: CGSize(width: 4, height: 4), scale: 2)
    panel.setFrame(CGRect(x: 200, y: 200, width: 8, height: 8), display: false)
    let monitor = PointerMonitor(panel: panel)
    var cursor = CGPoint(x: 203, y: 205)
    monitor.cursorLocation = { cursor }
    monitor.scale = 2
    monitor.cellTopLeft = { CGPoint(x: 200, y: 208) }
    let mask = try HitMask(data: encodeMask([
        [Bool](repeating: false, count: 16),
        [Bool](repeating: true, count: 16),
        [Bool](repeating: false, count: 16)
    ], 4, 4))
    let animation = try clip("none")
    let timeline = ClipTimeline(clip: animation, defaultFrameMs: 250)
    let began = CACurrentMediaTime()
    monitor.hitTargets = { [.init(mask: mask, cell: timeline.sample(at: CACurrentMediaTime() - began).index, offset: .zero)] }
    monitor.animationUpdate = { _ in
        timeline.nextChange(at: CACurrentMediaTime() - began, values: [false, true, false]).map { .after($0) } ?? .none
    }
    var callbacks = 0
    monitor.onChange = { _ in callbacks += 1 }
    monitor.install(observeSystemEvents: false)
    defer { monitor.uninstall() }
    func runUntil(_ elapsed: Double) {
        while CACurrentMediaTime() - began < elapsed {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        }
    }
    check(panel.ignoresMouseEvents && monitor.hasAnimationTimer, "transparent frame arms the next opaque boundary without moving the cursor")
    runUntil(0.16)
    check(!panel.ignoresMouseEvents && monitor.isOverSilhouette, "unmoving cursor becomes clickable when opaque frame arrives")
    runUntil(0.36)
    check(panel.ignoresMouseEvents && !monitor.isOverSilhouette, "unmoving cursor becomes click-through when opaque frame leaves")
    check(callbacks == 1 && monitor.animationRefreshCount == 2, "boundary refreshes do not synthesize movement or pointer reactions")
    check(!monitor.hasAnimationTimer && !monitor.hasRoutingDisplayLink, "finite animation leaves no routing wake behind")

    var opaque = true
    monitor.hitTargets = { [.init(mask: mask, cell: opaque ? 1 : 0, offset: .zero)] }
    monitor.animationUpdate = { _ in .after(0.02) }
    monitor.sample(notify: false)
    cursor = CGPoint(x: 500, y: 500)
    monitor.sample(notify: false)
    check(!monitor.hasAnimationTimer && !monitor.hasRoutingDisplayLink && panel.ignoresMouseEvents, "leaving the panel cancels all routing work")
    cursor = CGPoint(x: 203, y: 205)
    monitor.sample(notify: false)
    func event(_ type: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                          windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
    }
    monitor.handle(event(.leftMouseDown), deliveredToPanel: true)
    opaque = false
    monitor.sample(notify: false)
    check(monitor.hasCapturedPress && !panel.ignoresMouseEvents && !monitor.hasAnimationTimer, "animation cannot steal a pet-owned press/drag")
    monitor.handle(event(.leftMouseUp), deliveredToPanel: true)
    check(!monitor.hasCapturedPress && panel.ignoresMouseEvents, "release immediately restores current silhouette routing")
    monitor.handle(event(.leftMouseDown), deliveredToPanel: false)
    check(!monitor.hasCapturedPress, "press targeted to another app is never captured")
    monitor.animationUpdate = { _ in .continuous }
    monitor.sample(notify: false)
    check(monitor.hasRoutingDisplayLink && !monitor.hasAnimationTimer, "continuous hover geometry uses one scoped display link")
    monitor.animationUpdate = { _ in .none }
    monitor.sample(notify: false)
    check(!monitor.hasRoutingDisplayLink && !monitor.hasAnimationTimer, "paused/static geometry cancels the hover link")
    monitor.animationUpdate = { _ in .after(0.01) }
    monitor.sample(notify: false)
    let refreshes = monitor.animationRefreshCount
    monitor.uninstall()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
    check(!monitor.hasAnimationTimer && !monitor.hasRoutingDisplayLink && monitor.animationRefreshCount == refreshes && panel.ignoresMouseEvents, "uninstall cancels pending callbacks and clears routing")

    let loaded = try PackStore(searchPaths: []).load(root: fixtures.appendingPathComponent("build/socketed.pack"))
    let body = Body(pack: loaded.pack, host: CALayer(), atlas: { name in
        guard let texture = loaded.pack.textures[name] else { return nil }
        return SpriteLayer.atlas(at: loaded.root.appendingPathComponent(texture.file))
    })
    let bodyClip = loaded.pack.clips[loaded.pack.states[loaded.pack.initialState]!.clip]!
    body.apply(state: loaded.pack.initialState, bodyClip: bodyClip)
    body.setPaused(true)
    let stopped = body.animationElapsed
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025))
    check(near(body.animationElapsed, stopped, 0.0001), "routing animation clock freezes with the renderer")
    check(body.routingUpdate(cursor: CGPoint(x: 10, y: 10), masks: [:]) == .none, "paused body asks for no routing work")
    body.setPaused(false)
    check(near(body.animationElapsed, stopped, 0.01), "resume continues frozen clock instead of jumping frames")
}
