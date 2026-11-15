// Pack behavior acceptance through the actual generic Director. No AppKit needed.
import Foundation

@main
struct NornAcceptance {
    static func main() throws {
        let pack = try JSONDecoder().decode(Pack.self, from: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[1])))
        let director = Director(pack: pack)
        director.tuning = pack.defaultTuning; director.flags = pack.defaultFlags
        var context = Guard.Context()
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }
        for state in ["idle", "reading", "asleep"] {
            let plan = director.enter(state, reason: "quiescence acceptance")
            check(plan.quiescent && plan.wake == .none, "Rest state schedules work: \(state)")
        }
        for state in pack.states.keys where state != "held" {
            _ = director.enter(state, reason: "grab acceptance")
            check(director.deliver(event: "pointer.grab", context)?.state == "held", "Cannot grab \(state)")
        }
        _ = director.enter("held", reason: "release acceptance")
        check(director.deliver(event: "pointer.release", context)?.state == "falling", "Release must fall")
        check(director.deliver(event: "physics.landed", context)?.state == "landing", "Fall must land")
        check(director.timeout(context)?.state == "idle", "Landing must recover")
        for state in ["idle", "inspecting", "watching", "greeting", "walking", "settling", "waking", "landing"] {
            _ = director.enter(state, reason: "click acceptance")
            check(director.deliver(event: "pointer.click", context)?.state == "greeting", "Click from \(state)")
            _ = director.enter(state, reason: "walk acceptance")
            check(director.deliver(event: "pointer.doubleClick", context)?.state == "walking", "Double click from \(state)")
        }
        _ = director.enter("idle", reason: "attention acceptance")
        check(director.deliver(event: "pointer.enter", context)?.state == "watching", "Hover reaction")
        check(director.timeout(context)?.state == "inspecting", "Watch to inspect")
        check(director.timeout(context)?.state == "idle", "Inspect to idle")
        // IdleWatcher subscriptions are pack-wide and would arm a timer even
        // in quiescent states. This pack deliberately uses event-driven rest.
        check(!pack.requestedEvents.keys.contains("user.idle"), "Background idle watcher requested")
        check(!pack.requestedEvents.keys.contains("pointer.idle"), "Background pointer timer requested")
        _ = director.enter("walking", reason: "rest acceptance")
        check(director.timeout(context)?.state == "settling", "Walk to settling")
        check(director.timeout(context)?.state == "reading", "Settle to read")
        check(director.deliver(event: "system.willSleep", context)?.state == "asleep", "Read to sleep")
        check(director.deliver(event: "system.wake", context)?.state == "waking", "System wake")
        check(director.timeout(context)?.state == "idle", "Wake to idle")
        _ = director.enter("idle", reason: "power acceptance")
        check(director.deliver(event: "power.lowPowerMode", value: 0, context) == nil, "False power event must not sleep")
        context.lowPower = true
        check(director.deliver(event: "power.lowPowerMode", value: 1, context)?.state == "asleep", "Low power must sleep")
        check(director.deliver(event: "power.lowPowerMode", value: 1, context) == nil, "True power event must not wake")
        context.lowPower = false
        check(director.deliver(event: "power.lowPowerMode", value: 0, context)?.state == "waking", "Power restoration must wake")
        for (name, state) in pack.states where state.duration?.clipDriven == true {
            let plan = director.enter(name, reason: "timing acceptance")
            let ms = pack.clips[state.clip]!.durations(default: pack.stage.defaultFrameMs).reduce(0, +)
            check(plan.wake == .after(Double(ms) / 1000), "Clip timing mismatch: \(name)")
            check(director.timeout(context) != nil, "Finite state dead end: \(name)")
        }
        // ---- Settings controls
        func fresh(_ flags: [String: Bool] = [:], tuning: [String: Double] = [:]) -> Director {
            let d = Director(pack: pack, seed: 5)
            d.tuning = pack.defaultTuning.merging(tuning) { _, new in new }
            d.flags = pack.defaultFlags.merging(flags) { _, new in new }
            return d
        }
        check(pack.format == 2 && pack.referencedControls == Set(pack.tuning.keys), "Every declared control must be used")
        check(pack.defaultFlags["wanders"] == false, "Wandering must be off by default")
        // Default: arrival settles into the quiescent idle and nothing is scheduled.
        var d = fresh()
        check(d.start().state == "inspecting", "Arrival state")
        let rested = d.timeout(context)
        check(rested?.state == "idle" && rested?.quiescent == true && rested?.wake == Director.Wake.none,
              "Default arrival must end in quiescent idle with no wake")
        _ = d.enter("settling", reason: "controls")
        let reading = d.timeout(context)
        check(reading?.state == "reading" && reading?.wake == Director.Wake.none, "Default rest must be quiescent reading")
        for state in ["landing", "waking", "inspecting"] {
            _ = d.enter(state, reason: "controls")
            check(d.timeout(context)?.state == "idle", "Default \(state) must return to quiescent idle")
        }
        // Wandering on: a self-running loop idle -> walk -> settle -> read -> wake -> idle.
        d = fresh(["wanders": true])
        _ = d.start()
        var plan = d.timeout(context)
        check(plan?.state == "idle_restless" && plan?.quiescent == false, "Wandering arrival uses the timed idle")
        if case .after(let seconds)? = plan?.wake { check((20...60).contains(seconds), "Timed idle waits 20-60 s, got \(seconds)") }
        else { check(false, "Timed idle must schedule one wake") }
        var loop: [String] = []
        for _ in 0..<5 { plan = d.timeout(context); loop.append(plan?.state ?? "nil") }
        check(loop == ["walking", "settling", "reading_restless", "waking", "idle_restless"], "Wandering loop: \(loop)")
        let quick = fresh(["wanders": true], tuning: ["wanderPace": 2]).enter("idle_restless", reason: "controls")
        if case .after(let seconds) = quick.wake { check((10...30).contains(seconds), "Pace 200% halves the wait, got \(seconds)") }
        else { check(false, "Paced idle must schedule a wake") }
        for state in ["idle_restless", "reading_restless"] {
            _ = d.enter(state, reason: "controls")
            check(d.deliver(event: "pointer.grab", context)?.state == "held", "Cannot grab \(state)")
        }
        // The switch itself re-routes her, in both directions, from rest states.
        d = fresh(["wanders": true]); _ = d.enter("idle", reason: "controls")
        check(d.deliver(event: "controls.changed", context)?.state == "inspecting", "Switching wandering on must rouse idle")
        check(d.timeout(context)?.state == "idle_restless", "and lead to the timed idle")
        d = fresh(["wanders": true]); _ = d.enter("reading", reason: "controls")
        check(d.deliver(event: "controls.changed", context)?.state == "waking", "Switching wandering on must rouse reading")
        d = fresh(["wanders": false]); _ = d.enter("idle_restless", reason: "controls")
        check(d.deliver(event: "controls.changed", context)?.state == "inspecting", "Switching wandering off must leave the timed idle")
        check(d.timeout(context)?.state == "idle", "and return to quiescent idle")
        d = fresh(); _ = d.enter("idle", reason: "controls")
        check(d.deliver(event: "controls.changed", context) == nil, "An unrelated toggle must not disturb quiescent idle")
        // Pointer and power toggles.
        for state in ["idle", "idle_restless"] {
            d = fresh(["noticesCursor": false]); _ = d.enter(state, reason: "controls")
            check(d.deliver(event: "pointer.enter", context) == nil, "Hover must be switchable in \(state)")
            d = fresh(["greets": false]); _ = d.enter(state, reason: "controls")
            check(d.deliver(event: "pointer.click", context) == nil, "Greeting must be switchable in \(state)")
            check(d.deliver(event: "pointer.doubleClick", context)?.state == "walking", "Double click still walks with greeting off")
            var low = context; low.lowPower = true
            d = fresh(["napsInLowPower": false]); _ = d.enter(state, reason: "controls")
            check(d.deliver(event: "power.lowPowerMode", value: 1, low) == nil, "Low power nap must be switchable in \(state)")
            check(d.deliver(event: "system.willSleep", low)?.state == "asleep", "System sleep still applies")
        }
        d = fresh(["greets": false]); _ = d.enter("reading", reason: "controls")
        check(d.deliver(event: "pointer.click", context)?.state == "waking", "Click still wakes a reader with greeting off")
        print("Norn Director: \(checks) checks passed (grab/release/land, hover/click/walk, rest/wake, power guards, timing, Settings controls).")
    }
}
