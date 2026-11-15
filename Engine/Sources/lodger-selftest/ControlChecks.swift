import Foundation
import LodgerEngine

/// Pack-declared controls: typed tuning entries, toggles as guard flags,
/// weight scaling and knob-valued event thresholds.
func controlPackJSON(format: Int = 2, tuning: String, states: String) -> String {
    #"""
    {"format":\#(format),
     "identity":{"id":"test.controls","name":"C","version":"1.0.0","author":"t","license":"CC0-1.0"},
     "stage":{"cell":{"w":8,"h":8},"bodyHeight":8,"ground":{"x":4,"y":8},"defaultFrameMs":100},
     "textures":{"t":{"file":"a.png","columns":2,"rows":1}},
     "clips":{"loop":{"texture":"t","loop":"forever","frames":[{"cell":0},{"cell":1}]},
              "once":{"texture":"t","loop":"none","frames":[{"cell":0,"ms":300}]}},
     "parts":[{"name":"body","bind":{"mode":"body"}}],
     "initialState":"idle",
     "tuning":\#(tuning),
     "states":\#(states)}
    """#
}

let controlTuning = #"""
{"roam":{"label":"Roaming","min":0,"max":2,"default":1,"group":"Activity","description":"How often","unit":"percent"},
 "rest":{"label":"Resting","min":0,"max":2,"default":1},
 "wait":{"label":"Wait","min":10,"max":600,"default":300,"unit":"seconds"},
 "curious":{"type":"toggle","label":"Curious","default":true,"group":"Pointer"}}
"""#

let controlStates = #"""
{"idle":{"clip":"loop","duration":{"minMs":1000,"maxMs":1000},
   "next":[{"state":"a","weight":1,"weightBy":"roam"},{"state":"b","weight":1,"weightBy":"rest"}],
   "interrupts":[
     {"on":"pointer.click","state":"a","when":{"flag":{"name":"curious","value":true}}},
     {"on":{"user.idle":{"knob":"wait"}},"state":"asleep"},
     {"on":{"pointer.near":60},"state":"b"}]},
 "a":{"clip":"once","next":[{"state":"idle","weight":1}]},
 "b":{"clip":"once","next":[{"state":"idle","weight":1}]},
 "asleep":{"clip":"loop","quiescent":true,"interrupts":[{"on":"pointer.click","state":"idle"}]}}
"""#

func runControlChecks() throws {
    section("pack-declared controls — typed tuning, flags, weights and thresholds")
    func decode(_ json: String) throws -> Pack { try JSONDecoder().decode(Pack.self, from: Data(json.utf8)) }
    let pack = try decode(controlPackJSON(tuning: controlTuning, states: controlStates))

    let roam = pack.tuning["roam"]!, curious = pack.tuning["curious"]!
    check(!roam.isToggle && roam.min == 0 && roam.max == 2 && roam.defaultValue == 1, "a slider decodes its range and default")
    check(roam.group == "Activity" && roam.description == "How often" && roam.unit == "percent", "display metadata decodes")
    check(curious.isToggle && curious.defaultFlag == true && curious.group == "Pointer", "a toggle decodes a boolean default")
    check(pack.tuning["rest"]?.group == nil && pack.tuning["rest"]?.isToggle == false, "type defaults to slider and metadata is optional")
    check((try? decode(controlPackJSON(tuning: #"{"x":{"type":"toggle","label":"X","default":true,"min":0}}"#, states: controlStates))) == nil,
          "a toggle with a range is rejected")
    check((try? decode(controlPackJSON(tuning: #"{"x":{"type":"toggle","label":"X","default":1}}"#, states: controlStates))) == nil,
          "a toggle with a numeric default is rejected")
    check((try? decode(controlPackJSON(tuning: #"{"x":{"type":"dial","label":"X","default":1}}"#, states: controlStates))) == nil,
          "an unknown control type is rejected")
    check(pack.defaultTuning == ["roam": 1, "rest": 1, "wait": 300] && pack.defaultFlags == ["curious": true],
          "defaults split into numeric tuning and boolean flags")

    // Toggle -> flag guard
    let ctx = Guard.Context()
    var d = Director(pack: pack, seed: 7)
    d.tuning = pack.defaultTuning; d.flags = ["curious": true]
    _ = d.start()
    check(d.deliver(event: "pointer.click", ctx)?.state == "a", "a toggle that is on satisfies its flag guard")
    d = Director(pack: pack, seed: 7); d.tuning = pack.defaultTuning; d.flags = ["curious": false]
    _ = d.start()
    check(d.deliver(event: "pointer.click", ctx) == nil, "a toggle that is off blocks the interrupt")
    d.flags = ["curious": true]
    check(d.deliver(event: "pointer.click", ctx)?.state == "a", "a changed toggle applies at the next evaluation without re-entering the state")

    // weightBy
    func picks(_ tuning: [String: Double]) -> [String: Int] {
        let d = Director(pack: pack, seed: 99); d.tuning = tuning
        var out: [String: Int] = [:]
        for _ in 0..<200 {
            _ = d.enter("idle", reason: "test")
            if let p = d.timeout(ctx) { out[p.state, default: 0] += 1 }
        }
        return out
    }
    let even = picks(["roam": 1, "rest": 1])
    check((even["a"] ?? 0) > 60 && (even["b"] ?? 0) > 60, "equal knobs keep the authored weights", "\(even)")
    let noRoam = picks(["roam": 0, "rest": 1])
    check(noRoam["a"] == nil && noRoam["b"] == 200, "a knob at zero removes its transition", "\(noRoam)")
    let mostly = picks(["roam": 2, "rest": 0.2])
    check((mostly["a"] ?? 0) > 150, "a higher knob makes its transition proportionally likelier", "\(mostly)")
    let none = picks(["roam": 0, "rest": 0])
    check((none["a"] ?? 0) + (none["b"] ?? 0) == 200 && (none["a"] ?? 0) > 60,
          "all weights scaled to zero falls back to authored weights instead of stalling", "\(none)")
    let missing = picks([:])
    check((missing["a"] ?? 0) + (missing["b"] ?? 0) == 200, "an unset knob leaves the weight unscaled")

    // Knob-valued thresholds
    let idleRef = pack.states["idle"]!.interrupts[1].on
    check(idleRef.knob == "wait" && idleRef.value == nil, "an event threshold may name a knob")
    check(idleRef.threshold(["wait": 120]) == 120 && pack.states["idle"]!.interrupts[2].on.threshold([:]) == 60,
          "thresholds resolve through tuning, literals pass through")
    d = Director(pack: pack, seed: 1); d.tuning = ["wait": 120]; _ = d.start()
    check(d.deliver(event: "user.idle", value: 100, ctx) == nil, "below the tuned threshold nothing fires")
    check(d.deliver(event: "user.idle", value: 120, ctx)?.state == "asleep", "at the tuned threshold the interrupt fires")
    d = Director(pack: pack, seed: 1); d.tuning = [:]; _ = d.start()
    check(d.deliver(event: "user.idle", value: 1e9, ctx) == nil, "an unresolved knob threshold never fires")
    check(pack.requestedEvents(tuning: ["wait": 45])["user.idle"] == .some(45)
          && pack.requestedEvents(tuning: ["wait": 45])["pointer.near"] == .some(60),
          "requested events report the tuned threshold")
    check(pack.requestedEvents["user.idle"] == .some(300), "the untuned view uses the pack default")
}
