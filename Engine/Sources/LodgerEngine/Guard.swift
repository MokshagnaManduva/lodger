import Foundation

/// The closed guard vocabulary.
///
/// There is deliberately no expression language here. Shimeji's format lets a pack
/// write `Condition="#{mascot.environment.cursor.y < ...}"`, which is arbitrary
/// evaluation loaded from an untrusted folder - a security hole and, just as
/// importantly, a Rule 2 hole: a pack that can evaluate anything per frame can burn
/// the battery. Adding a case here is an engine change plus a format-version bump.
/// That cost is the point.
public indirect enum Guard: Decodable, Sendable {
    case random(Double)
    case stateAge(Comparison, seconds: Double)
    case pointerDistance(Comparison, px: Double)
    case pointerSide(Side)
    case onEdge(Surface)
    case facing(Side)
    case perched(Bool)
    case lowPower(Bool)
    case flag(name: String, value: Bool)
    case timeOfDay(from: Minutes, to: Minutes)
    case all([Guard])
    case any([Guard])
    case not(Guard)

    public enum Comparison: String, Decodable, Sendable {
        case lt, lte, gt, gte, eq
        public func callAsFunction(_ a: Double, _ b: Double) -> Bool {
            switch self {
            case .lt:  return a < b
            case .lte: return a <= b
            case .gt:  return a > b
            case .gte: return a >= b
            case .eq:  return abs(a - b) < .ulpOfOne
            }
        }
    }
    public enum Side: String, Decodable, Sendable { case left, right }
    public enum Surface: String, Decodable, Sendable {
        case floor, windowTop, ceiling, wallLeft, wallRight
    }

    /// Minutes since midnight, so a window can wrap past midnight.
    public struct Minutes: Sendable, Equatable {
        public let value: Int
        public init?(_ hhmm: String) {
            let parts = hhmm.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
                  (0...23).contains(h), (0...59).contains(m) else { return nil }
            value = h * 60 + m
        }
    }

    // MARK: decoding

    struct Key: CodingKey {
        let stringValue: String; let intValue: Int? = nil
        init?(stringValue s: String) { stringValue = s }
        init?(intValue: Int) { return nil }
    }
    private struct OpValue: Decodable { let op: Comparison; let sec: Double?; let px: Double? }
    private struct FlagValue: Decodable { let name: String; let value: Bool }
    private struct TimeValue: Decodable { let from: String; let to: String }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        guard let key = c.allKeys.first, c.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "a guard is exactly one keyed object"))
        }
        switch key.stringValue {
        case "random":
            self = .random(try c.decode(Double.self, forKey: key))
        case "stateAge":
            let v = try c.decode(OpValue.self, forKey: key)
            self = .stateAge(v.op, seconds: v.sec ?? 0)
        case "pointerDistance":
            let v = try c.decode(OpValue.self, forKey: key)
            self = .pointerDistance(v.op, px: v.px ?? 0)
        case "pointerSide": self = .pointerSide(try c.decode(Side.self, forKey: key))
        case "onEdge":      self = .onEdge(try c.decode(Surface.self, forKey: key))
        case "facing":      self = .facing(try c.decode(Side.self, forKey: key))
        case "perched":     self = .perched(try c.decode(Bool.self, forKey: key))
        case "lowPower":    self = .lowPower(try c.decode(Bool.self, forKey: key))
        case "flag":
            let v = try c.decode(FlagValue.self, forKey: key)
            self = .flag(name: v.name, value: v.value)
        case "timeOfDay":
            let v = try c.decode(TimeValue.self, forKey: key)
            guard let f = Minutes(v.from), let t = Minutes(v.to) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: c,
                    debugDescription: "timeOfDay wants HH:MM")
            }
            self = .timeOfDay(from: f, to: t)
        case "all": self = .all(try c.decode([Guard].self, forKey: key))
        case "any": self = .any(try c.decode([Guard].self, forKey: key))
        case "not": self = .not(try c.decode(Guard.self, forKey: key))
        default:
            throw DecodingError.dataCorruptedError(forKey: key, in: c,
                debugDescription: "unknown guard '\(key.stringValue)'. The vocabulary is "
                    + "closed; adding to it is an engine change and a format-version bump.")
        }
    }

    // MARK: evaluation

    /// Everything a guard is allowed to ask about. Nothing else is reachable from
    /// a pack, which is what keeps evaluation cheap and bounded.
    public struct Context: Sendable {
        public var stateAge: TimeInterval = 0
        public var pointerDistance: Double? = nil
        public var pointerSide: Side? = nil
        public var edge: Surface = .floor
        public var facing: Side = .left
        public var perched: Bool = false
        public var lowPower: Bool = false
        public var flags: [String: Bool] = [:]
        public var minutesSinceMidnight: Int = 0
        public init() {}
    }

    public func evaluate(_ ctx: Context, random: () -> Double) -> Bool {
        switch self {
        case .random(let p):
            return random() < p
        case .stateAge(let op, let sec):
            return op(ctx.stateAge, sec)
        case .pointerDistance(let op, let px):
            // No pointer information means the guard cannot be satisfied, rather
            // than silently passing.
            guard let d = ctx.pointerDistance else { return false }
            return op(d, px)
        case .pointerSide(let s):  return ctx.pointerSide == s
        case .onEdge(let s):       return ctx.edge == s
        case .facing(let s):       return ctx.facing == s
        case .perched(let b):      return ctx.perched == b
        case .lowPower(let b):     return ctx.lowPower == b
        case .flag(let n, let v):  return (ctx.flags[n] ?? false) == v
        case .timeOfDay(let f, let t):
            let m = ctx.minutesSinceMidnight
            return f.value <= t.value ? (m >= f.value && m < t.value)
                                      : (m >= f.value || m < t.value)   // wraps midnight
        case .all(let gs): return gs.allSatisfy { $0.evaluate(ctx, random: random) }
        case .any(let gs): return gs.contains { $0.evaluate(ctx, random: random) }
        case .not(let g):  return !g.evaluate(ctx, random: random)
        }
    }
}
