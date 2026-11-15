import Foundation
import LodgerEngine

/// User settings, in `UserDefaults`.
///
/// Lives in the app target, not the engine: the engine takes values, it does not
/// know where they came from. That keeps `Engine/` free of anything host-specific
/// and keeps it testable without a defaults domain.
struct Preferences {
    static var defaults = UserDefaults.standard
    private static var d: UserDefaults { defaults }

    private enum Key {
        static let packID = "pack.id"
        static let scales = "pack.scales"
        static let audio = "audio.enabled"
        static let volume = "audio.volume"
        static let tuning = "tuning"
        static let flags = "flags"
        static let appearance = "appearance"
        static let hidden = "pet.hidden"
        static let opacity = "pet.opacity"
        static let stayInPlace = "pet.stayInPlace"
        static let calmOnBattery = "pet.calmOnBattery"
    }

    static var packID: String? {
        get { d.string(forKey: Key.packID) }
        set { d.set(newValue, forKey: Key.packID) }
    }

    static func scale(for packID: String, defaultValue: Int) -> Int {
        let saved = (d.dictionary(forKey: Key.scales)?[packID] as? NSNumber)?.intValue
        return saved ?? defaultValue
    }

    static func setScale(_ scale: Int, for packID: String) {
        var all = d.dictionary(forKey: Key.scales) ?? [:]
        all[packID] = scale
        d.set(all, forKey: Key.scales)
    }

    /// Also off by default. An always-running background app that makes noise
    /// unprompted is the fastest route to being uninstalled.
    static var audioEnabled: Bool {
        get { d.bool(forKey: Key.audio) }
        set { d.set(newValue, forKey: Key.audio) }
    }

    static var volume: Double {
        get {
            let value = d.object(forKey: Key.volume) as? Double ?? 0.4
            return value.isFinite ? min(1, max(0, value)) : 0.4
        }
        set { if newValue.isFinite { d.set(min(1, max(0, newValue)), forKey: Key.volume) } }
    }

    // MARK: app-level options, for whichever character is running

    /// The character is not shown and nothing of it runs.
    static var hidden: Bool {
        get { d.bool(forKey: Key.hidden) }
        set { d.set(newValue, forKey: Key.hidden) }
    }

    static let opacityRange = 0.3...1.0
    static var opacity: Double {
        get {
            let value = d.object(forKey: Key.opacity) as? Double ?? 1
            return value.isFinite ? min(opacityRange.upperBound, max(opacityRange.lowerBound, value)) : 1
        }
        set { if newValue.isFinite { d.set(min(opacityRange.upperBound, max(opacityRange.lowerBound, newValue)), forKey: Key.opacity) } }
    }

    /// Never set off walking unprompted.
    static var stayInPlace: Bool {
        get { d.bool(forKey: Key.stayInPlace) }
        set { d.set(newValue, forKey: Key.stayInPlace) }
    }

    /// Change activity half as often while on battery power.
    static var calmOnBattery: Bool {
        get { d.bool(forKey: Key.calmOnBattery) }
        set { d.set(newValue, forKey: Key.calmOnBattery) }
    }
    static let batteryPace = 0.5

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

    /// Per-pack values for the toggles a pack declares in `tuning`. Stored apart
    /// from the sliders, so a control that changes kind between pack versions
    /// falls back to its new default instead of being misread.
    static func flags(for packID: String) -> [String: Bool] {
        (d.dictionary(forKey: Key.flags)?[packID] as? [String: Bool]) ?? [:]
    }

    static func setFlags(_ values: [String: Bool], for packID: String) {
        var all = d.dictionary(forKey: Key.flags) ?? [:]
        all[packID] = values
        d.set(all, forKey: Key.flags)
    }

    /// Per-pack look: appearance choice id -> option id.
    static func appearance(for packID: String) -> [String: String] {
        (d.dictionary(forKey: Key.appearance)?[packID] as? [String: String]) ?? [:]
    }

    static func setAppearance(_ values: [String: String], for packID: String) {
        var all = d.dictionary(forKey: Key.appearance) ?? [:]
        all[packID] = values
        d.set(all, forKey: Key.appearance)
    }

    /// Forget one control's saved value, of either kind.
    static func resetControl(_ name: String, for packID: String) {
        var sliders = tuning(for: packID), toggles = flags(for: packID)
        sliders.removeValue(forKey: name); toggles.removeValue(forKey: name)
        setTuning(sliders, for: packID); setFlags(toggles, for: packID)
    }

    /// Forget every saved control value, keeping the size.
    static func resetBehaviour(packID: String) {
        setTuning([:], for: packID); setFlags([:], for: packID)
    }

    static func reset(packID: String) {
        for key in [Key.scales, Key.tuning, Key.flags, Key.appearance] {
            var all = d.dictionary(forKey: key) ?? [:]
            all.removeValue(forKey: packID)
            d.set(all, forKey: key)
        }
    }

    /// Resolve a pack's sliders: stored value, else the pack's own default.
    static func resolvedTuning(for pack: Pack) -> [String: Double] {
        let stored = tuning(for: pack.identity.id)
        var out: [String: Double] = [:]
        for (name, knob) in pack.tuning where !knob.isToggle {
            let value = stored[name] ?? knob.defaultValue
            out[name] = value.isFinite ? min(knob.max, max(knob.min, value)) : knob.defaultValue
        }
        return out
    }

    /// Resolve a pack's toggles: stored value, else the pack's own default.
    static func resolvedFlags(for pack: Pack) -> [String: Bool] {
        let stored = flags(for: pack.identity.id)
        var out: [String: Bool] = [:]
        for (name, knob) in pack.tuning {
            if let fallback = knob.defaultFlag { out[name] = stored[name] ?? fallback }
        }
        return out
    }
}
