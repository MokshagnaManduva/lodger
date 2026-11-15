// Compile with the engine's pure Pack/Guard/Director sources; no character code
// belongs in the engine module. Invoked by verify_klien_runtime.py --behavior.
import Foundation

@main
struct TossAcceptance {
    static func main() throws {
        let pack = try JSONDecoder().decode(Pack.self, from: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[1])))
        let director = Director(pack: pack)
        director.tuning = pack.defaultTuning; director.flags = pack.defaultFlags
        var context = Guard.Context()
        context.pointerDistance = 30
        let toss = director.enter("toss_emblem", reason: "acceptance")
        precondition(toss.wake == .after(1.2))
        precondition(director.timeout(context)?.state == "idle")
        let events: [(String, Double?, String)] = [
            ("pointer.near", 30, "watching"), ("pointer.fast", 1500, "startled"),
            ("pointer.grab", nil, "held"), ("pointer.click", nil, "tipping_hat"),
            ("user.idle", 300, "sleep_preparing"), ("power.lowPowerMode", 1, "sitting_down"),
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
        try controls(pack, context)
        print("Pointer Director: click from idle/watching, nearby fast reaction and distant fast rejection PASS")
        print("Toss Director: 1.2s scheduled completion, idle return, eight airborne interruption routes and threshold rejection PASS")
    }

    /// Settings controls: defaults keep the authored behaviour, and each control
    /// changes exactly the transition it is wired to.
    static func controls(_ pack: Pack, _ near: Guard.Context) throws {
        func director(tuning: [String: Double] = [:], flags: [String: Bool] = [:], seed: UInt64 = 11) -> Director {
            let d = Director(pack: pack, seed: seed)
            d.tuning = pack.defaultTuning.merging(tuning) { _, new in new }
            d.flags = pack.defaultFlags.merging(flags) { _, new in new }
            return d
        }
        func idleChoices(_ tuning: [String: Double]) -> [String: Int] {
            let d = director(tuning: tuning)
            var out: [String: Int] = [:]
            for _ in 0..<2000 {
                _ = d.enter("idle", reason: "controls")
                if let next = d.timeout(near) { out[next.state, default: 0] += 1 }
            }
            return out
        }
        precondition(pack.format == 2 && pack.referencedControls == Set(pack.tuning.keys),
                     "every declared control is used: \(Set(pack.tuning.keys).subtracting(pack.referencedControls))")
        let authored = idleChoices([:])
        // Authored weights 25/35/10/15(x0.5 guard)/15: every activity appears.
        for state in ["idle", "walking", "tipping_hat", "sitting_down", "toss_emblem"] {
            precondition((authored[state] ?? 0) > 60, "default distribution lost \(state): \(authored)")
        }
        precondition(abs(Double(authored["walking"] ?? 0) / 2000 - 35.0 / 92.5) < 0.05, "default walk share changed: \(authored)")
        for (knob, state) in [("wander", "walking"), ("toss", "toss_emblem"), ("hatTips", "tipping_hat"), ("sit", "sitting_down")] {
            let off = idleChoices([knob: 0])
            precondition(off[state] == nil, "\(knob)=0 must remove \(state): \(off)")
            precondition(off.values.reduce(0, +) == 2000, "\(knob)=0 must not stall idle")
            let more = idleChoices([knob: 2])
            precondition((more[state] ?? 0) > (authored[state] ?? 0), "\(knob)=2 must raise \(state)")
        }
        let still = idleChoices(["wander": 0, "toss": 0, "hatTips": 0, "sit": 0])
        precondition(still == ["idle": 2000], "all activities off keeps him idling: \(still)")

        for state in ["idle", "toss_emblem"] {
            var d = director(tuning: ["sleepAfter": 900]); _ = d.enter(state, reason: "controls")
            precondition(d.deliver(event: "user.idle", value: 300, near) == nil, "sleepAfter must delay sleep in \(state)")
            precondition(d.deliver(event: "user.idle", value: 900, near)?.state == "sleep_preparing")
            d = director(flags: ["reactsToCursor": false]); _ = d.enter(state, reason: "controls")
            precondition(d.deliver(event: "pointer.near", value: 30, near) == nil, "cursor watching must be switchable in \(state)")
            precondition(d.deliver(event: "pointer.click", near)?.state == "tipping_hat", "clicks still work with watching off")
            d = director(flags: ["startles": false]); _ = d.enter(state, reason: "controls")
            precondition(d.deliver(event: "pointer.fast", value: 2000, near) == nil, "startle must be switchable in \(state)")
        }
        precondition(pack.requestedEvents(tuning: ["sleepAfter": 900])["user.idle"] == .some(900))

        func sleepsFromSitting(night: Bool, lowPower: Bool, toggle: Bool) -> Bool {
            var ctx = near; ctx.minutesSinceMidnight = night ? 30 : 12 * 60; ctx.lowPower = lowPower
            let d = director(flags: ["sleepsAtNight": toggle])
            for _ in 0..<200 {
                _ = d.enter("sitting", reason: "controls")
                if d.timeout(ctx)?.state == "sleeping" { return true }
            }
            return false
        }
        precondition(sleepsFromSitting(night: true, lowPower: false, toggle: true), "night dozing on by default")
        precondition(!sleepsFromSitting(night: true, lowPower: false, toggle: false), "night dozing switchable")
        precondition(!sleepsFromSitting(night: false, lowPower: false, toggle: true), "no dozing by day")
        precondition(sleepsFromSitting(night: false, lowPower: true, toggle: false), "low power still allows sleep")
        print("Controls Director: default distribution, four frequency sliders, sleep delay and three toggles PASS")
    }
}
