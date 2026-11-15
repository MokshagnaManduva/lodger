import CoreGraphics
import Foundation

/// Appearance options as colour maps.
///
/// A pack offers looks by mapping exact source colours to replacements. The map
/// is applied **once**, when an atlas is loaded - never per frame - and it never
/// touches alpha, so hit masks, anchors and frame timing stay valid whatever the
/// user picks. It is a lookup table: no expression, nothing a pack can compute.
public enum Recolor {
    /// 0xRRGGBB.
    public typealias Table = [UInt32: UInt32]

    /// `#rrggbb` -> 0xRRGGBB. Anything else is nil.
    public static func parse(_ hex: String) -> UInt32? {
        let digits = hex.dropFirst()
        guard hex.hasPrefix("#"), digits.count == 6,
              digits.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
        return UInt32(digits, radix: 16)
    }

    /// The image with every fully opaque pixel whose colour is a key replaced by
    /// its value. Returns the original when there is nothing to do.
    public static func apply(_ image: CGImage, table: Table) -> CGImage? {
        guard !table.isEmpty else { return image }
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                          | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        // Runs of one colour are the norm in pixel art: remember the last lookup.
        var lastKey: UInt32 = .max, lastValue: UInt32? = nil
        for i in 0..<(width * height) {
            let p = i * 4
            guard pixels[p + 3] == 255 else { continue }
            let key = UInt32(pixels[p]) << 16 | UInt32(pixels[p + 1]) << 8 | UInt32(pixels[p + 2])
            if key != lastKey { lastKey = key; lastValue = table[key] }
            guard let value = lastValue else { continue }
            pixels[p] = UInt8(value >> 16 & 0xFF)
            pixels[p + 1] = UInt8(value >> 8 & 0xFF)
            pixels[p + 2] = UInt8(value & 0xFF)
        }
        return context.makeImage()
    }
}

extension Pack {
    /// The merged colour map for a selection.
    public func recolorTable(selection: [String: String]) -> Recolor.Table {
        let resolved = resolvedAppearance(selection)
        var table: Recolor.Table = [:]
        for choice in appearance {
            guard let option = choice.options.first(where: { $0.id == resolved[choice.id] }) else { continue }
            for (from, to) in option.recolor {
                if let f = Recolor.parse(from), let t = Recolor.parse(to) { table[f] = t }
            }
        }
        return table
    }
}
