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
        public let pixelPerfect: Bool
        public let scaleSteps: [Int]
        public let defaultScale: Int
        public let defaultFrameMs: Int

        enum CodingKeys: String, CodingKey {
            case cell, bodyHeight, ground, pixelPerfect, scaleSteps, defaultScale, defaultFrameMs
        }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            cell = try c.decode(Size.self, forKey: .cell)
            bodyHeight = try c.decode(Int.self, forKey: .bodyHeight)
            ground = try c.decode(Point.self, forKey: .ground)
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
        public let bind: Bind
        enum CodingKeys: String, CodingKey {
            case name, z, visibleIn, hiddenIn, hitTest, bind
        }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            z = try c.decodeIfPresent(Int.self, forKey: .z)
            visibleIn = try c.decodeIfPresent([String].self, forKey: .visibleIn) ?? []
            hiddenIn = try c.decodeIfPresent([String].self, forKey: .hiddenIn) ?? []
            hitTest = try c.decodeIfPresent(Bool.self, forKey: .hitTest) ?? true
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
        public let orientFrames: [String: Int]
        /// float — defaults mirror Schema/pack.schema.json
        public let rest: Point
        public let stiffness: Double, damping: Double, mass: Double
        public let lag: Double, maxOffset: Double, sleepThreshold: Double
        public let bob: Bob

        enum CodingKeys: String, CodingKey {
            case mode, parent, anchor, clip, frames, offset, orientFrames
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
            orientFrames = try c.decodeIfPresent([String: Int].self, forKey: .orientFrames) ?? [:]
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
    /// enforced by the schema at build time, not re-litigated here.
    public struct EventRef: Decodable, Sendable {
        public let name: String
        public let value: Double?
        public init(from d: Decoder) throws {
            if let s = try? d.singleValueContainer().decode(String.self) {
                name = s; value = nil; return
            }
            let c = try d.container(keyedBy: Key.self)
            guard let k = c.allKeys.first else {
                throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(),
                                                       debugDescription: "empty event")
            }
            name = k.stringValue
            if let n = try? c.decode(Double.self, forKey: k) { value = n }
            else if let b = try? c.decode(Bool.self, forKey: k) { value = b ? 1 : 0 }
            else { value = nil }
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
        public init(from d: Decoder) throws {
            if let s = try? d.singleValueContainer().decode(String.self), s == "clip" {
                clipDriven = true; minMs = 0; maxMs = 0; return
            }
            let c = try d.container(keyedBy: K.self)
            clipDriven = false
            minMs = try c.decode(Int.self, forKey: .minMs)
            maxMs = try c.decode(Int.self, forKey: .maxMs)
        }
        enum K: String, CodingKey { case minMs, maxMs }
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
        public let duration: Duration?
        public let next: [Transition]
        public let interrupts: [Interrupt]
        enum CodingKeys: String, CodingKey {
            case clip, motion, surface, facing, quiescent, duration, next, interrupts
        }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            clip = try c.decode(String.self, forKey: .clip)
            motion = try c.decodeIfPresent(MotionSpec.self, forKey: .motion) ?? .none
            surface = try c.decodeIfPresent(String.self, forKey: .surface) ?? "floor"
            facing = try c.decodeIfPresent(String.self, forKey: .facing) ?? "keep"
            quiescent = try c.decodeIfPresent(Bool.self, forKey: .quiescent) ?? false
            duration = try c.decodeIfPresent(Duration.self, forKey: .duration)
            next = try c.decodeIfPresent([Transition].self, forKey: .next) ?? []
            interrupts = try c.decodeIfPresent([Interrupt].self, forKey: .interrupts) ?? []
        }
    }

    public struct Sound: Decodable, Sendable {
        public let file: String
        public let volume: Double?
    }

    /// A scalar knob the pack wants surfaced in Settings. The engine renders a
    /// generic control for each, so it needs no idea what any of them mean.
    public struct Knob: Decodable, Sendable {
        public let label: String
        public let min: Double
        public let max: Double
        public let defaultValue: Double
        enum CodingKeys: String, CodingKey { case label, min, max, `default` }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            label = try c.decode(String.self, forKey: .label)
            min = try c.decode(Double.self, forKey: .min)
            max = try c.decode(Double.self, forKey: .max)
            defaultValue = try c.decode(Double.self, forKey: .default)
        }
    }

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
