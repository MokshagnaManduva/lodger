import AppKit
import Foundation
import LodgerEngine

// Engine self-tests. A plain executable rather than XCTest, because Command Line
// Tools ships neither XCTest nor swift-testing - so this runs on a bare toolchain
// and needs no Xcode in CI.

var failures = 0, checks = 0

func check(_ ok: Bool, _ what: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if ok { print("  PASS  \(what)") }
    else {
        failures += 1
        print("  FAIL  \(what)")
        let d = detail(); if !d.isEmpty { print("        \(d)") }
    }
}
func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }
func section(_ s: String) { print("\n\(s)") }

func encodeMask(_ cells: [[Bool]], _ w: Int, _ h: Int) -> Data {
    func varint(_ n: Int) -> [UInt8] {
        var n = n, out: [UInt8] = []
        repeat { var b = UInt8(n & 0x7F); n >>= 7; if n != 0 { b |= 0x80 }; out.append(b) }
        while n != 0
        return out
    }
    var d = Array("LMSK".utf8) + [1]
    d += varint(w) + varint(h) + varint(cells.count)
    for flat in cells {
        var runs: [Int] = []; var cur = false; var n = 0
        for v in flat { if v == cur { n += 1 } else { runs.append(n); cur = v; n = 1 } }
        runs.append(n)
        d += varint(runs.count)
        for r in runs { d += varint(r) }
    }
    return Data(d)
}

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fixtures = repoRoot.appendingPathComponent("Tests/Fixtures")

// ---------------------------------------------------------------- pack model
section("pack model")
do {
    let store = PackStore(searchPaths: [fixtures])
    let loaded = try store.load(root: fixtures.appendingPathComponent("test.solidsquare"))
    let p = loaded.pack
    check(p.identity.id == "test.solidsquare", "minimum viable pack decodes")
    check(p.textures.count == 1 && p.clips.count == 1 && p.states.count == 1,
          "one texture, one clip, one state")
    check(p.states["resting"]?.quiescent == true, "quiescent flag decodes")
    check(p.stage.defaultScale == 2 && p.stage.scaleSteps == [1, 2, 3],
          "stage defaults applied when absent from the file")
} catch { check(false, "minimum viable pack decodes", "\(error)") }

do {
    let root = fixtures.appendingPathComponent("build/socketed.pack")
    if FileManager.default.fileExists(atPath: root.path) {
        let store = PackStore(searchPaths: [root.deletingLastPathComponent()])
        let loaded = try store.load(root: root)
        let wave = loaded.pack.clips["wave"]!
        check(wave.frames.count == 4, "built pack: clip frames survive the build")
        check(wave.frames.allSatisfy { $0.anchors["hand"] != nil },
              "built pack: every frame carries its injected anchor")
        let mask = try store.hitMask(for: loaded, texture: "body")
        check(mask?.count == 4 && mask?.cellWidth == 20, "built pack: hit masks load")
        check((mask?.opaqueCount(cell: 0) ?? 0) > 0, "built pack: masks are non-empty")
    } else {
        print("  SKIP  built pack (run: packtool build Tests/Fixtures/src.socketed)")
    }
} catch { check(false, "built pack loads", "\(error)") }

// Rule 1, structurally.
section("Rule 1 — bundled and installed packs share one code path")
do {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("lodger-shadow-\(UUID().uuidString)")
    let bundled = tmp.appendingPathComponent("bundled")
    let user = tmp.appendingPathComponent("user")
    defer { try? FileManager.default.removeItem(at: tmp) }
    // Copy the whole pack, not just the manifest: PackStore.load verifies that every
    // referenced texture, mask and sound actually exists, because a pack that decodes
    // but has no art renders an invisible character with no explanation.
    let src = fixtures.appendingPathComponent("test.solidsquare")
    for d in [bundled, user] {
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: src, to: d.appendingPathComponent("test.solidsquare"))
    }
    let manifest = user.appendingPathComponent("test.solidsquare/pack.json")
    let original = try String(contentsOf: manifest, encoding: .utf8)
    try original.replacingOccurrences(of: "\"name\": \"Solid Square\"",
                                      with: "\"name\": \"User Override\"")
        .write(to: manifest, atomically: true, encoding: .utf8)

    let found = PackStore.standard(bundled: bundled, applicationSupport: user).discover()
    check(found.count == 1, "same id collapses to one entry", "got \(found.count)")
    check(found.first?.pack.identity.name == "User Override",
          "a user pack shadows a bundled pack with the same id",
          "got \(found.first?.pack.identity.name ?? "nothing")")
} catch { check(false, "shadowing", "\(error)") }

// ------------------------------------------------------------- sprite layer
section("sprite layer — the render-server mechanism")
// Cells are numbered row-major from the top; contentsRect's origin is bottom-left,
// so the row index flips. Verified against real rendering further down.
let topRow = SpriteLayer.contentsRect(cell: 1, columns: 4, rows: 2)   // row 0, col 1
check(near(topRow.origin.x, 0.25) && near(topRow.origin.y, 0.5)
      && near(topRow.width, 0.25) && near(topRow.height, 0.5),
      "contentsRect: top-row cell maps to the upper half", "got \(topRow)")
let bottomRow = SpriteLayer.contentsRect(cell: 5, columns: 4, rows: 2)  // row 1, col 1
check(near(bottomRow.origin.x, 0.25) && near(bottomRow.origin.y, 0.0),
      "contentsRect: bottom-row cell maps to the lower half", "got \(bottomRow)")

let times = SpriteLayer.keyTimes(durationsMs: [100, 300, 100, 100])
check(times.count == 5, "discrete keyTimes has one more entry than values",
      "got \(times.count) for 4 frames")
check(near(times[0].doubleValue, 0) && near(times.last!.doubleValue, 1),
      "keyTimes span 0...1")
check(near(times[1].doubleValue, 100.0/600.0) && near(times[2].doubleValue, 400.0/600.0),
      "keyTimes follow per-frame ms, not a uniform rate")

func decodeClip(_ s: String) -> Pack.Clip {
    try! JSONDecoder().decode(Pack.Clip.self, from: Data(s.utf8))
}
func decodeTex(_ s: String) -> Pack.Texture {
    try! JSONDecoder().decode(Pack.Texture.self, from: Data(s.utf8))
}

// Rule 2 at its sharpest.
let staticLayer = CALayer()
let staticResult = SpriteLayer.install(
    clip: decodeClip(#"{"texture":"t","loop":"forever","frames":[{"cell":3,"ms":1000}]}"#),
    texture: decodeTex(#"{"file":"a.png","columns":4,"rows":2}"#),
    defaultFrameMs: 250, into: staticLayer)
check(!staticResult.animated && staticLayer.animation(forKey: "sprite") == nil,
      "a single-frame clip installs NO animation at all")
check(near(staticLayer.contentsRect.origin.x, 0.75),
      "static frame still points at the right cell")

let animLayer = CALayer()
let animResult = SpriteLayer.install(
    clip: decodeClip(#"""
    {"texture":"t","loop":"forever","frames":[{"cell":0,"ms":200},{"cell":1,"ms":200},{"cell":2,"ms":200}]}
    """#),
    texture: decodeTex(#"{"file":"a.png","columns":3,"rows":1}"#),
    defaultFrameMs: 250, into: animLayer)
let anim = animLayer.animation(forKey: "sprite") as? CAKeyframeAnimation
check(animResult.animated && anim != nil, "a multi-frame clip installs a keyframe animation")
check(anim?.keyPath == "contentsRect", "animates contentsRect, not position or opacity")
check(anim?.calculationMode == .discrete, "calculationMode is discrete — no interpolation")
check(anim?.values?.count == 3 && anim?.keyTimes?.count == 4, "3 values, 4 keyTimes")
check(near(anim?.duration ?? 0, 0.6), "duration is the sum of frame durations")
check(anim?.repeatCount == .infinity, "a forever clip repeats forever")
check(animLayer.magnificationFilter == .nearest, "nearest-neighbour magnification")

// Settle the contentsRect origin empirically instead of assuming it.
section("contentsRect origin — measured, not assumed")
do {
    let cw = 8, ch = 8, cols = 2, rows = 2
    let colours: [[UInt8]] = [[220, 40, 40], [40, 200, 40], [40, 60, 220], [230, 210, 60]]
    // Each cell also carries a white band across its TOP half, so this test can
    // tell a wrong row index apart from a vertically flipped image.
    let band: [UInt8] = [250, 250, 250]
    var px = [UInt8](repeating: 0, count: cw * cols * ch * rows * 4)
    for y in 0..<(ch * rows) {
        for x in 0..<(cw * cols) {
            let idx = (y / ch) * cols + (x / cw), o = (y * cw * cols + x) * 4
            let topHalf = (y % ch) < ch / 2
            let c = topHalf ? band : colours[idx]
            px[o] = c[0]; px[o+1] = c[1]; px[o+2] = c[2]; px[o+3] = 255
        }
    }
    let space = CGColorSpaceCreateDeviceRGB()
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let atlas = CGImage(width: cw * cols, height: ch * rows, bitsPerComponent: 8,
                        bitsPerPixel: 32, bytesPerRow: cw * cols * 4, space: space,
                        bitmapInfo: info, provider: CGDataProvider(data: Data(px) as CFData)!,
                        decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    for cell in 0..<4 {
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: cw, height: ch)
        layer.contents = atlas
        layer.magnificationFilter = .nearest
        layer.contentsRect = SpriteLayer.contentsRect(cell: cell, columns: cols, rows: rows)
        var out = [UInt8](repeating: 0, count: cw * ch * 4)
        let ctx = CGContext(data: &out, width: cw, height: ch, bitsPerComponent: 8,
                            bytesPerRow: cw * 4, space: space, bitmapInfo: info.rawValue)!
        layer.render(in: ctx)
        func sample(row: Int) -> [Int] {
            let o = (row * cw + cw / 2) * 4
            return [Int(out[o]), Int(out[o+1]), Int(out[o+2])]
        }
        // memory row 0 is the top of the produced raster
        let top = sample(row: 1), bottom = sample(row: ch - 2)
        let wantBottom = colours[cell].map(Int.init)
        let matches = { (a: [Int], b: [Int]) in zip(a, b).allSatisfy { abs($0 - $1) <= 12 } }
        check(matches(bottom, wantBottom), "cell \(cell) selects cell \(cell)",
              "lower half rendered \(bottom), expected \(wantBottom). Swapped cells mean "
              + "contentsRect's row origin is wrong.")
        check(matches(top, band.map(Int.init)), "cell \(cell) is not vertically flipped",
              "upper half rendered \(top), expected the white band \(band.map(Int.init)). "
              + "The band belongs at the top; finding it at the bottom means the whole "
              + "image is flipped, not just the row index.")
    }
}

// ------------------------------------------------------------------ hit mask
section("hit mask")
do {
    var a = [Bool](repeating: false, count: 16); a[5] = true; a[6] = true; a[10] = true
    let mask = try HitMask(data: encodeMask([a, [Bool](repeating: true, count: 16)], 4, 4))
    check(mask.count == 2, "two cells decode")
    check(mask.opaque(cell: 0, x: 1, y: 1), "opaque pixel reads opaque")
    check(!mask.opaque(cell: 0, x: 0, y: 0), "transparent pixel reads transparent")
    check(mask.opaqueCount(cell: 0) == 3 && mask.opaqueCount(cell: 1) == 16, "counts match")
    check(!mask.opaque(cell: 0, x: -1, y: 0) && !mask.opaque(cell: 0, x: 99, y: 0)
          && !mask.opaque(cell: 7, x: 0, y: 0),
          "out-of-range reads are transparent, not a crash")
} catch { check(false, "hit mask round trip", "\(error)") }

var rejected = 0
for bad in [Data("NOPE\u{01}".utf8), Data(), Data("LMSK".utf8)] {
    if (try? HitMask(data: bad)) == nil { rejected += 1 }
}
check(rejected == 3, "garbage mask data is rejected, not misread", "rejected \(rejected)/3")

// ------------------------------------------------------------------- guards
section("guard vocabulary — closed by construction")
func decodeGuard(_ j: String) -> Guard? {
    try? JSONDecoder().decode(Guard.self, from: Data(j.utf8))
}
check(decodeGuard(#"{"random":0.5}"#) != nil, "random decodes")
check(decodeGuard(#"{"all":[{"lowPower":true},{"perched":false}]}"#) != nil, "all decodes")
check(decodeGuard(#"{"not":{"facing":"left"}}"#) != nil, "not decodes")
check(decodeGuard(#"{"timeOfDay":{"from":"23:00","to":"06:00"}}"#) != nil, "timeOfDay decodes")
check(decodeGuard(#"{"eval":"mascot.environment.cursor.y < 100"}"#) == nil,
      "an expression-language guard is REJECTED")
check(decodeGuard(#"{"telepathy":1}"#) == nil, "an unknown guard is REJECTED")
check(decodeGuard(#"{"random":0.5,"lowPower":true}"#) == nil,
      "a two-key guard object is REJECTED")
check(decodeGuard(#"{"timeOfDay":{"from":"25:00","to":"06:00"}}"#) == nil,
      "an out-of-range clock time is REJECTED")

var gctx = Guard.Context()
gctx.lowPower = true; gctx.facing = .right; gctx.stateAge = 12
let alwaysHalf = { 0.5 }
check(decodeGuard(#"{"lowPower":true}"#)!.evaluate(gctx, random: alwaysHalf), "lowPower true")
check(!decodeGuard(#"{"facing":"left"}"#)!.evaluate(gctx, random: alwaysHalf), "facing mismatch")
check(decodeGuard(#"{"stateAge":{"op":"gt","sec":10}}"#)!.evaluate(gctx, random: alwaysHalf),
      "stateAge comparison")
check(!decodeGuard(#"{"pointerDistance":{"op":"lt","px":40}}"#)!.evaluate(gctx, random: alwaysHalf),
      "pointerDistance with no pointer fails closed, rather than passing silently")
check(decodeGuard(#"{"all":[{"lowPower":true},{"facing":"right"}]}"#)!
        .evaluate(gctx, random: alwaysHalf), "all")
check(decodeGuard(#"{"any":[{"lowPower":false},{"facing":"right"}]}"#)!
        .evaluate(gctx, random: alwaysHalf), "any")
check(decodeGuard(#"{"not":{"lowPower":false}}"#)!.evaluate(gctx, random: alwaysHalf), "not")

// A window that wraps past midnight is the common case for a sleep schedule.
let night = decodeGuard(#"{"timeOfDay":{"from":"23:00","to":"06:00"}}"#)!
for (mins, want, label) in [(23*60+30, true, "23:30 is inside 23:00-06:00"),
                            (2*60, true, "02:00 is inside"),
                            (12*60, false, "12:00 is outside"),
                            (22*60, false, "22:00 is outside")] {
    var c = Guard.Context(); c.minutesSinceMidnight = mins
    check(night.evaluate(c, random: alwaysHalf) == want, label)
}

// ----------------------------------------------------------------- director
section("director — pure, seedable, no timers")
let directorJSON = #"""
{"format":1,
 "identity":{"id":"test.director","name":"D","version":"1.0.0","author":"t","license":"CC0-1.0"},
 "stage":{"cell":{"w":8,"h":8},"bodyHeight":8,"ground":{"x":4,"y":8},"defaultFrameMs":100},
 "textures":{"t":{"file":"a.png","columns":2,"rows":1}},
 "clips":{"loop":{"texture":"t","loop":"forever","frames":[{"cell":0},{"cell":1}]},
          "once":{"texture":"t","loop":"none","frames":[{"cell":0,"ms":300}]}},
 "parts":[{"name":"body","bind":{"mode":"body"}}],
 "initialState":"idle",
 "states":{
   "idle":{"clip":"loop","duration":{"minMs":1000,"maxMs":1000},
     "next":[{"state":"a","weight":1},{"state":"b","weight":3}],
     "interrupts":[
       {"on":{"pointer.near":60},"state":"near"},
       {"on":"pointer.click","state":"a","when":{"lowPower":true}},
       {"on":"pointer.click","state":"b"}]},
   "a":{"clip":"once","next":[{"state":"idle","weight":1}]},
   "b":{"clip":"once","next":[{"state":"idle","weight":1}]},
   "near":{"clip":"once","next":[{"state":"idle","weight":1}]},
   "asleep":{"clip":"loop","quiescent":true,
     "interrupts":[{"on":"pointer.click","state":"idle"}]}}}
"""#
do {
    let dpack = try JSONDecoder().decode(Pack.self, from: Data(directorJSON.utf8))
    let d = Director(pack: dpack, seed: 42)
    let start = d.start()
    check(start.state == "idle" && start.wake == .after(1.0),
          "a state with a duration asks for exactly one wake", "got \(start.wake)")

    let sleepPlan = d.enter("asleep", reason: "test")
    check(sleepPlan.quiescent && sleepPlan.wake == .none,
          "a quiescent state asks for NO wake at all", "got \(sleepPlan.wake)")

    _ = d.enter("a", reason: "test")
    let finite = d.start
    _ = finite
    let aPlan = d.enter("a", reason: "test")
    check(aPlan.wake == .after(0.3),
          "a finite clip with no duration ends when the clip ends", "got \(aPlan.wake)")

    // Weighted selection: b is weighted 3:1 over a, and must be reproducible.
    var counts: [String: Int] = [:]
    let sampler = Director(pack: dpack, seed: 7)
    for _ in 0..<400 {
        _ = sampler.enter("idle", reason: "t")
        if let p = sampler.timeout(Guard.Context()) { counts[p.state, default: 0] += 1 }
    }
    let ratio = Double(counts["b"] ?? 0) / Double(max(1, counts["a"] ?? 1))
    check(ratio > 2.2 && ratio < 4.2, "weights are honoured (b:a about 3:1)",
          "got \(counts) ratio \(String(format: "%.2f", ratio))")

    let replay = Director(pack: dpack, seed: 7)
    var second: [String] = []
    for _ in 0..<400 {
        _ = replay.enter("idle", reason: "t")
        if let p = replay.timeout(Guard.Context()) { second.append(p.state) }
    }
    let replay2 = Director(pack: dpack, seed: 7)
    var third: [String] = []
    for _ in 0..<400 {
        _ = replay2.enter("idle", reason: "t")
        if let p = replay2.timeout(Guard.Context()) { third.append(p.state) }
    }
    check(second == third, "the same seed replays the same personality exactly")

    // Interrupt priority is declaration order, so a pack reads top to bottom.
    let d2 = Director(pack: dpack, seed: 1)
    _ = d2.enter("idle", reason: "t")
    var lowCtx = Guard.Context(); lowCtx.lowPower = true
    check(d2.deliver(event: "pointer.click", lowCtx)?.state == "a",
          "the first matching interrupt whose guard passes wins")
    _ = d2.enter("idle", reason: "t")
    check(d2.deliver(event: "pointer.click", Guard.Context())?.state == "b",
          "a failed guard falls through to the next interrupt")

    // Parameterised events are thresholds, and the direction differs by event.
    _ = d2.enter("idle", reason: "t")
    check(d2.deliver(event: "pointer.near", value: 30, Guard.Context())?.state == "near",
          "pointer.near fires when the cursor is closer than the threshold")
    _ = d2.enter("idle", reason: "t")
    check(d2.deliver(event: "pointer.near", value: 900, Guard.Context()) == nil,
          "pointer.near does not fire when the cursor is far away")
    _ = d2.enter("idle", reason: "t")
    check(d2.deliver(event: "system.wake", Guard.Context()) == nil,
          "an event no interrupt names is ignored")
} catch { check(false, "director pack decodes", "\(error)") }

// ---------------------------------------------------------------- scheduler
section("scheduler — the only place allowed to make a timer")
do {
    let s = Scheduler(queue: DispatchQueue(label: "test"))
    check(s.liveTimers == 0, "starts with no timer")
    s.apply(.none) {}
    check(s.liveTimers == 0, "a quiescent plan schedules NOTHING", "got \(s.liveTimers)")
    check(s.scheduledCount == 0, "and does not even count as a schedule")
    s.apply(.after(30)) {}
    check(s.liveTimers == 1, "a timed plan schedules exactly one wake")
    s.apply(.after(30)) {}
    check(s.liveTimers == 1, "re-applying replaces rather than accumulates",
          "got \(s.liveTimers)")
    s.cancel()
    check(s.liveTimers == 0, "cancel clears it")
    check(Scheduler.leewayFraction >= 0.10, "leeway is at least Apple's 10% guidance")
}

// ------------------------------------------------------------ pointer monitor
section("pointer hit testing")
do {
    var flat = [Bool](repeating: false, count: 64)
    for y in 2..<6 { for x in 2..<6 { flat[y * 8 + x] = true } }   // opaque core
    let mask = try HitMask(data: encodeMask([flat], 8, 8))
    let frame = CGRect(x: 100, y: 200, width: 16, height: 16)      // 8x8 cell at 2x
    let topLeftOnScreen = CGPoint(x: frame.minX, y: frame.maxY)

    // screen y is up, cell y is down: a cursor near the TOP of the frame must map
    // to a SMALL cell y
    let topLeft = PointerMonitor.read(cursor: CGPoint(x: 105, y: 214),
                                      frame: frame, cellTopLeft: topLeftOnScreen,
                                      scale: 2, mask: (mask, 0))
    check(topLeft.local.y < 2, "screen y-up converts to cell y-down",
          "got local \(topLeft.local)")
    let centre = PointerMonitor.read(cursor: CGPoint(x: 108, y: 208),
                                     frame: frame, cellTopLeft: topLeftOnScreen,
                                      scale: 2, mask: (mask, 0))
    check(centre.inside, "cursor over an opaque pixel reads as inside")
    let corner = PointerMonitor.read(cursor: CGPoint(x: 101, y: 215),
                                     frame: frame, cellTopLeft: topLeftOnScreen,
                                      scale: 2, mask: (mask, 0))
    check(!corner.inside,
          "cursor over a TRANSPARENT pixel inside the frame reads as OUTSIDE",
          "this is the whole point of the alpha mask; got local \(corner.local)")
    let away = PointerMonitor.read(cursor: CGPoint(x: 160, y: 208),
                                   frame: frame, cellTopLeft: topLeftOnScreen,
                                      scale: 2, mask: (mask, 0))
    check(!away.inside && abs(away.distance - 44) < 0.001,
          "distance is measured to the frame edge", "got \(away.distance)")
    check(away.side == .right && topLeft.side == .left, "side is reported")
} catch { check(false, "pointer hit testing", "\(error)") }

// -------------------------------------------------------------------- spring
section("spring — a float must be able to fall asleep")
do {
    var sp = Spring(stiffness: 110, damping: 13, mass: 1, maxOffset: 10, sleepThreshold: 0.2)
    check(sp.settled, "a spring starts at rest")
    sp.step(1.0 / 60)
    check(sp.settled, "stepping a settled spring is a no-op")

    sp.displace(by: CGVector(dx: 8, dy: 0))
    check(!sp.settled, "displacing wakes it")
    var steps = 0
    while !sp.settled && steps < 6000 { sp.step(1.0 / 60); steps += 1 }
    check(sp.settled, "it settles rather than ringing forever", "gave up after \(steps) steps")
    check(steps < 240, "and settles within a few seconds", "took \(steps) steps (\(steps/60)s)")
    check(sp.offset == .zero, "settling snaps exactly to rest, so 'settled' is a real state")

    var clamped = Spring(stiffness: 110, damping: 13, mass: 1, maxOffset: 5, sleepThreshold: 0.2)
    clamped.displace(by: CGVector(dx: 100, dy: 0))
    let d = (clamped.offset.x * clamped.offset.x + clamped.offset.y * clamped.offset.y).squareRoot()
    check(d <= 5.0001, "maxOffset clamps a large displacement", "got \(d)")

    // A stiff spring with a long frame must not explode - substepping handles it.
    var stiff = Spring(stiffness: 4000, damping: 20, mass: 1, maxOffset: 50, sleepThreshold: 0.2)
    stiff.displace(by: CGVector(dx: 20, dy: 20))
    for _ in 0..<200 { stiff.step(0.25) }
    check(stiff.offset.x.isFinite && stiff.offset.y.isFinite,
          "a stiff spring survives long frames without diverging",
          "got \(stiff.offset)")
}

// ---------------------------------------------------------------------- body
section("body — four bind modes, and the socket sync guarantee")
do {
    let root = fixtures.appendingPathComponent("build/socketed.pack")
    if FileManager.default.fileExists(atPath: root.path) {
        let store = PackStore(searchPaths: [root.deletingLastPathComponent()])
        let loaded = try store.load(root: root)
        let pk = loaded.pack
        let host = CALayer()
        let body = Body(pack: pk, host: host) { name in
            guard let t = pk.textures[name] else { return nil }
            return SpriteLayer.atlas(at: root.appendingPathComponent(t.file))
        }
        check(body.parts.count == 4, "one layer per part", "got \(body.parts.count)")
        // z-order: orb(-1) below body(0) below prop(3) below face(9)
        check(body.parts.map(\.decl.name) == ["orb", "body", "prop", "face"],
              "parts are ordered by z", "got \(body.parts.map(\.decl.name))")

        let wave = pk.clips["wave"]!
        body.apply(state: "waving", bodyClip: wave)

        let bodyLayer = body.parts.first { $0.decl.name == "body" }!.layer
        let propLayer = body.parts.first { $0.decl.name == "prop" }!.layer
        let orbLayer  = body.parts.first { $0.decl.name == "orb" }!.layer
        let faceLayer = body.parts.first { $0.decl.name == "face" }!.layer

        let bodyAnim = bodyLayer.animation(forKey: "sprite") as? CAKeyframeAnimation
        let socket = propLayer.animation(forKey: "socket") as? CAKeyframeAnimation
        check(socket != nil, "a socket gets its own position animation")
        check(socket?.keyPath == "position", "which animates position")
        check(socket?.calculationMode == .discrete, "discretely, like the frames it tracks")

        // THE guarantee: the prop and the body advance on the same timeline in the
        // render server, so a socket tracks a moving anchor with no per-frame work.
        let sameTimes = (socket?.keyTimes ?? []).map(\.doubleValue)
            == (bodyAnim?.keyTimes ?? []).map(\.doubleValue)
        check(sameTimes && socket?.duration == bodyAnim?.duration
              && socket?.autoreverses == bodyAnim?.autoreverses,
              "socket position shares the body's keyTimes, duration and autoreverse",
              "socket \(socket?.keyTimes ?? []) vs body \(bodyAnim?.keyTimes ?? [])")
        check(socket?.values?.count == wave.frames.count,
              "one position per body frame")

        // The socket actually tracks the anchor: frames 1 and 3 differ in hand y.
        let pts = (socket?.values as? [NSValue])?.map { $0.pointValue } ?? []
        check(pts.count == 4 && pts[1].y != pts[3].y,
              "socket positions differ where the anchor differs", "got \(pts)")

        check(orbLayer.animation(forKey: "bob") != nil,
              "a settled float bobs via a render-server animation, not a tick")
        check(orbLayer.animation(forKey: "socket") == nil,
              "a float is not keyframed to the body")
        check(faceLayer.animation(forKey: "sprite") != nil, "an overlay runs its own clip")
        check(body.springsSettled, "floats start settled, so no display link is needed")

        body.displaceFloats(by: CGVector(dx: 12, dy: 4))
        check(!body.springsSettled, "moving the window wakes the float")
        var n = 0
        while !body.stepSprings(1.0 / 60) && n < 3000 { n += 1 }
        check(body.springsSettled, "and it settles again", "gave up after \(n) steps")

        // hiddenIn must actually hide.
        body.apply(state: "sleeping", bodyClip: pk.clips["rest"]!)
        check(faceLayer.isHidden, "hiddenIn hides a part in that state")
        check(!bodyLayer.isHidden, "and leaves the others alone")
    } else {
        print("  SKIP  body (run: make build-fixture)")
    }
} catch { check(false, "body", "\(error)") }

// -------------------------------------------------------------------- motion
section("motion — kinematics, pure and testable")
do {
    let world = Motion.World(floor: 100, left: 200, right: 800)

    var m = Motion(feet: CGPoint(x: 500, y: 100))
    check(!m.needsTicking, "a still pet needs no display link")
    m.begin(.walk(speed: 100, direction: .right), in: world)
    check(m.needsTicking, "walking justifies a display link")
    check(m.facing == .right, "beginning a walk sets facing")
    _ = m.step(0.5, in: world)
    check(abs(m.feet.x - 550) < 0.001, "walks at the declared speed", "got \(m.feet.x)")
    check(abs(m.feet.y - 100) < 0.001, "stays on the floor while walking")

    // Clamp before reporting, so the pet is never outside the world even for the
    // frame in which it turns around.
    var e = Motion(feet: CGPoint(x: 790, y: 100))
    e.begin(.walk(speed: 1000, direction: .right), in: world)
    let hits = e.step(0.5, in: world)
    check(e.feet.x == 800, "clamps exactly to the edge, never past it", "got \(e.feet.x)")
    check(hits == [.edgeReached(.right)], "and reports the edge once", "got \(hits)")

    var l = Motion(feet: CGPoint(x: 210, y: 100))
    l.begin(.walk(speed: 1000, direction: .left), in: world)
    check(l.step(0.5, in: world) == [.edgeReached(.left)], "left edge reports too")
    check(l.feet.x == 200, "and clamps")

    // Falling
    var f = Motion(feet: CGPoint(x: 500, y: 400))
    f.begin(.fall(gravity: 900, terminal: 700), in: world)
    check(f.needsTicking, "falling justifies a display link")
    var events: [Motion.Event] = [], ticks = 0
    while events.isEmpty && ticks < 600 { events = f.step(1.0/60, in: world); ticks += 1 }
    check(events == [.landed], "falling ends in exactly one landed event", "got \(events)")
    check(f.feet.y == 100, "lands exactly on the floor, not below it", "got \(f.feet.y)")
    check(f.velocity == .zero, "landing kills velocity")

    var t = Motion(feet: CGPoint(x: 500, y: 100000))
    t.begin(.fall(gravity: 900, terminal: 700), in: world)
    for _ in 0..<600 { _ = t.step(1.0/60, in: world) }
    check(abs(t.velocity.dy) <= 700.0001, "terminal velocity is respected",
          "got \(t.velocity.dy)")

    // Dragging is driven by mouse events, not a tick.
    var d = Motion(feet: CGPoint(x: 500, y: 100))
    d.begin(.drag, in: world)
    check(!d.needsTicking, "being dragged needs NO display link — the OS is already "
                           + "delivering the events")
    let delta = d.moveTo(CGPoint(x: 520, y: 130))
    check(delta.dx == 20 && delta.dy == 30, "moveTo returns the delta for the springs")

    // The pet must never end up unreachable.
    var lost = Motion(feet: CGPoint(x: -5000, y: -5000))
    check(lost.rescue(into: world), "an off-world pet is rescued")
    check(lost.feet.x == 200 && lost.feet.y == 100, "back onto the floor",
          "got \(lost.feet)")
    var fine = Motion(feet: CGPoint(x: 500, y: 100))
    check(!fine.rescue(into: world), "a pet already in the world is left alone")
}

section("pack loading rejects a pack whose art is missing")
do {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("lodger-noart-\(UUID().uuidString)")
    let dir = tmp.appendingPathComponent("broken")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    // A valid manifest, no atlas on disk.
    try String(contentsOf: fixtures.appendingPathComponent("test.solidsquare/pack.json"),
               encoding: .utf8)
        .write(to: dir.appendingPathComponent("pack.json"), atomically: true, encoding: .utf8)

    let store = PackStore(searchPaths: [tmp])
    var reason = ""
    do { _ = try store.load(root: dir) }
    catch let f as PackStore.Failure { reason = f.description }
    catch { reason = "\(error)" }
    check(reason.contains("atlas/sq.png"),
          "a manifest that decodes but has no art is rejected, naming the file",
          "got \(reason.isEmpty ? "no error at all" : reason)")
    check(store.discover().isEmpty, "and it is not offered as installable")
}

// ---------------------------------------------------------------------- walk
section("walk — resolved up front, handed to the render server")
do {
    let w = Motion.World(floor: 100, left: 200, right: 800)
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let wide = 2400.0     // span cap = min(width/3, 400) = 400

    // A stretch that fits comfortably.
    let s1 = Walk.resolve(from: 400, direction: .right, speed: 100,
                          remainingSeconds: 2, world: w, displayWidth: wide, now: t0)
    check(s1?.endX == 600, "travels speed x duration", "got \(s1?.endX ?? -1)")
    check(abs((s1?.seconds ?? 0) - 2) < 0.001, "and takes that long")
    check(s1?.hitEdge == false && s1?.capped == false, "neither clamped nor capped")

    // Clamped by the world.
    let s2 = Walk.resolve(from: 700, direction: .right, speed: 100,
                          remainingSeconds: 5, world: w, displayWidth: wide, now: t0)
    check(s2?.endX == 800, "clamps to the world edge", "got \(s2?.endX ?? -1)")
    check(abs((s2?.seconds ?? 0) - 1) < 0.001, "duration shrinks to match the distance",
          "got \(s2?.seconds ?? -1)")
    check(s2?.hitEdge == true, "and reports that it hit the edge")

    // Cut short by the span cap, not by the edge: a long walk must not demand a
    // near-full-screen transparent window.
    let s3 = Walk.resolve(from: 210, direction: .right, speed: 100,
                          remainingSeconds: 20, world: Motion.World(floor: 100, left: 200, right: 5000),
                          displayWidth: wide, now: t0)
    check(s3?.span == 400, "a long walk is capped to the span limit", "got \(s3?.span ?? -1)")
    check(s3?.capped == true && s3?.hitEdge == false, "and says it was capped, not clamped")
    check(abs(s3!.remainingAfter(20) - 16) < 0.001,
          "the rest of the duration is carried into the next stretch",
          "got \(s3!.remainingAfter(20))")
    check(Walk.spanCap(displayWidth: 900) == 300, "the cap follows a narrow display")

    // Pinned against the edge it faces.
    check(Walk.resolve(from: 200, direction: .left, speed: 100, remainingSeconds: 2,
                       world: w, displayWidth: wide, now: t0) == nil,
          "a pet already at the edge resolves to no stretch")

    // Interpolation is what a mid-walk grab depends on.
    let s = s1!
    check(s.x(at: t0) == 400, "position at t=0 is the start")
    check(abs(s.x(at: t0.addingTimeInterval(1)) - 500) < 0.001, "halfway at t=half",
          "got \(s.x(at: t0.addingTimeInterval(1)))")
    check(s.x(at: t0.addingTimeInterval(2)) == 600, "the end at t=end")
    check(s.x(at: t0.addingTimeInterval(99)) == 600, "and clamps past the end")
    check(s.x(at: t0.addingTimeInterval(-5)) == 400, "and before the start")

    let left = Walk.resolve(from: 500, direction: .left, speed: 50,
                            remainingSeconds: 2, world: w, displayWidth: wide, now: t0)!
    check(left.endX == 400 && left.minX == 400 && left.maxX == 500,
          "walking left resolves min/max correctly", "got \(left)")
}

// --------------------------------------------------------------------- perch
section("perch — engine policy, and graceful degradation without permission")
do {
    let ours: pid_t = ProcessInfo.processInfo.processIdentifier
    func cand(_ id: UInt32, pid: pid_t = 9999, x: CGFloat = 100, y: CGFloat = 100,
              w: CGFloat = 600, h: CGFloat = 400, layer: Int = 0,
              onScreen: Bool = true) -> Perch.Candidate {
        Perch.Candidate(windowID: id, pid: pid, ownerName: "Test",
                        bounds: CGRect(x: x, y: y, width: w, height: h),
                        layer: layer, onScreen: onScreen)
    }

    check(Perch.perchable(cand(1), ownPID: ours), "a normal on-screen window is perchable")
    check(!Perch.perchable(cand(2, pid: ours), ownPID: ours),
          "the pet never perches on its own window")
    check(!Perch.perchable(cand(3, layer: 25), ownPID: ours),
          "a non-zero window layer is rejected — the Dock and menu bar live there")
    check(!Perch.perchable(cand(4, w: 120, h: 80), ownPID: ours),
          "a window below the minimum size is rejected")
    check(!Perch.perchable(cand(5, onScreen: false), ownPID: ours),
          "an off-screen window is rejected")

    // CGWindowList counts y downward from the primary display's top; AppKit counts
    // upward from its bottom. Getting this backwards puts the pet under the window.
    let H: CGFloat = 900
    let flipped = Perch.flip(CGRect(x: 100, y: 50, width: 600, height: 400), screenHeight: H)
    check(flipped.minY == 450 && flipped.maxY == 850,
          "flip converts CGWindowList's top-down y to AppKit's bottom-up",
          "got \(flipped)")
    check(Perch.flip(flipped, screenHeight: H) == CGRect(x: 100, y: 50, width: 600, height: 400),
          "and flipping twice is the identity")

    let surface = Perch.surface(of: CGRect(x: 100, y: 50, width: 600, height: 400),
                                screenHeight: H, halfWidth: 30)
    check(surface.floor == 850, "the walkable floor is the window's TOP edge",
          "got \(surface.floor)")
    check(surface.left == 130 && surface.right == 670,
          "inset by the pet's half width so it stays on the window", "got \(surface)")

    // Front-to-back order decides, and unperchable windows are skipped rather than
    // blocking what is behind them.
    let stack = [cand(1, pid: ours, x: 0, y: 0, w: 800, h: 800),   // ours, in front
                 cand(2, x: 0, y: 0, w: 800, h: 800, layer: 25),   // chrome
                 cand(3, x: 0, y: 0, w: 800, h: 800)]              // the real one
    let hit = Perch.target(under: CGPoint(x: 400, y: 400), in: stack,
                           ownPID: ours, screenHeight: H)
    check(hit?.windowID == 3, "picks the frontmost PERCHABLE window under the point",
          "got \(hit?.windowID ?? 0)")
    check(Perch.target(under: CGPoint(x: 4000, y: 4000), in: stack,
                       ownPID: ours, screenHeight: H) == nil,
          "a drop on empty space perches on nothing")

    let onscreen = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
    check(Perch.stillValid(cand(1), ownPID: ours, screens: onscreen),
          "a window on a display stays valid")
    check(!Perch.stillValid(cand(1, x: 9000, y: 9000), ownPID: ours, screens: onscreen),
          "a window dragged off every display is a lost perch")

    // Enumeration is permission-free, so this actually runs here.
    let live = WindowFinder.windows()
    check(!live.isEmpty, "CGWindowList enumeration works with no permission",
          "got \(live.count) windows")
    check(live.allSatisfy { $0.bounds.width > 0 && $0.bounds.height > 0 },
          "every enumerated window has real geometry")
    let normal = live.filter { Perch.perchable($0, ownPID: ours) }
    print("        (\(live.count) windows on screen, \(normal.count) perchable)")

    // Graceful degradation: without Accessibility the tracker refuses cleanly and
    // the engine simply never emits perch.acquired.
    if PerchTracker.hasPermission {
        print("        (Accessibility IS granted; the attach path is exercisable)")
    } else {
        let tracker = PerchTracker()
        check(tracker.attach(to: cand(1)) == .needsPermission,
              "without Accessibility, attach reports needsPermission rather than failing oddly")
        check(tracker.tracked == nil, "and tracks nothing")
    }
}

// ------------------------------------------------------------------ benchmark
// The pointer path is the one thing that runs on an event whose rate the engine
// does not control, so its per-event cost needs a number, not a shrug.
if CommandLine.arguments.contains("--bench") {
    section("hit test cost per mouse-move event")
    var flat = [Bool](repeating: false, count: 128 * 128)
    for y in 20..<110 { for x in 30..<100 { flat[y * 128 + x] = true } }
    let mask = try! HitMask(data: encodeMask([flat], 128, 128))
    let frame = CGRect(x: 500, y: 300, width: 256, height: 256)
    let topLeft = CGPoint(x: frame.minX, y: frame.maxY)
    let n = 2_000_000
    var inside = 0
    let t0 = Date()
    for i in 0..<n {
        let p = CGPoint(x: 400 + Double(i % 400), y: 250 + Double((i / 400) % 400))
        if PointerMonitor.read(cursor: p, frame: frame, cellTopLeft: topLeft,
                               scale: 2, mask: (mask, 0)).inside {
            inside += 1
        }
    }
    let ns = Date().timeIntervalSince(t0) / Double(n) * 1e9
    print(String(format: "  %.0f ns per event over %d samples (%d landed inside a 128x128 mask)",
                 ns, n, inside))
    for rate in [60, 120, 500] {
        print(String(format: "  at %3d events/s sustained: %.4f s CPU per hour",
                     rate, ns * 1e-9 * Double(rate) * 3600))
    }
    print("  a real session moves the cursor a fraction of the time, so this is a ceiling")
}

print("\n\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
