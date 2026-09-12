import Foundation

/// The behaviour state machine.
///
/// Deliberately **pure**: it owns no timers, no run loop and no clock. It is given
/// elapsed time and a context, and returns decisions plus a description of the wake
/// it needs. Scheduling is a separate concern (`Scheduler`), which is what makes
/// Rule 2 auditable - you can read this file and see that it cannot poll.
///
/// It is also fully testable without a run loop, and reproducible: the RNG is
/// seedable, so a personality can be replayed exactly.
public final class Director {

    /// What the engine must arrange after entering a state.
    public enum Wake: Equatable, Sendable {
        /// Nothing at all. No timer, no display link, no run-loop source.
        /// A quiescent state leaves the process genuinely asleep until an
        /// external event arrives.
        case none
        /// One coalesced wake after this interval. Never a repeating tick.
        case after(TimeInterval)
    }

    public struct Plan: Sendable {
        public let state: String
        public let clip: String
        public let quiescent: Bool
        public let motion: Pack.MotionSpec
        public let surface: String
        public let wake: Wake
        public let reason: String
    }

    public let pack: Pack
    public private(set) var current: String
    public private(set) var stateAge: TimeInterval = 0
    /// Values for the knobs the pack declared in `tuning`. The Director divides a
    /// duration by the knob a state names in `scaleBy` - and never learns what any
    /// of them mean, which is what keeps Rule 1 intact while still letting a pack
    /// ship a "liveliness" slider.
    public var tuning: [String: Double] = [:]
    private var rng: SplitMix64

    public init(pack: Pack, seed: UInt64 = 0x9E3779B97F4A7C15) {
        self.pack = pack
        self.current = pack.initialState
        self.rng = SplitMix64(seed: seed)
    }

    // MARK: entering states

    public func start() -> Plan { plan(entering: current, reason: "initialState") }

    /// Enter `name`, resetting the state clock.
    public func enter(_ name: String, reason: String) -> Plan {
        current = name
        stateAge = 0
        return plan(entering: name, reason: reason)
    }

    private func plan(entering name: String, reason: String) -> Plan {
        guard let st = pack.states[name] else {
            return Plan(state: name, clip: "", quiescent: false, motion: .none,
                        surface: "floor", wake: .none, reason: "unknown state")
        }
        let clip = pack.clips[st.clip]
        var wake: Wake = .none

        if st.quiescent {
            // Defend the invariant the linter also enforces, because a hand-edited
            // pack can reach here without ever passing through packtool.
            wake = .none
        } else if let d = st.duration {
            if d.clipDriven {
                let ms = clip?.durations(default: pack.stage.defaultFrameMs).reduce(0, +) ?? 0
                wake = ms > 0 ? .after(Double(ms) / 1000) : .none
            } else {
                let span = max(0, d.maxMs - d.minMs)
                var ms = Double(d.minMs)
                    + (span > 0 ? Double(rng.next(upperBound: UInt64(span + 1))) : 0)
                if let knob = d.scaleBy, let value = tuning[knob], value > 0 {
                    ms /= value        // a higher knob means a livelier pet
                }
                wake = .after(max(0.016, ms / 1000))
            }
        } else if let clip, clip.loop == .none, !clip.frames.isEmpty {
            // A finite clip with no declared duration ends when the clip ends.
            let ms = clip.durations(default: pack.stage.defaultFrameMs).reduce(0, +)
            wake = ms > 0 ? .after(Double(ms) / 1000) : .none
        }

        return Plan(state: name, clip: st.clip, quiescent: st.quiescent,
                    motion: st.motion, surface: st.surface, wake: wake, reason: reason)
    }

    // MARK: transitions

    public func advanceTime(_ dt: TimeInterval) { stateAge += dt }

    /// The state's duration elapsed: pick a successor by weight among those whose
    /// guard passes. Returns nil if there is nowhere to go.
    public func timeout(_ ctx: Guard.Context) -> Plan? {
        guard let st = pack.states[current] else { return nil }
        var context = ctx; context.stateAge = stateAge
        let eligible = st.next.filter { t in
            t.weight > 0 && (t.when?.evaluate(context, random: { self.rng.nextUnit() }) ?? true)
        }
        guard let pick = weighted(eligible) else { return nil }
        return enter(pick.state, reason: "timeout")
    }

    /// An engine event arrived. The first interrupt that names it and whose guard
    /// passes wins - declaration order is the priority order, which keeps a pack's
    /// behaviour readable top to bottom.
    public func deliver(event name: String, value: Double? = nil,
                        _ ctx: Guard.Context) -> Plan? {
        guard let st = pack.states[current] else { return nil }
        var context = ctx; context.stateAge = stateAge
        for it in st.interrupts where it.on.name == name {
            if let threshold = it.on.value, let v = value {
                // Parameterised events are thresholds: near(60) fires at <= 60,
                // idle(300) and fast(1400) fire at >=.
                let satisfied = name.hasSuffix(".near") ? v <= threshold : v >= threshold
                if !satisfied { continue }
            }
            if let g = it.when, !g.evaluate(context, random: { self.rng.nextUnit() }) { continue }
            return enter(it.state, reason: "interrupt \(name)")
        }
        return nil
    }

    private func weighted(_ options: [Pack.Transition]) -> Pack.Transition? {
        let total = options.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        var r = rng.nextUnit() * total
        for o in options {
            r -= o.weight
            if r <= 0 { return o }
        }
        return options.last
    }
}

/// Small, fast, seedable. The engine owns randomness so behaviour is reproducible
/// in tests; packs supply weights, never entropy.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)   // 53 bits, [0, 1)
    }
}
