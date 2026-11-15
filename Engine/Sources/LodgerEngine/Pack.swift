import Foundation

/// The in-memory model of a character pack manifest.
///
/// Everything here is data supplied by a folder someone dropped in. Nothing in
/// this file may know the name of any particular character.
public struct Pack: Decodable, Sendable {
    public let format: Int
    public let engineMin: String?
    public let requires: [String]
    public let identity: Identity
    public let stage: Stage
    public let textures: [String: Texture]
    public let clips: [String: Clip]
    public let parts: [Part]
    public let initialState: String
    public let states: [String: State]
    public let hitMasks: [String: String]
    public let sounds: [String: Sound]
    public let tuning: [String: Knob]

    public struct Identity: Decodable, Sendable {
        public let id: String, name: String, version: String
        public let author: String, license: String
        public let description: String?
        public let preview: String?
    }

    public struct Point: Decodable, Sendable {
        public let x: Double, y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }
    public struct Size: Decodable, Sendable { public let w: Int, h: Int }

    public struct Stage: Decodable, Sendable {
        public let cell: Size
        public let bodyHeight: Int
        public let ground: Point
        public let artFacing: String
        public let pixelPerfect: Bool
        public let scaleSteps: [Int]
        public let defaultScale: Int
        public let defaultFrameMs: Int

        enum CodingKeys: String, CodingKey {
            case cell, bodyHeight, ground, artFacing, pixelPerfect, scaleSteps
            case defaultScale, defaultFrameMs
        }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            cell = try c.decode(Size.self, forKey: .cell)
            bodyHeight = try c.decode(Int.self, forKey: .bodyHeight)
            ground = try c.decode(Point.self, forKey: .ground)
            artFacing = try c.decodeIfPresent(String.self, forKey: .artFacing) ?? "left"
            pixelPerfect = try c.decodeIfPresent(Bool.self, forKey: .pixelPerfect) ?? true
            scaleSteps = try c.decodeIfPresent([Int].self, forKey: .scaleSteps) ?? [1, 2, 3]
            defaultScale = try c.decodeIfPresent(Int.self, forKey: .defaultScale) ?? 2
            defaultFrameMs = try c.decodeIfPresent(Int.self, forKey: .defaultFrameMs) ?? 250
        }
    }

    public struct Texture: Decodable, Sendable {
        public let file: String
        public let columns: Int, rows: Int
        public let preload: Bool
        enum CodingKeys: String, CodingKey { case file, columns, rows, preload }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            file = try c.decode(String.self, forKey: .file)
            columns = try c.decode(Int.self, forKey: .columns)
            rows = try c.decode(Int.self, forKey: .rows)
            preload = try c.decodeIfPresent(Bool.self, forKey: .preload) ?? false
        }
        public var cellCount: Int { columns * rows }
    }

    public enum Loop: String, Decodable, Sendable { case none, forever, pingpong }

    public struct Frame: Decodable, Sendable {
        public let cell: Int
        public let ms: Int?
        public let anchors: [String: Point]
        public let sound: String?
        enum CodingKeys: String, CodingKey { case cell, ms, anchors, sound }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            cell = try c.decode(Int.self, forKey: .cell)
            ms = try c.decodeIfPresent(Int.self, forKey: .ms)
            anchors = try c.decodeIfPresent([String: Point].self, forKey: .anchors) ?? [:]
            sound = try c.decodeIfPresent(String.self, forKey: .sound)
        }
    }

    public struct Clip: Decodable, Sendable {
        public let texture: String
        public let loop: Loop
        public let mirrorable: Bool
        public let frames: [Frame]
        enum CodingKeys: String, CodingKey { case texture, loop, mirrorable, frames }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            texture = try c.decode(String.self, forKey: .texture)
            loop = try c.decodeIfPresent(Loop.self, forKey: .loop) ?? Loop.none
            mirrorable = try c.decodeIfPresent(Bool.self, forKey: .mirrorable) ?? true
            frames = try c.decode([Frame].self, forKey: .frames)
        }
        /// Per-frame hold durations, filling in the pack default.
        public func durations(default d: Int) -> [Int] { frames.map { $0.ms ?? d } }
    }

    public struct Part: Decodable, Sendable {
        public let name: String
        public let z: Int?
        public let visibleIn: [String]
        public let hiddenIn: [String]
        public let hitTest: Bool
        /// When the body flips to face the other way, does this part swap sides too?
        public let mirrorWithBody: Bool
        public let bind: Bind
        enum CodingKeys: String, CodingKey {
            case name, z, visibleIn, hiddenIn, hitTest, mirrorWithBody, bind
        }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            z = try c.decodeIfPresent(Int.self, forKey: .z)
            visibleIn = try c.decodeIfPresent([String].self, forKey: .visibleIn) ?? []
            hiddenIn = try c.decodeIfPresent([String].self, forKey: .hiddenIn) ?? []
            hitTest = try c.decodeIfPresent(Bool.self, forKey: .hitTest) ?? true
            mirrorWithBody = try c.decodeIfPresent(Bool.self, forKey: .mirrorWithBody) ?? true
            bind = try c.decode(Bind.self, forKey: .bind)
        }
        public func visible(in state: String) -> Bool {
            visibleIn.isEmpty ? !hiddenIn.contains(state) : visibleIn.contains(state)
        }
    }

    public struct Bob: Decodable, Sendable {
        public let amplitudeX: Double, amplitudeY: Double
        public let periodMs: Int, phase: Double
        enum CodingKeys: String, CodingKey { case amplitudeX, amplitudeY, periodMs, phase }
        public init() { amplitudeX = 0; amplitudeY = 0; periodMs = 2000; phase = 0 }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            amplitudeX = try c.decodeIfPresent(Double.self, forKey: .amplitudeX) ?? 0
            amplitudeY = try c.decodeIfPresent(Double.self, forKey: .amplitudeY) ?? 0
            periodMs = try c.decodeIfPresent(Int.self, forKey: .periodMs) ?? 2000
            phase = try c.decodeIfPresent(Double.self, forKey: .phase) ?? 0
        }
    }

    public struct Bind: Decodable, Sendable {
        public let mode: String            // body | socket | float | overlay
        public let parent: String
        public let anchor: String?
        public let clip: String?
        /// socket
        public let frames: String          // "parent" | "clip"
        public let offset: Point
        /// float — defaults mirror Schema/pack.schema.json
        public let rest: Point
        public let stiffness: Double, damping: Double, mass: Double
        public let lag: Double, maxOffset: Double, sleepThreshold: Double
        public let bob: Bob

        enum CodingKeys: String, CodingKey {
            case mode, parent, anchor, clip, frames, offset
            case rest, stiffness, damping, mass, lag, maxOffset, sleepThreshold, bob
        }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            mode = try c.decode(String.self, forKey: .mode)
            parent = try c.decodeIfPresent(String.self, forKey: .parent) ?? "body"
            anchor = try c.decodeIfPresent(String.self, forKey: .anchor)
            clip = try c.decodeIfPresent(String.self, forKey: .clip)
            frames = try c.decodeIfPresent(String.self, forKey: .frames) ?? "parent"
            offset = try c.decodeIfPresent(Point.self, forKey: .offset) ?? Point(x: 0, y: 0)
            rest = try c.decodeIfPresent(Point.self, forKey: .rest) ?? Point(x: 0, y: 0)
            stiffness = try c.decodeIfPresent(Double.self, forKey: .stiffness) ?? 90
            damping = try c.decodeIfPresent(Double.self, forKey: .damping) ?? 12
            mass = try c.decodeIfPresent(Double.self, forKey: .mass) ?? 1
            lag = try c.decodeIfPresent(Double.self, forKey: .lag) ?? 0.08
            maxOffset = try c.decodeIfPresent(Double.self, forKey: .maxOffset) ?? 24
            sleepThreshold = try c.decodeIfPresent(Double.self, forKey: .sleepThreshold) ?? 0.15
            bob = try c.decodeIfPresent(Bob.self, forKey: .bob) ?? Bob()
        }
    }

    /// An engine event reference from a pack, e.g. `"pointer.click"` or
    /// `{"pointer.near": 60}`. Stored losslessly; the closed vocabulary is
    /// enforced by PackStore before decoding, as well as by the author tools.
    public struct EventRef: Decodable, Sendable {
        public let name: String
        public let value: Double?
        /// A slider in `tuning` supplying the threshold instead of a literal, so a
        /// pack can expose "after how long" without the engine knowing the word.
        public let knob: String?
        private struct KnobRef: Decodable { let knob: String }
        public init(from d: Decoder) throws {
            if let s = try? d.singleValueContainer().decode(String.self) {
                name = s; value = nil; knob = nil; return
            }
            let c = try d.container(keyedBy: Key.self)
            guard let k = c.allKeys.first else {
                throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(),
                                                       debugDescription: "empty event")
            }
            name = k.stringValue
            if let n = try? c.decode(Double.self, forKey: k) { value = n; knob = nil }
            else if let b = try? c.decode(Bool.self, forKey: k) { value = b ? 1 : 0; knob = nil }
            else if let r = try? c.decode(KnobRef.self, forKey: k) { value = nil; knob = r.knob }
            else { value = nil; knob = nil }
        }
        /// The threshold in force. A knob with no value resolves to nil, and a
        /// parameterised interrupt with no threshold never fires.
        public func threshold(_ tuning: [String: Double]) -> Double? {
            if let knob { return tuning[knob] }
            return value
        }
        struct Key: CodingKey {
            let stringValue: String; let intValue: Int? = nil
            init?(stringValue s: String) { stringValue = s }
            init?(intValue: Int) { return nil }
        }
    }

    public struct Transition: Decodable, Sendable {
        public let state: String
        public let weight: Double
        /// Name of a slider in `tuning` to multiply this weight by. Zero removes
        /// the option; the engine never learns what the slider means.
        public let weightBy: String?
        public let when: Guard?
    }
    public struct Interrupt: Decodable, Sendable {
        public let on: EventRef
        public let state: String
        public let when: Guard?
    }

    public struct Duration: Decodable, Sendable {
        public let clipDriven: Bool
        public let minMs: Int, maxMs: Int
        /// Name of a knob in `tuning` to divide this duration by. The engine applies
        /// it without ever learning what the knob means - which is how a pack gets
        /// a "liveliness" slider without the engine knowing the word.
        public let scaleBy: String?
        public init(from d: Decoder) throws {
            if let s = try? d.singleValueContainer().decode(String.self), s == "clip" {
                clipDriven = true; minMs = 0; maxMs = 0; scaleBy = nil; return
            }
            let c = try d.container(keyedBy: K.self)
            clipDriven = false
            minMs = try c.decode(Int.self, forKey: .minMs)
            maxMs = try c.decode(Int.self, forKey: .maxMs)
            scaleBy = try c.decodeIfPresent(String.self, forKey: .scaleBy)
        }
        enum K: String, CodingKey { case minMs, maxMs, scaleBy }
    }

    /// A state's declared motion. The pack states intent; the engine owns the
    /// integration and, critically, the scheduling.
    public enum MotionSpec: Decodable, Sendable {
        case none
        case walk(speed: Double, direction: String)
        case fall(gravity: Double, terminal: Double)
        case drag

        private struct Body: Decodable {
            let type: String
            let speed: Double?, direction: String?
            let gravity: Double?, terminal: Double?
        }
        public init(from d: Decoder) throws {
            if let s = try? d.singleValueContainer().decode(String.self) {
                self = s == "none" ? .none : .none
                return
            }
            let b = try d.singleValueContainer().decode(Body.self)
            switch b.type {
            case "walk": self = .walk(speed: b.speed ?? 20, direction: b.direction ?? "random")
            case "fall": self = .fall(gravity: b.gravity ?? 900, terminal: b.terminal ?? 700)
            case "drag": self = .drag
            default: self = .none
            }
        }
    }

    public struct State: Decodable, Sendable {
        public let clip: String
        public let motion: MotionSpec
        public let surface: String
        public let facing: String
        public let quiescent: Bool
        public let sound: String?
        public let duration: Duration?
        public let next: [Transition]
        public let interrupts: [Interrupt]
        enum CodingKeys: String, CodingKey {
            case clip, motion, surface, facing, quiescent, sound, duration, next, interrupts
        }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            clip = try c.decode(String.self, forKey: .clip)
            motion = try c.decodeIfPresent(MotionSpec.self, forKey: .motion) ?? .none
            surface = try c.decodeIfPresent(String.self, forKey: .surface) ?? "floor"
            facing = try c.decodeIfPresent(String.self, forKey: .facing) ?? "keep"
            quiescent = try c.decodeIfPresent(Bool.self, forKey: .quiescent) ?? false
            sound = try c.decodeIfPresent(String.self, forKey: .sound)
            duration = try c.decodeIfPresent(Duration.self, forKey: .duration)
            next = try c.decodeIfPresent([Transition].self, forKey: .next) ?? []
            interrupts = try c.decodeIfPresent([Interrupt].self, forKey: .interrupts) ?? []
        }
    }

    public struct Sound: Decodable, Sendable {
        public let file: String
        public let volume: Double?
        public let maxConcurrent: Int
        enum CodingKeys: String, CodingKey { case file, volume, maxConcurrent }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            file = try c.decode(String.self, forKey: .file)
            volume = try c.decodeIfPresent(Double.self, forKey: .volume)
            maxConcurrent = try c.decodeIfPresent(Int.self, forKey: .maxConcurrent) ?? 1
        }
    }

    /// A control the pack wants surfaced in Settings: a numeric slider or an
    /// on/off toggle. The host renders a generic control for each, so neither it
    /// nor the engine needs any idea what one means.
    public struct Knob: Decodable, Sendable {
        public enum Kind: Sendable, Equatable {
            case slider(min: Double, max: Double, defaultValue: Double)
            case toggle(defaultValue: Bool)
        }
        public let label: String
        public let kind: Kind
        /// Display only. Never interpreted by the engine.
        public let group: String?
        public let description: String?
        public let unit: String?

        public var isToggle: Bool { if case .toggle = kind { return true } else { return false } }
        public var min: Double { if case .slider(let v, _, _) = kind { return v } else { return 0 } }
        public var max: Double { if case .slider(_, let v, _) = kind { return v } else { return 1 } }
        public var defaultValue: Double {
            switch kind {
            case .slider(_, _, let v): return v
            case .toggle(let on): return on ? 1 : 0
            }
        }
        public var defaultFlag: Bool? { if case .toggle(let on) = kind { return on } else { return nil } }

        enum CodingKeys: String, CodingKey { case type, label, min, max, `default`, group, description, unit }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            label = try c.decode(String.self, forKey: .label)
            group = try c.decodeIfPresent(String.self, forKey: .group)
            description = try c.decodeIfPresent(String.self, forKey: .description)
            unit = try c.decodeIfPresent(String.self, forKey: .unit)
            switch try c.decodeIfPresent(String.self, forKey: .type) ?? "slider" {
            case "slider":
                kind = .slider(min: try c.decode(Double.self, forKey: .min),
                               max: try c.decode(Double.self, forKey: .max),
                               defaultValue: try c.decode(Double.self, forKey: .default))
            case "toggle":
                guard !c.contains(.min), !c.contains(.max), !c.contains(.unit) else {
                    throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                        debugDescription: "a toggle has no min, max or unit")
                }
                kind = .toggle(defaultValue: try c.decode(Bool.self, forKey: .default))
            case let other:
                throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                    debugDescription: "unknown control type '\(other)'")
            }
        }
    }

    /// Names of the controls some state actually uses: through `scaleBy`,
    /// `weightBy`, an event threshold or a `flag` guard. A host shows only these,
    /// so a declared-but-unused entry never appears as a control that does nothing.
    public var referencedControls: Set<String> {
        var out = Set<String>()
        func visit(_ g: Guard?) {
            switch g {
            case .flag(let name, _)?: out.insert(name)
            case .all(let gs)?, .any(let gs)?: gs.forEach { visit($0) }
            case .not(let inner)?: visit(inner)
            default: break
            }
        }
        for st in states.values {
            if let knob = st.duration?.scaleBy { out.insert(knob) }
            for edge in st.next { visit(edge.when); if let knob = edge.weightBy { out.insert(knob) } }
            for edge in st.interrupts { visit(edge.when); if let knob = edge.on.knob { out.insert(knob) } }
        }
        return out.intersection(tuning.keys)
    }

    /// The pack's own slider defaults, by name.
    public var defaultTuning: [String: Double] {
        tuning.filter { !$0.value.isToggle }.mapValues(\.defaultValue)
    }
    /// The pack's own toggle defaults, by name.
    public var defaultFlags: [String: Bool] {
        tuning.compactMapValues(\.defaultFlag)
    }

    /// Every event name any state listens for, with the largest threshold per
    /// name under the given slider values. The engine installs observers only for
    /// what is actually wanted, so a pack that ignores the battery costs nothing
    /// to watch it.
    public func requestedEvents(tuning: [String: Double]) -> [String: Double?] {
        var out: [String: Double?] = [:]
        for st in states.values {
            for it in st.interrupts {
                let name = it.on.name, v = it.on.threshold(tuning)
                if let existing = out[name] ?? nil, let v {
                    out[name] = Swift.max(existing, v)
                } else if out[name] == nil {
                    out[name] = v
                }
            }
        }
        return out
    }
    public var requestedEvents: [String: Double?] { requestedEvents(tuning: defaultTuning) }

    enum CodingKeys: String, CodingKey {
        case format, engineMin, requires, identity, stage, textures, clips
        case parts, initialState, states, hitMasks, sounds, tuning
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        format = try c.decode(Int.self, forKey: .format)
        engineMin = try c.decodeIfPresent(String.self, forKey: .engineMin)
        requires = try c.decodeIfPresent([String].self, forKey: .requires) ?? []
        identity = try c.decode(Identity.self, forKey: .identity)
        stage = try c.decode(Stage.self, forKey: .stage)
        textures = try c.decode([String: Texture].self, forKey: .textures)
        clips = try c.decode([String: Clip].self, forKey: .clips)
        parts = try c.decode([Part].self, forKey: .parts)
        initialState = try c.decode(String.self, forKey: .initialState)
        states = try c.decode([String: State].self, forKey: .states)
        hitMasks = try c.decodeIfPresent([String: String].self, forKey: .hitMasks) ?? [:]
        sounds = try c.decodeIfPresent([String: Sound].self, forKey: .sounds) ?? [:]
        tuning = try c.decodeIfPresent([String: Knob].self, forKey: .tuning) ?? [:]
    }
}
