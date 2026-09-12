import AppKit
import IOKit.ps

/// System conditions the engine turns into pack events.
///
/// Every one of these is an observer or a notification. Nothing here polls, and
/// nothing here is installed unless some reachable state in the loaded pack
/// actually asks for it - the same discipline the pointer monitor follows.
///
/// `app.occluded` is the one that earns its keep twice: a pet animating behind a
/// full-screen window is work nobody can see, so the engine stops the animation as
/// well as telling the pack.
public final class SystemEvents {

    public struct Wants: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let sleepWake  = Wants(rawValue: 1 << 0)
        public static let power      = Wants(rawValue: 1 << 1)
        public static let displays   = Wants(rawValue: 1 << 2)
        public static let space      = Wants(rawValue: 1 << 3)
        public static let occlusion  = Wants(rawValue: 1 << 4)
    }

    /// `(name, value)` pairs, matching the closed event vocabulary.
    public var onEvent: ((String, Double?) -> Void)?
    /// Raised separately from the pack event so the engine can stop animating.
    public var onOcclusionChanged: ((Bool) -> Void)?

    private var tokens: [NSObjectProtocol] = []
    private var runLoopSource: CFRunLoopSource?
    private var lastOnBattery: Bool?
    private weak var window: NSWindow?

    public private(set) var installed: Wants = []

    public init() {}
    deinit { uninstall() }

    public func install(_ wants: Wants, window: NSWindow?) {
        uninstall()
        self.window = window
        let ws = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default

        if wants.contains(.sleepWake) {
            tokens.append(ws.addObserver(forName: NSWorkspace.willSleepNotification,
                                         object: nil, queue: .main) { [weak self] _ in
                self?.onEvent?("system.willSleep", nil)
            })
            tokens.append(ws.addObserver(forName: NSWorkspace.didWakeNotification,
                                         object: nil, queue: .main) { [weak self] _ in
                self?.onEvent?("system.wake", nil)
            })
        }

        if wants.contains(.power) {
            tokens.append(nc.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                         object: nil, queue: .main) { [weak self] _ in
                let low = ProcessInfo.processInfo.isLowPowerModeEnabled
                self?.onEvent?("power.lowPowerMode", low ? 1 : 0)
            })
            installPowerSourceObserver()
        }

        if wants.contains(.displays) {
            tokens.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                         object: nil, queue: .main) { [weak self] _ in
                self?.onEvent?("display.changed", nil)
            })
        }

        if wants.contains(.space) {
            tokens.append(ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                         object: nil, queue: .main) { [weak self] _ in
                self?.onEvent?("space.changed", nil)
            })
        }

        if wants.contains(.occlusion), let window {
            tokens.append(nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                         object: window, queue: .main) { [weak self] n in
                guard let w = n.object as? NSWindow else { return }
                let visible = w.occlusionState.contains(.visible)
                self?.onOcclusionChanged?(!visible)
                self?.onEvent?("app.occluded", visible ? 0 : 1)
            })
        }

        installed = wants
    }

    public func uninstall() {
        for t in tokens {
            NotificationCenter.default.removeObserver(t)
            NSWorkspace.shared.notificationCenter.removeObserver(t)
        }
        tokens.removeAll()
        if let s = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .defaultMode)
            runLoopSource = nil
        }
        installed = []
    }

    // MARK: battery

    /// IOKit posts a run-loop source callback when a power source changes, so this
    /// is event-driven too - `NSProcessInfo` has no on-battery equivalent.
    private func installPowerSourceObserver() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ refcon in
            guard let refcon else { return }
            Unmanaged<SystemEvents>.fromOpaque(refcon).takeUnretainedValue().powerSourceChanged()
        }, ctx)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        runLoopSource = src
        lastOnBattery = Self.onBattery()
    }

    private func powerSourceChanged() {
        let now = Self.onBattery()
        guard now != lastOnBattery else { return }   // it fires for charge % too
        lastOnBattery = now
        onEvent?("power.onBattery", now ? 1 : 0)
    }

    public static func onBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue()
                    as? [String: Any] else { continue }
            if let state = d[kIOPSPowerSourceStateKey] as? String {
                return state == kIOPSBatteryPowerValue
            }
        }
        return false
    }
}
