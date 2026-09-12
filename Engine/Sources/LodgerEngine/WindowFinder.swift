import AppKit
import CoreGraphics

/// Enumerates on-screen windows.
///
/// **This is called exactly once per interaction - at drag-drop - and never on a
/// timer.** Enumerating windows repeatedly is the poll that Rule 2 forbids, and it
/// is the reason the pet tracks exactly one window at a time: one window can be
/// *observed* (see `PerchTracker`), while "any window" can only be sampled.
///
/// Needs no permission. `CGWindowList` reports geometry freely; only window titles
/// require Screen Recording, and the engine never reads them for perching.
public enum WindowFinder {

    /// How many times the window list has been enumerated this session.
    ///
    /// Observable on purpose. Enumeration is meant to happen only inside a user
    /// interaction, so a soak that shows anything other than zero means a poll has
    /// crept in. The diagnostics line prints it.
    public private(set) nonisolated(unsafe) static var enumerations = 0

    /// On-screen windows, front to back.
    public static func windows() -> [Perch.Candidate] {
        enumerations += 1
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
        return raw.compactMap { entry in
            guard let id = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let b = entry[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat
            else { return nil }
            return Perch.Candidate(
                windowID: id,
                pid: pid,
                ownerName: entry[kCGWindowOwnerName as String] as? String ?? "",
                bounds: CGRect(x: x, y: y, width: w, height: h),
                layer: entry[kCGWindowLayer as String] as? Int ?? 0,
                onScreen: (entry[kCGWindowIsOnscreen as String] as? Bool) ?? true)
        }
    }

    /// Current geometry of one window, or nil if it is gone.
    public static func window(id: UInt32) -> Perch.Candidate? {
        windows().first { $0.windowID == id }
    }

    /// Height of the coordinate space `CGWindowList` reports in: the primary
    /// display's height, since its origin is that display's top-left.
    public static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
    }
}
