import Foundation

/// 1-bit alpha silhouettes, one per atlas cell, written by `packtool build`.
///
/// These exist because the engine does **not** rely on the window server routing
/// clicks through transparent pixels. That behaviour is undocumented and has
/// regressed on both Sonoma and Tahoe 26.3. Instead the pet window stays
/// `ignoresMouseEvents = true` and flips only while the cursor is inside the
/// silhouette - which costs one array lookup per mouse-move event.
public struct HitMask: Sendable {
    public let cellWidth: Int, cellHeight: Int
    private let cells: [[Bool]]

    public var count: Int { cells.count }

    public enum Failure: Error, CustomStringConvertible {
        case badMagic, badVersion(Int), truncated, invalid
        public var description: String {
            switch self {
            case .badMagic: return "not a mask file (bad magic)"
            case .badVersion(let v): return "unsupported mask version \(v)"
            case .truncated: return "mask data truncated"
            case .invalid: return "invalid or oversized mask data"
            }
        }
    }

    public init(data: Data) throws {
        guard data.count > 5, data.prefix(4) == Data("LMSK".utf8) else { throw Failure.badMagic }
        let version = Int(data[data.startIndex + 4])
        guard version == 1 else { throw Failure.badVersion(version) }

        var i = data.startIndex + 5
        func varint() throws -> Int {
            var n = 0, shift = 0
            while true {
                guard i < data.endIndex else { throw Failure.truncated }
                let b = data[i]; i += 1
                guard shift <= 56 else { throw Failure.invalid }
                n |= Int(b & 0x7F) << shift
                if b & 0x80 == 0 { return n }
                shift += 7
            }
        }
        cellWidth = try varint()
        cellHeight = try varint()
        let n = try varint()
        guard (1...1024).contains(cellWidth), (1...1024).contains(cellHeight),
              (1...4096).contains(n) else { throw Failure.invalid }
        let area = cellWidth * cellHeight
        guard area <= 32 * 1024 * 1024 / n else { throw Failure.invalid }

        var out: [[Bool]] = []
        out.reserveCapacity(n)
        for _ in 0..<n {
            var flat = [Bool](); flat.reserveCapacity(area)
            var value = false
            let runs = try varint()
            guard runs > 0, runs <= area + 1, runs <= data.endIndex - i else { throw Failure.invalid }
            for _ in 0..<runs {
                let run = try varint()
                guard run <= area - flat.count else { throw Failure.invalid }
                flat.append(contentsOf: repeatElement(value, count: run))
                value.toggle()
            }
            guard flat.count == area else { throw Failure.truncated }
            out.append(flat)
        }
        guard i == data.endIndex else { throw Failure.invalid }
        cells = out
    }

    /// Is `(x, y)`, in cell coordinates with the origin at the top-left, opaque?
    public func opaque(cell: Int, x: Int, y: Int) -> Bool {
        guard cell >= 0, cell < cells.count,
              x >= 0, x < cellWidth, y >= 0, y < cellHeight else { return false }
        return cells[cell][y * cellWidth + x]
    }

    public func opaqueCount(cell: Int) -> Int {
        guard cell >= 0, cell < cells.count else { return 0 }
        return cells[cell].lazy.filter { $0 }.count
    }
}
