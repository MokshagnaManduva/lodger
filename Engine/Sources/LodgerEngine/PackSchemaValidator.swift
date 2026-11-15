import Foundation
import CoreFoundation

/// Deliberately limited to the keywords in our embedded schema. The generator
/// rejects unsupported keywords; this is not a general JSON Schema implementation.
enum PackSchemaValidator {
    static let schema = try! JSONSerialization.jsonObject(with: PackSchema.data) as! [String: Any]

    static func validate(_ value: Any) throws {
        var nodes = 0
        func bounded(_ v: Any, depth: Int) throws {
            nodes += 1
            guard depth <= 48, nodes <= 100_000 else { throw PackStore.Failure.invalid("manifest is too complex") }
            if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
                guard n.doubleValue.isFinite, abs(n.doubleValue) <= 1_000_000_000 else {
                    throw PackStore.Failure.invalid("manifest numbers must be finite and at most 1,000,000,000 in magnitude")
                }
            }
            if let d = v as? [String: Any] { for child in d.values { try bounded(child, depth: depth + 1) } }
            if let a = v as? [Any] { for child in a { try bounded(child, depth: depth + 1) } }
        }
        try bounded(value, depth: 0)
        try check(value, schema, "pack")
    }

    private static func equal(_ a: Any, _ b: Any) -> Bool {
        if let a = a as? NSNumber, let b = b as? NSNumber {
            return (CFGetTypeID(a) == CFBooleanGetTypeID()) == (CFGetTypeID(b) == CFBooleanGetTypeID()) && a == b
        }
        return (a as AnyObject).isEqual(b)
    }

    private static func check(_ value: Any, _ rule: [String: Any], _ path: String) throws {
        func require(_ ok: Bool, _ reason: String) throws {
            if !ok { throw PackStore.Failure.invalid("\(path): \(reason)") }
        }
        if let ref = rule["$ref"] as? String {
            let key = String(ref.dropFirst("#/$defs/".count))
            try check(value, (schema["$defs"] as! [String: Any])[key] as! [String: Any], path)
        }
        if let type = rule["type"] as? String {
            let n = value as? NSNumber
            let bool = n.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            let matches: Bool
            switch type {
            case "object": matches = value is [String: Any]
            case "array": matches = value is [Any]
            case "string": matches = value is String
            case "boolean": matches = bool
            case "number": matches = n != nil && !bool
            case "integer": matches = n != nil && !bool && n!.doubleValue.rounded() == n!.doubleValue
            default: matches = false
            }
            try require(matches, "expected \(type)")
        }
        if let constant = rule["const"] { try require(equal(value, constant), "expected \(constant)") }
        if let choices = rule["enum"] as? [Any] { try require(choices.contains { equal(value, $0) }, "unsupported value \(value)") }
        if let choices = rule["oneOf"] as? [[String: Any]] {
            let matches = choices.filter { (try? check(value, $0, path)) != nil }.count
            try require(matches == 1, "does not match an allowed form")
        }
        if let forbidden = rule["not"] as? [String: Any] {
            try require((try? check(value, forbidden, path)) == nil, "forbidden combination")
        }
        if let d = value as? [String: Any] {
            for key in rule["required"] as? [String] ?? [] { try require(d[key] != nil, "missing \(key)") }
            if let min = rule["minProperties"] as? Int { try require(d.count >= min, "must not be empty") }
            let properties = rule["properties"] as? [String: [String: Any]] ?? [:]
            for key in d.keys.sorted() {
                if let child = properties[key] { try check(d[key]!, child, "\(path).\(key)") }
                else if let child = rule["additionalProperties"] as? [String: Any] { try check(d[key]!, child, "\(path).\(key)") }
                else if let allowed = rule["additionalProperties"] as? Bool { try require(allowed, "unknown property \(key)") }
            }
        }
        if let a = value as? [Any] {
            if let min = rule["minItems"] as? Int { try require(a.count >= min, "must contain at least \(min) item(s)") }
            if rule["uniqueItems"] as? Bool == true {
                var seen = Set<Data>()
                for item in a {
                    let key = try JSONSerialization.data(withJSONObject: item, options: [.fragmentsAllowed, .sortedKeys])
                    try require(seen.insert(key).inserted, "duplicate item")
                }
            }
            if let child = rule["items"] as? [String: Any] {
                for (i, item) in a.enumerated() { try check(item, child, "\(path)[\(i)]") }
            }
        }
        if let s = value as? String {
            if let min = rule["minLength"] as? Int { try require(s.unicodeScalars.count >= min, "string is too short") }
            if let max = rule["maxLength"] as? Int { try require(s.unicodeScalars.count <= max, "string is too long") }
            if let pattern = rule["pattern"] as? String { try require(s.range(of: pattern, options: .regularExpression) == s.startIndex..<s.endIndex, "invalid string format") }
            if rule["format"] as? String == "uri" { try require(URL(string: s)?.scheme != nil, "expected absolute URI") }
        }
        if let n = value as? NSNumber {
            if let min = rule["minimum"] as? Double { try require(n.doubleValue >= min, "must be >= \(min)") }
            if let max = rule["maximum"] as? Double { try require(n.doubleValue <= max, "must be <= \(max)") }
            if let min = rule["exclusiveMinimum"] as? Double { try require(n.doubleValue > min, "must be > \(min)") }
        }
    }
}
