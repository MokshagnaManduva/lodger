// Pack behavior acceptance through the actual generic Director. No AppKit needed.
import Foundation

@main
struct NornAcceptance {
    static func main() throws {
        let pack = try JSONDecoder().decode(Pack.self, from: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[1])))
        let director = Director(pack: pack)
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
        print("Norn Director: \(checks) checks passed (grab/release/land, hover/click/walk, rest/wake, power guards, timing).")
    }
}
