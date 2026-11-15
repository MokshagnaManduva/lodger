import Foundation
import ImageIO
import CoreGraphics
import AVFoundation

/// Activation-time work only: no timers, polling or per-frame validation.
enum PackValidation {
    static let engineVersion = [1, 0, 0] // Pack API version, independent of app release version.
    static func validate(_ p: Pack, manifest: [String: Any], root: URL) throws {
        func require(_ ok: Bool, _ message: String) throws {
            if !ok { throw PackStore.Failure.invalid(message) }
        }
        if let minimum = p.engineMin {
            let version = minimum.split(separator: ".").compactMap { Int($0) }
            try require(version.count == 3 && !engineVersion.lexicographicallyPrecedes(version), "requires engine \(minimum); this engine supports pack API 1.0.0")
        }
        try require(Set(p.requires).isSubset(of: ["audio", "multiDisplay"]), "unsupported capability (window perching is unavailable)")
        try require((manifest["stage"] as? [String: Any])?["minPerchSize"] == nil, "stage.minPerchSize is unsupported")
        let w = p.stage.cell.w, h = p.stage.cell.h
        try require((1...1024).contains(w) && (1...1024).contains(h), "stage.cell dimensions must be 1...1024")
        try require(p.stage.bodyHeight <= h, "stage.bodyHeight exceeds cell height")
        try require((0...Double(w)).contains(p.stage.ground.x) && (0...Double(h)).contains(p.stage.ground.y), "stage.ground must lie within the cell")
        try require(!p.stage.scaleSteps.isEmpty && Set(p.stage.scaleSteps).count == p.stage.scaleSteps.count && p.stage.scaleSteps.contains(p.stage.defaultScale), "stage.scaleSteps must be unique, nonempty and contain defaultScale")
        try require(p.parts.count <= 64 && p.states.count <= 512 && p.clips.count <= 1024 && p.textures.count <= 64, "too many parts, states, clips or textures")
        try require(p.states[p.initialState] != nil, "initialState refers to missing state \(p.initialState)")
        try require(p.parts.filter { $0.bind.mode == "body" }.count == 1, "exactly one body part is required")
        try require(Set(p.parts.map(\.name)).count == p.parts.count, "part names must be unique")
        let bodyName = p.parts.first { $0.bind.mode == "body" }!.name
        for part in p.parts {
            let b = part.bind
            if b.mode == "float" {
                try require(b.mass >= 0.0001 && b.stiffness / b.mass <= 10_000 && b.damping / b.mass <= 200,
                            "part \(part.name): spring parameters exceed the stable solver range")
                try require(b.maxOffset + max(abs(b.rest.x), abs(b.rest.y)) <= 1024,
                            "part \(part.name): attachment margin exceeds 1024 pixels")
            }
            if b.mode != "body" { try require(b.parent == bodyName, "part \(part.name): only attachment to the body is supported") }
            if let clip = b.clip { try require(p.clips[clip] != nil, "part \(part.name): unknown clip \(clip)") }
            if b.mode == "float" || (b.mode == "socket" && b.frames == "clip") {
                try require(b.clip != nil, "part \(part.name): bind.clip is required")
            }
            for state in part.visibleIn + part.hiddenIn { try require(p.states[state] != nil, "part \(part.name): unknown visibility state \(state)") }
            if b.mode == "socket" || b.mode == "float" {
                for (name, state) in p.states where part.visible(in: name) {
                    if let clip = p.clips[state.clip] {
                        try require(clip.frames.allSatisfy { $0.anchors[b.anchor ?? ""] != nil }, "part \(part.name): missing anchor \(b.anchor ?? "") in state \(name)")
                    }
                }
            }
        }
        try require((max(w, h) + 2 * Body.attachmentMargin(for: p)) * (p.stage.scaleSteps.max() ?? 1) <= 8192,
                    "scaled stage including attachments exceeds 8192 pixels")
        try require(p.tuning.count <= 64, "too many tuning controls")
        for (name, knob) in p.tuning where !knob.isToggle {
            try require(knob.min <= knob.defaultValue && knob.defaultValue <= knob.max, "tuning.\(name): require min <= default <= max")
        }
        try validateControls(p, manifest: manifest)
        for (name, clip) in p.clips {
            guard let texture = p.textures[clip.texture] else { throw PackStore.Failure.invalid("clip \(name): unknown texture \(clip.texture)") }
            // Bounds below are checked before multiplying any dimensions.
            try require((1...4096).contains(texture.columns) && (1...4096).contains(texture.rows), "texture grid exceeds limits")
            try require(clip.frames.count <= 4096, "clip \(name): too many frames")
            var total = 0
            for frame in clip.frames {
                try require(frame.cell < texture.columns * texture.rows, "clip \(name): cell \(frame.cell) outside texture")
                if let sound = frame.sound { try require(p.sounds[sound] != nil, "clip \(name): unknown sound \(sound)") }
                total += frame.ms ?? p.stage.defaultFrameMs
            }
            try require(total <= 86_400_000, "clip \(name): duration exceeds one day")
        }
        for (name, state) in p.states {
            guard let clip = p.clips[state.clip] else { throw PackStore.Failure.invalid("state \(name): unknown clip \(state.clip)") }
            try require(state.surface != "windowTop", "state \(name): windowTop is unsupported")
            if let sound = state.sound { try require(p.sounds[sound] != nil, "state \(name): unknown sound \(sound)") }
            for target in state.next.map(\.state) + state.interrupts.map(\.state) {
                try require(p.states[target] != nil, "state \(name): unknown target \(target)")
            }
            if let d = state.duration, !d.clipDriven {
                try require(d.minMs <= d.maxMs && d.maxMs <= 86_400_000, "state \(name): invalid duration range (maximum one day)")
                if let knob = d.scaleBy { try require(p.tuning[knob] != nil && p.tuning[knob]!.min > 0 && Double(d.maxMs) / p.tuning[knob]!.min <= 86_400_000, "state \(name): duration scaleBy requires a positive tuning knob and scaled duration at most one day") }
            }
            if state.quiescent {
                let still: Bool
                if case .none = state.motion { still = true } else { still = false }
                try require(still && state.next.isEmpty && state.duration == nil && (clip.frames.count == 1 || clip.loop != .none), "state \(name): quiescent states require no motion, duration or next and a looping or single-frame clip")
            }
        }
        // Reject removed vocabulary even when nested in compound guards.
        func currentVocabulary(_ v: Any) throws {
            if let d = v as? [String: Any] {
                try require(d["perched"] == nil && d["onEdge"] as? String != "windowTop", "window perching guards are unsupported")
                for child in d.values { try currentVocabulary(child) }
            } else if let a = v as? [Any] { for child in a { try currentVocabulary(child) } }
        }
        for state in (manifest["states"] as! [String: [String: Any]]).values {
            for edge in (state["next"] as? [[String: Any]] ?? []) + (state["interrupts"] as? [[String: Any]] ?? []) {
                if let event = edge["on"] as? String { try require(!event.hasPrefix("perch."), "window perching events are unsupported") }
                if let guardValue = edge["when"] { try currentVocabulary(guardValue) }
            }
        }
        try require(p.sounds.isEmpty || p.requires.contains("audio"), "sounds require the audio capability")
        for (name, sound) in p.sounds {
            try require(sound.maxConcurrent <= 16, "sound \(name): maxConcurrent exceeds 16")
            let url = try PackFiles.file(sound.file, in: root)
            do { _ = try AVAudioPlayer(contentsOf: url) }
            catch { throw PackStore.Failure.invalid("sound \(name): cannot decode \(sound.file)") }
        }
        try require(Set(p.hitMasks.keys).isSubset(of: Set(p.textures.keys)), "hitMasks refers to an unknown texture")
        var totalPixels = 0
        for (name, texture) in p.textures {
            try require((1...4096).contains(texture.columns) && (1...4096).contains(texture.rows), "texture \(name): invalid grid")
            let width = texture.columns * w, height = texture.rows * h
            try require(width <= 8192 && height <= 8192 && texture.columns * texture.rows <= 4096, "texture \(name): atlas exceeds limits")
            totalPixels += width * height
            try require(totalPixels <= 32 * 1024 * 1024, "pack exceeds 32 megapixels of decoded textures")
            let image = try decodeImage(texture.file, root: root, width: width, height: height)
            if let file = p.hitMasks[name] {
                let mask: HitMask
                do { mask = try HitMask(data: PackFiles.data(file, in: root)) }
                catch { throw PackStore.Failure.invalid("\(file): \(error)") }
                try require(mask.cellWidth == w && mask.cellHeight == h && mask.count == texture.cellCount, "\(file): mask dimensions/count do not match texture")
                var alpha = [UInt8](repeating: 0, count: width * height * 4)
                let drawn = alpha.withUnsafeMutableBytes { bytes -> Bool in
                    guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                    return true
                }
                try require(drawn, "\(file): cannot inspect texture alpha")
                for cell in 0..<mask.count {
                    let ox = cell % texture.columns * w, oy = cell / texture.columns * h
                    for y in 0..<h { for x in 0..<w {
                        if mask.opaque(cell: cell, x: x, y: y) != (alpha[((oy + y) * width + ox + x) * 4 + 3] > 0) {
                            throw PackStore.Failure.invalid("\(file): mask silhouette does not match texture alpha")
                        }
                    } }
                }
            }
        }
        if let preview = (manifest["identity"] as? [String: Any])?["preview"] as? String {
            _ = try decodeImage(preview, root: root)
        }
    }

    /// Controls are referenced by name from four places. Each reference must name
    /// a control of the right kind, and the version 2 features must not appear in
    /// a pack that declares version 1.
    private static func validateControls(_ p: Pack, manifest: [String: Any]) throws {
        func require(_ ok: Bool, _ message: String) throws {
            if !ok { throw PackStore.Failure.invalid(message) }
        }
        func slider(_ name: String) -> Pack.Knob? {
            guard let knob = p.tuning[name], !knob.isToggle else { return nil }
            return knob
        }
        var usesVersion2 = false
        for entry in (manifest["tuning"] as? [String: [String: Any]] ?? [:]).values
        where !Set(entry.keys).isSubset(of: ["label", "min", "max", "default"]) { usesVersion2 = true }
        var flagNames = Set<String>()
        func collectFlags(_ g: Guard?) {
            switch g {
            case .flag(let name, _)?: flagNames.insert(name)
            case .all(let gs)?, .any(let gs)?: gs.forEach { collectFlags($0) }
            case .not(let inner)?: collectFlags(inner)
            default: break
            }
        }
        for (name, state) in p.states {
            if let knob = state.duration?.scaleBy {
                try require(slider(knob) != nil, "state \(name): scaleBy must name a slider declared in tuning")
            }
            for edge in state.next {
                collectFlags(edge.when)
                guard let knob = edge.weightBy else { continue }
                usesVersion2 = true
                try require(slider(knob).map { $0.min >= 0 } ?? false,
                            "state \(name): weightBy must name a slider with a non-negative range")
            }
            for edge in state.interrupts {
                collectFlags(edge.when)
                guard let knob = edge.on.knob else { continue }
                usesVersion2 = true
                try require(slider(knob).map { $0.min > 0 } ?? false,
                            "state \(name): event threshold must name a slider with a positive range")
            }
        }
        if p.format >= 2 {
            for name in flagNames.sorted() {
                try require(p.tuning[name]?.isToggle == true, "flag \(name) must name a toggle declared in tuning")
            }
        } else {
            try require(!usesVersion2, "typed tuning controls, weightBy and knob thresholds require format 2")
        }
    }

    private static func decodeImage(_ path: String, root: URL, width: Int? = nil, height: Int? = nil) throws -> CGImage {
        let data = try PackFiles.data(path, in: root)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= 8192, h <= 8192, w * h <= 32 * 1024 * 1024,
              width == nil || width == w, height == nil || height == h,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete else {
            throw PackStore.Failure.invalid("\(path): corrupt image or dimensions do not match atlas/limits")
        }
        return image
    }
}
