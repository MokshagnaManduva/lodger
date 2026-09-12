import AppKit
import ApplicationServices

/// Watches **one** window and reports when it moves or goes away.
///
/// One window, not all of them, and that is a performance requirement rather than
/// a preference. There is no system-wide "any window moved" notification, so
/// tracking every window means sampling `CGWindowList` on a timer forever - exactly
/// the poll Rule 2 forbids. Tracking a single window is event-driven: one
/// `AXObserver`, and while that window sits still our cost is zero.
///
/// The user picks the window by dragging the pet onto it, so the drag *is* the
/// selection mechanism and window enumeration happens once, inside an interaction.
///
/// Requires Accessibility. Without it `attach` returns `.needsPermission` and the
/// engine simply never emits `perch.acquired`; a pack that knows nothing about
/// perching is unaffected either way.
public final class PerchTracker {

    public enum Outcome: Equatable {
        case attached
        case needsPermission
        case notFound          // no AX window matched the CGWindowList entry
    }

    /// Fired when the tracked window moves or resizes. Event-driven, never polled.
    public var onMoved: ((Perch.Candidate) -> Void)?
    /// Fired once when the perch becomes unusable, for any reason at all.
    public var onLost: (() -> Void)?

    public private(set) var tracked: Perch.Candidate?
    private var observer: AXObserver?
    private var element: AXUIElement?
    private var appElement: AXUIElement?

    public static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Ask for Accessibility, showing the system prompt.
    ///
    /// Call this when the user drops the pet on a window - not at launch. The drop
    /// hit-test needs no permission, so the request can name what they just aimed
    /// at instead of appearing for no visible reason.
    @discardableResult
    public static func requestPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public init() {}
    deinit { detach() }

    // MARK: attach / detach

    public func attach(to candidate: Perch.Candidate) -> Outcome {
        detach()
        guard Self.hasPermission else { return .needsPermission }

        let app = AXUIElementCreateApplication(candidate.pid)
        guard let window = Self.axWindow(in: app, matching: candidate.bounds) else {
            return .notFound
        }

        var obs: AXObserver?
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverCreate(candidate.pid, { _, _, notification, refcon in
            guard let refcon else { return }
            let me = Unmanaged<PerchTracker>.fromOpaque(refcon).takeUnretainedValue()
            me.handle(notification as String)
        }, &obs) == .success, let obs else { return .notFound }

        for n in [kAXWindowMovedNotification, kAXWindowResizedNotification,
                  kAXWindowMiniaturizedNotification, kAXUIElementDestroyedNotification,
                  kAXApplicationHiddenNotification] {
            AXObserverAddNotification(obs, window, n as CFString, ctx)
        }
        // Application-level notifications have to be registered on the app element.
        for n in [kAXApplicationHiddenNotification, kAXApplicationDeactivatedNotification] {
            AXObserverAddNotification(obs, app, n as CFString, ctx)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)

        observer = obs
        element = window
        appElement = app
        tracked = candidate
        return .attached
    }

    public func detach() {
        if let obs = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        observer = nil
        element = nil
        appElement = nil
        tracked = nil
    }

    // MARK: events

    private func handle(_ notification: String) {
        switch notification {
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            guard let id = tracked?.windowID, let fresh = WindowFinder.window(id: id) else {
                lose(); return
            }
            // A window resized below the floor, or dragged off every display, is a
            // lost perch rather than a moved one. One event, every case.
            let screens = NSScreen.screens.map {
                Perch.flip($0.frame, screenHeight: WindowFinder.primaryScreenHeight)
            }
            guard Perch.stillValid(fresh, ownPID: ProcessInfo.processInfo.processIdentifier,
                                   screens: screens) else { lose(); return }
            tracked = fresh
            onMoved?(fresh)

        case kAXWindowMiniaturizedNotification, kAXUIElementDestroyedNotification,
             kAXApplicationHiddenNotification:
            lose()

        default:
            break
        }
    }

    private func lose() {
        detach()
        onLost?()
    }

    /// Map a `CGWindowList` entry to an `AXUIElement` by matching geometry.
    ///
    /// There is no public API bridging a `CGWindowID` to an accessibility element,
    /// so frame matching is the standard technique. It can pick the wrong window
    /// when an app has two exactly-coincident windows, which is rare and recovers
    /// on the next `perch.lost`.
    private static func axWindow(in app: AXUIElement, matching bounds: CGRect) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString,
                                            &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }

        for w in windows {
            guard let origin: CGPoint = axValue(w, kAXPositionAttribute, .cgPoint),
                  let size: CGSize = axValue(w, kAXSizeAttribute, .cgSize) else { continue }
            let frame = CGRect(origin: origin, size: size)
            if abs(frame.minX - bounds.minX) < 2, abs(frame.minY - bounds.minY) < 2,
               abs(frame.width - bounds.width) < 2, abs(frame.height - bounds.height) < 2 {
                // A standard window only - not a sheet, palette, popover or HUD.
                if let sub: String = axString(w, kAXSubroleAttribute),
                   sub != kAXStandardWindowSubrole as String {
                    continue
                }
                return w
            }
        }
        return nil
    }

    private static func axValue<T>(_ el: AXUIElement, _ attr: String,
                                   _ type: AXValueType) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &raw) == .success,
              let v = raw, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var out = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { out.deallocate() }
        guard AXValueGetValue(v as! AXValue, type, out) else { return nil }
        return out.pointee
    }

    private static func axString(_ el: AXUIElement, _ attr: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &raw) == .success
        else { return nil }
        return raw as? String
    }
}
