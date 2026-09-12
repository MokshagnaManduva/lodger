import AppKit
import LodgerEngine

/// The menu bar item - the app's only permanent UI.
///
/// The menu's contents are rebuilt in `menuNeedsUpdate`, i.e. when the user opens
/// it, and never on a timer. A status item that refreshes itself on a schedule is
/// the classic way a background app quietly costs power all day; this one costs
/// nothing until clicked.
final class MenuBar: NSObject, NSMenuDelegate {

    private let item: NSStatusItem
    private let app: AppController
    private var onQuit: () -> Void

    init(app: AppController, onQuit: @escaping () -> Void) {
        self.app = app
        self.onQuit = onQuit
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let image = NSImage(systemSymbolName: "pawprint.fill",
                               accessibilityDescription: "Lodger") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "Lodger"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    // MARK: building on demand

    func menuNeedsUpdate(_ menu: NSMenu) {
        app.reload()
        menu.removeAllItems()

        if app.packs.isEmpty {
            let empty = NSMenuItem(title: "No characters installed", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let header = NSMenuItem(title: "Character", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for loaded in app.packs {
                let id = loaded.pack.identity.id
                let mi = NSMenuItem(title: "  " + loaded.pack.identity.name,
                                    action: #selector(pick(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = id
                mi.state = id == app.activeID ? .on : .off
                mi.toolTip = "\(id) \(loaded.pack.identity.version) — \(loaded.origin)"
                menu.addItem(mi)
            }
        }

        // Anything that looks like a pack but will not load says why, rather than
        // being silently skipped.
        if !app.failures.isEmpty {
            menu.addItem(.separator())
            let h = NSMenuItem(title: "Will not load", action: nil, keyEquivalent: "")
            h.isEnabled = false
            menu.addItem(h)
            for f in app.failures {
                let mi = NSMenuItem(title: "  \(f.url.lastPathComponent): \(f.reason)",
                                    action: nil, keyEquivalent: "")
                mi.isEnabled = false
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        add(menu, "Add Character…", #selector(addCharacter))
        add(menu, "Reveal Characters Folder", #selector(revealFolder))

        menu.addItem(.separator())
        let perch = add(menu, "Perch on Windows", #selector(togglePerch))
        perch.state = Preferences.perchMode ? .on : .off
        if let pet = app.pet, !pet.packSupportsPerching {
            perch.isEnabled = false
            perch.toolTip = "This character does not declare the windowEdges capability."
        } else if !PerchTracker.hasPermission {
            perch.toolTip = "Needs Accessibility. You will be asked when you drop the "
                          + "character on a window."
        }

        let audio = add(menu, "Sound", #selector(toggleAudio))
        audio.state = Preferences.audioEnabled ? .on : .off

        menu.addItem(.separator())
        menu.addItem(diagnostics())

        menu.addItem(.separator())
        add(menu, "Quit Lodger", #selector(quit)).keyEquivalent = "q"
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        menu.addItem(mi)
        return mi
    }

    /// Sampled when the menu opens, so the invariants are inspectable without
    /// anything running in the background to keep them fresh.
    private func diagnostics() -> NSMenuItem {
        let parent = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let cpu = ProcessInfo.processInfo
        var lines: [String] = []
        if let pet = app.pet {
            lines.append("state: \(pet.director.current)")
            lines.append("live timers: \(pet.scheduler.liveTimers)")
            lines.append("display link: \(pet.hasDisplayLink ? "running" : "none")")
            lines.append("walking: \(pet.isWalking)   perched: \(pet.isPerched)")
            lines.append("pointer monitor: \(pet.pointer.installed ? "installed" : "off")")
        } else {
            lines.append("no character running")
        }
        lines.append("window enumerations: \(WindowFinder.enumerations)")
        lines.append("accessibility: \(PerchTracker.hasPermission ? "granted" : "not granted")")
        lines.append("low power mode: \(cpu.isLowPowerModeEnabled)")
        for l in lines {
            let mi = NSMenuItem(title: l, action: nil, keyEquivalent: "")
            mi.isEnabled = false
            sub.addItem(mi)
        }
        parent.submenu = sub
        return parent
    }

    // MARK: actions

    @objc private func pick(_ sender: NSMenuItem) {
        app.activate(id: sender.representedObject as? String)
    }

    @objc private func addCharacter() {
        // Installing a character is dropping a folder in. The picker just saves the
        // user a trip to the Finder; copying is all it does.
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Install"
        panel.message = "Choose one or more character pack folders."
        guard panel.runModal() == .OK else { return }
        for src in panel.urls {
            let dst = AppController.packsDirectory.appendingPathComponent(src.lastPathComponent)
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: src, to: dst)
        }
        app.reload()
    }

    @objc private func revealFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([AppController.packsDirectory])
    }

    @objc private func togglePerch() {
        app.setPerchMode(!Preferences.perchMode)
    }

    @objc private func toggleAudio() {
        Preferences.audioEnabled = !Preferences.audioEnabled
        app.pet?.audio.enabled = Preferences.audioEnabled
            && (app.pet?.loaded.pack.requires.contains("audio") ?? false)
    }

    @objc private func quit() { onQuit() }
}
