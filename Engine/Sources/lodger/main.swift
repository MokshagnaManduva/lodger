import AppKit
import LodgerEngine

// The walking skeleton. It renders a synthetic test pack and nothing else, and
// exists to prove the three claims the architecture rests on before anything is
// built on top of them:
//
//   1. a borderless, non-activating, transparent, floating panel that stays out
//      of the Dock and the app switcher, click-through except on the silhouette
//   2. sprite animation that runs in the render server - verified by pausing the
//      process and watching it keep going
//   3. a quiescent state that installs no timer at all
//
// Deliberately no behaviour, no physics, and no Klien.

// Line-buffer stdout: this process is long-lived and its diagnostics are read by
// external verification scripts while it is still running.
setvbuf(stdout, nil, _IOLBF, 0)

struct Options {
    var packPath: String?
    var soakSeconds: Double?
    var state: String?
    var headless = false
    var perch = false
    var requestAX = false
}

func parse() -> Options {
    var o = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--pack":  o.packPath = it.next()
        case "--soak":  o.soakSeconds = it.next().flatMap(Double.init)
        case "--state": o.state = it.next()
        case "--headless": o.headless = true
        case "--perch": o.perch = true
        case "--ax":    o.requestAX = true
        case "-h", "--help":
            print("""
            lodger - walking skeleton

              --pack <dir>    pack to load (default: Tests/Fixtures/test.blinker)
              --state <name>  start in this state instead of initialState
              --soak <sec>    run for N seconds, then report CPU used
              --headless      load and report, render nothing, exit
              --perch         enable window perching (needs Accessibility)
              --ax            request Accessibility and report, then exit
            """)
            exit(0)
        default: break
        }
    }
    return o
}

func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let u = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
    let s = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
    return u + s
}

let opts = parse()
let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

if opts.requestAX {
    // Requested from the signed bundle on purpose: a TCC grant attaches to the
    // binary that asked, so asking from a throwaway test executable would not help
    // the app. In normal use this is called at the moment the user drops the pet on
    // a window, never at launch.
    print("already trusted : \(PerchTracker.hasPermission)")
    if !PerchTracker.hasPermission {
        print("requesting… a system dialog should appear; approve it in System Settings")
        _ = PerchTracker.requestPermission()
        for i in 1...60 {
            if PerchTracker.hasPermission { break }
            Thread.sleep(forTimeInterval: 1)
            if i % 10 == 0 { print("  still waiting (\(i)s)…") }
        }
    }
    print("trusted now     : \(PerchTracker.hasPermission)")
    exit(PerchTracker.hasPermission ? 0 : 1)
}

// Normal operation, unless a measurement flag asked for something else.
if opts.packPath == nil, opts.soakSeconds == nil, !opts.headless, opts.state == nil {
    // Running from the repo: also look where the working tree keeps packs, so the
    // app is usable before there is an installed bundle.
    runApp(devPaths: [cwd.appendingPathComponent("Packs"),
                      cwd.appendingPathComponent("Tests/Fixtures/build")]
                     .filter { FileManager.default.fileExists(atPath: $0.path) })
}
let packURL = URL(fileURLWithPath: opts.packPath
                  ?? cwd.appendingPathComponent("Tests/Fixtures/test.blinker").path)

let store = PackStore(searchPaths: [packURL.deletingLastPathComponent()])
guard let loaded = try? store.load(root: packURL) else {
    FileHandle.standardError.write(Data("cannot load pack at \(packURL.path)\n".utf8))
    exit(1)
}
let pack = loaded.pack
let stateName = opts.state ?? pack.initialState
guard let state = pack.states[stateName], let clip = pack.clips[state.clip],
      let texture = pack.textures[clip.texture] else {
    FileHandle.standardError.write(Data("state/clip/texture missing for \(stateName)\n".utf8))
    exit(1)
}

print("pack     : \(pack.identity.id) v\(pack.identity.version) — \(pack.identity.name)")
print("state    : \(stateName)\(state.quiescent ? "  [quiescent]" : "")")
print("clip     : \(state.clip)  \(clip.frames.count) frame(s), loop=\(clip.loop.rawValue)")
print("cell     : \(pack.stage.cell.w)x\(pack.stage.cell.h) @\(pack.stage.defaultScale)x")

if let m = (try? store.hitMask(for: loaded, texture: clip.texture)) ?? nil {
    print("hit mask : \(m.count) cells, \(m.cellWidth)x\(m.cellHeight), "
          + "cell 0 has \(m.opaqueCount(cell: 0)) opaque px")
} else {
    print("hit mask : none (pack not built with packtool build)")
}

if opts.headless && opts.soakSeconds == nil { exit(0) }

// ---------------------------------------------------------------- rendering

let app = NSApplication.shared
// No Dock icon, no app switcher entry, without needing an Info.plist.
app.setActivationPolicy(.accessory)

let pet = Pet(loaded: loaded)
pet.perchMode = opts.perch
var transitions = 0
pet.onStateChange = { plan, sched in
    transitions += 1
    let pos = String(format: "x=%.0f", pet.feet.x)
    let wake = plan.wake == .none ? "no timer"
                                  : String(format: "wake in %.2fs", { if case .after(let t) = plan.wake { return t } else { return 0 } }())
    print(String(format: "  %-10s %-16s %-18s timers=%d link=%@ %@",
                 (plan.state as NSString).utf8String!,
                 (plan.reason as NSString).utf8String!,
                 (wake as NSString).utf8String!,
                 sched.liveTimers,
                 pet.hasDisplayLink ? "YES" : "no ",
                 pos))
}
pet.start()

pet.panel.orderFrontRegardless()

let policyOK = app.activationPolicy() == .accessory
print("""

claim 1  window
         borderless=\(pet.panel.styleMask.contains(.borderless)) nonactivating=\(pet.panel.styleMask.contains(.nonactivatingPanel)) opaque=\(pet.panel.isOpaque)
         level=\(pet.panel.level.rawValue) ignoresMouseEvents=\(pet.panel.ignoresMouseEvents) canBecomeKey=\(pet.panel.canBecomeKey)
         activationPolicy=\(policyOK ? "accessory (no Dock, no cmd-Tab)" : "REGULAR - WRONG")
claim 3  timers
         pointer monitor installed=\(pet.pointer.installed) (only if a state reacts to the pointer)
         live timers now=\(pet.scheduler.liveTimers)  display link=\(pet.hasDisplayLink ? "RUNNING" : "none")
perching
         mode=\(pet.perchMode ? "on" : "off")  pack declares windowEdges=\(pet.packSupportsPerching)
         accessibility granted=\(PerchTracker.hasPermission)  perched=\(pet.isPerched)

pid      : \(ProcessInfo.processInfo.processIdentifier)
verify   : sudo timerfires -p \(ProcessInfo.processInfo.processIdentifier)
""")

// Screen-space rect with a top-left origin, so an external capture can find us.
if let screen = NSScreen.main {
    let f = pet.panel.frame
    let top = screen.frame.maxY - f.maxY
    print("CAPTURE_RECT \(Int(f.origin.x)),\(Int(top)),\(Int(f.width)),\(Int(f.height))")
}

if let soak = opts.soakSeconds {
    let start = cpuSeconds(), wall = Date()
    print("soaking \(Int(soak))s from state '\(stateName)' ...")
    // One deferred wake for the whole soak. NOT RunLoop.run(until:), which polls
    // and would put the harness's own overhead into the number we are measuring.
    DispatchQueue.global().asyncAfter(deadline: .now() + soak) {
        let used = cpuSeconds() - start
        let elapsed = Date().timeIntervalSince(wall)
        print(String(format: "\nCPU used : %.4f s over %.1f s wall  (%.4f%% of one core)",
                     used, elapsed, used / elapsed * 100))
        print(String(format: "projected: %.2f s CPU per idle hour  (target < 7 s)",
                     used / elapsed * 3600))
        print("transitions: \(transitions), scheduler wakes: \(pet.scheduler.scheduledCount)")
        print("display link: starts=\(pet.linkStarts) ticks=\(pet.springTicks) running=\(pet.hasDisplayLink)")
        print("window enumerations: \(WindowFinder.enumerations)  (must be 0 outside a drag)")
        if !pet.profile.isEmpty {
            let total = pet.profile.values.reduce(0, +)
            print("tick profile (wall seconds inside each phase):")
            for (k, v) in pet.profile.sorted(by: { $0.value > $1.value }) {
                print(String(format: "  %-16s %8.4f s  %5.1f%% of measured  %7.1f us/tick",
                             (k as NSString).utf8String!, v, v / total * 100,
                             v / Double(max(1, pet.springTicks)) * 1e6))
            }
        }
        exit(0)
    }
}

app.run()
