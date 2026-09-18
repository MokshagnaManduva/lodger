// Compile with the engine's pure Pack/Guard/Director sources; no character code
// belongs in the engine module. Invoked by verify_klien_runtime.py --behavior.
import Foundation

@main
struct TossAcceptance {
    static func main() throws {
        let pack = try JSONDecoder().decode(Pack.self, from: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[1])))
        let director = Director(pack: pack)
        var context = Guard.Context()
        context.pointerDistance = 30
        let toss = director.enter("toss_emblem", reason: "acceptance")
        precondition(toss.wake == .after(1.2))
        precondition(director.timeout(context)?.state == "idle")
        let events: [(String, Double?, String)] = [
            ("pointer.near", 30, "watching"), ("pointer.fast", 1500, "startled"),
            ("pointer.grab", nil, "held"), ("pointer.click", nil, "tipping_hat"),
            ("user.idle", 300, "sleep_preparing"), ("power.lowPowerMode", 1, "sitting_down"),
            ("perch.acquired", nil, "perched"), ("perch.lost", nil, "falling")
        ]
        for (event, value, target) in events {
            _ = director.enter("toss_emblem", reason: "acceptance")
            director.advanceTime(0.6) // interrupt at the airborne apex
            precondition(director.deliver(event: event, value: value, context)?.state == target,
                         "Incorrect mid-toss interruption: \(event)")
        }
        _ = director.enter("toss_emblem", reason: "acceptance")
        precondition(director.deliver(event: "pointer.near", value: 100, context) == nil)
        precondition(director.current == "toss_emblem")
        for state in ["idle", "watching"] {
            _ = director.enter(state, reason: "pointer acceptance")
            var far = context; far.pointerDistance = 300
            precondition(director.deliver(event: "pointer.fast", value: 2000, far) == nil)
            precondition(director.deliver(event: "pointer.fast", value: 2000, context)?.state == "startled")
            _ = director.enter(state, reason: "pointer acceptance")
            precondition(director.deliver(event: "pointer.click", context)?.state == "tipping_hat")
        }
        print("Pointer Director: click from idle/watching, nearby fast reaction and distant fast rejection PASS")
        print("Toss Director: 1.2s scheduled completion, idle return, eight airborne interruption routes and threshold rejection PASS")
    }
}
