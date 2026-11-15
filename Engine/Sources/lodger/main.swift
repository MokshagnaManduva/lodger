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
// Deliberately no behaviour, no physics, and no particular character.

// Line-buffer stdout: this process is long-lived and its diagnostics are read by
// external verification scripts while it is still running.
setvbuf(stdout, nil, _IOLBF, 0)

struct Options {
    var packPath: String?
    var soakSeconds: Double?
    var warmupSeconds: Double = 0
    var state: String?
    var headless = false
}

func parse() -> Options {
    var o = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--pack":  o.packPath = it.next()
        case "--soak":  o.soakSeconds = it.next().flatMap(Double.init)
        case "--warmup": o.warmupSeconds = it.next().flatMap(Double.init) ?? 0
        case "--state": o.state = it.next()
        case "--headless": o.headless = true
        case "-h", "--help":
            print("""
            lodger - walking skeleton

              --pack <dir>    pack to load (default: Tests/Fixtures/test.blinker)
              --state <name>  start in this state instead of initialState
              --soak <sec>    run for N seconds, then report CPU used
              --warmup <sec>  settle before starting the soak measurement
              --headless      load and report, render nothing, exit
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
// Director.start() uses its current state. Previously --state only changed the
// printed metadata, so every rendered soak silently measured initialState.
if opts.state != nil { _ = pet.director.enter(stateName, reason: "--state") }
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
    guard soak.isFinite, soak > 0, opts.warmupSeconds.isFinite, opts.warmupSeconds >= 0 else {
        fputs("soak must be positive and warmup nonnegative (finite seconds)\n", stderr)
        exit(2)
    }
    func beginMeasurement() {
        let start = cpuSeconds(), wall = ProcessInfo.processInfo.systemUptime
        let startTransitions = transitions
        let startScheduled = pet.scheduler.scheduledCount
        let startLinks = pet.linkStarts, startTicks = pet.springTicks
        let startRouting = pet.pointer.animationRefreshCount
        let startState = pet.director.current
        let inputIdleStart = IdleWatcher.systemInput()
        let visibleStart = pet.panel.occlusionState.contains(.visible)
        let startUserIdle = pet.userIdle.scheduledCount, startPointerIdle = pet.pointerIdle.scheduledCount
        print("soaking \(Int(soak))s from state '\(stateName)' ...")
        // One deferred wake for the whole soak. NOT RunLoop.run(until:), which polls
        // and would put the harness's own overhead into the number we are measuring.
        // Read engine counters on the main thread; no polling or sampling timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + soak) {
            let used = cpuSeconds() - start
            let elapsed = ProcessInfo.processInfo.systemUptime - wall
            print(String(format: "\nCPU used : %.4f s over %.1f s wall  (%.4f%% of one core)",
                         used, elapsed, used / elapsed * 100))
            print(String(format: "projected: %.2f s CPU per idle hour  (target < 7 s)",
                         used / elapsed * 3600))
            print("transitions: \(transitions), scheduler wakes: \(pet.scheduler.scheduledCount)")
            print("display link: starts=\(pet.linkStarts) ticks=\(pet.springTicks) running=\(pet.hasDisplayLink)")
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            let energy: [String: Any] = [
                "schema": 1, "requested_seconds": soak, "warmup_seconds": opts.warmupSeconds,
                "elapsed_seconds": elapsed, "cpu_seconds": used,
                "cpu_seconds_per_hour": used / elapsed * 3600,
                "requested_state": stateName, "start_state": startState, "end_state": pet.director.current,
                "transitions": transitions - startTransitions,
                "state_deadlines_scheduled": pet.scheduler.scheduledCount - startScheduled,
                "live_state_timers": pet.scheduler.liveTimers,
                "display_link_starts": pet.linkStarts - startLinks,
                "display_link_ticks": pet.springTicks - startTicks,
                "display_link_running": pet.hasDisplayLink,
                "routing_refreshes": pet.pointer.animationRefreshCount - startRouting,
                "routing_timer": pet.pointer.hasAnimationTimer,
                "routing_display_link": pet.pointer.hasRoutingDisplayLink,
                "user_idle_deadlines": pet.userIdle.scheduledCount - startUserIdle,
                "pointer_idle_deadlines": pet.pointerIdle.scheduledCount - startPointerIdle,
                "user_idle_armed": pet.userIdle.isArmed, "pointer_idle_armed": pet.pointerIdle.isArmed,
                "pointer_monitor": pet.pointer.installed,
                "peak_rss_bytes": usage.ru_maxrss,
                "input_idle_seconds_start": inputIdleStart,
                "input_idle_seconds_end": IdleWatcher.systemInput(),
                "visible_start": visibleStart, "visible_end": pet.panel.occlusionState.contains(.visible),
                "low_power_mode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            ]
            if let json = try? JSONSerialization.data(withJSONObject: energy, options: [.sortedKeys]),
               let line = String(data: json, encoding: .utf8) { print("ENERGY_JSON \(line)") }
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
    if opts.warmupSeconds > 0 {
        print("warmup: \(opts.warmupSeconds)s (excluded from CPU interval)")
        DispatchQueue.main.asyncAfter(deadline: .now() + opts.warmupSeconds, execute: beginMeasurement)
    } else { beginMeasurement() }
}

app.run()
