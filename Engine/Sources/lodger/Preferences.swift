import Foundation
import LodgerEngine

/// User settings, in `UserDefaults`.
///
/// Lives in the app target, not the engine: the engine takes values, it does not
/// know where they came from. That keeps `Engine/` free of anything host-specific
/// and keeps it testable without a defaults domain.
struct Preferences {
    private static let d = UserDefaults.standard

    private enum Key {
        static let packID = "pack.id"
        static let perchMode = "perch.enabled"
        static let audio = "audio.enabled"
        static let volume = "audio.volume"
        static let tuning = "tuning"
    }

    static var packID: String? {
        get { d.string(forKey: Key.packID) }
        set { d.set(newValue, forKey: Key.packID) }
    }

    /// Off by default: the app must ship asking for nothing. See CLAUDE.md 4a.
    static var perchMode: Bool {
        get { d.bool(forKey: Key.perchMode) }
        set { d.set(newValue, forKey: Key.perchMode) }
    }

    /// Also off by default. An always-running background app that makes noise
    /// unprompted is the fastest route to being uninstalled.
    static var audioEnabled: Bool {
        get { d.bool(forKey: Key.audio) }
        set { d.set(newValue, forKey: Key.audio) }
    }

    static var volume: Double {
        get { d.object(forKey: Key.volume) as? Double ?? 0.4 }
        set { d.set(newValue, forKey: Key.volume) }
    }

    /// Per-pack values for the knobs a pack declares in `tuning`. Keyed by pack id
    /// so switching characters does not clobber the other's settings.
    static func tuning(for packID: String) -> [String: Double] {
        (d.dictionary(forKey: Key.tuning)?[packID] as? [String: Double]) ?? [:]
    }

    static func setTuning(_ values: [String: Double], for packID: String) {
        var all = d.dictionary(forKey: Key.tuning) ?? [:]
        all[packID] = values
        d.set(all, forKey: Key.tuning)
    }

    /// Resolve a pack's tuning knobs: stored value, else the pack's own default.
    static func resolvedTuning(for pack: Pack) -> [String: Double] {
        let stored = tuning(for: pack.identity.id)
        var out: [String: Double] = [:]
        for (name, knob) in pack.tuning {
            out[name] = stored[name] ?? knob.defaultValue
        }
        return out
    }
}
