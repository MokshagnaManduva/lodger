import AppKit
import QuartzCore

/// Turns a clip into a layer that animates **in the render server**.
///
/// This is the mechanism the whole efficiency argument rests on. A
/// `CAKeyframeAnimation` on `contentsRect` with `calculationMode = .discrete`
/// steps the layer through atlas cells with no interpolation. Once the
/// transaction commits, the animation is serialised to the render server and
/// runs there - the app process contributes nothing per frame and can sleep.
///
/// Two rules follow, and both are load-bearing:
///
///  * A single-frame clip installs **no animation at all**. Not a one-value
///    keyframe animation - nothing. That is what makes a `quiescent` state cost
///    literally zero.
///  * Frame timing comes from per-frame `ms` in the pack. The engine never
///    exposes a frame rate, because scheduling belongs to the engine (Rule 2).
public enum SpriteLayer {

    /// Unit sub-rectangle of atlas cell `index`.
    ///
    /// Atlas cells are numbered row-major from the **top** - that is how the sheet
    /// looks and how `packtool build` writes it. But `contentsRect` lives in the
    /// layer's unit coordinate space, whose origin is **bottom-left** on macOS.
    /// Measured, not assumed: `lodger-selftest` renders each cell and compares it
    /// against the source pixels, and without this row flip cells 0 and 2 of a 2x2
    /// atlas come out swapped.
    public static func contentsRect(cell index: Int, columns: Int, rows: Int) -> CGRect {
        let col = index % columns, row = index / columns
        let flipped = rows - 1 - row
        return CGRect(x: CGFloat(col) / CGFloat(columns),
                      y: CGFloat(flipped) / CGFloat(rows),
                      width: 1 / CGFloat(columns),
                      height: 1 / CGFloat(rows))
    }

    /// Normalised keyframe times. Discrete mode holds `values[i]` from
    /// `keyTimes[i]` to `keyTimes[i+1]`, so there is one more time than value.
    public static func keyTimes(durationsMs: [Int]) -> [NSNumber] {
        let total = max(1, durationsMs.reduce(0, +))
        var t = 0, out: [NSNumber] = [0]
        for ms in durationsMs {
            t += ms
            out.append(NSNumber(value: Double(t) / Double(total)))
        }
        return out
    }

    public struct Installed {
        public let animated: Bool
        public let frameCount: Int
        public let totalMs: Int
    }

    /// Configure `layer` to show `clip`. Returns what was installed so callers
    /// (and the diagnostics HUD) can assert the zero-timer invariant.
    @discardableResult
    public static func install(clip: Pack.Clip, texture: Pack.Texture,
                               defaultFrameMs: Int, into layer: CALayer) -> Installed {
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.removeAnimation(forKey: "sprite")

        let rects = clip.frames.map {
            contentsRect(cell: $0.cell, columns: texture.columns, rows: texture.rows)
        }
        let ms = clip.durations(default: defaultFrameMs)

        guard rects.count > 1 else {
            // Static: set it and install nothing. No animation, no timer, no wake-ups.
            layer.contentsRect = rects.first ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            return Installed(animated: false, frameCount: rects.count,
                             totalMs: ms.first ?? 0)
        }

        let total = ms.reduce(0, +)
        let anim = CAKeyframeAnimation(keyPath: "contentsRect")
        anim.values = rects.map { NSValue(rect: $0) }
        anim.keyTimes = keyTimes(durationsMs: ms)
        anim.calculationMode = .discrete
        anim.duration = Double(total) / 1000.0
        anim.repeatCount = clip.loop == .none ? 1 : .infinity
        anim.autoreverses = clip.loop == .pingpong
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards

        layer.contentsRect = rects[0]
        layer.add(anim, forKey: "sprite")
        return Installed(animated: true, frameCount: rects.count, totalMs: total)
    }

    /// Load an atlas as a CGImage, nearest-neighbour friendly.
    public static func atlas(at url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
