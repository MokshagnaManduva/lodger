import AppKit
import LodgerEngine

/// Normal operation: a menu bar item and a character on screen.
///
/// The measurement paths in `main.swift` (`--pack`, `--soak`, `--headless`) stay as
/// they are, because the energy protocol depends on them.
func runApp(devPaths: [URL]) -> Never {
    let app = NSApplication.shared
    // No Dock icon and no app switcher entry. The bundle sets LSUIElement too, but
    // doing it here as well means the SwiftPM binary behaves the same when run
    // straight from the command line.
    app.setActivationPolicy(.accessory)

    let controller = AppController(extraSearchPaths: devPaths)
    controller.reload()

    var menuBar: MenuBar?
    menuBar = MenuBar(app: controller) {
        controller.pet?.stop()
        NSApplication.shared.terminate(nil)
    }
    _ = menuBar   // held for the lifetime of the process

    controller.activate(id: Preferences.packID)

    print("Lodger — \(controller.packs.count) character(s) installed")
    for p in controller.packs {
        let mark = p.pack.identity.id == controller.activeID ? "*" : " "
        // Print where it came from, so shadowing is visible rather than mysterious.
        print("  \(mark) \(p.pack.identity.id) \(p.pack.identity.version)  "
              + "[\(p.origin)]  \(p.root.deletingLastPathComponent().path)")
    }
    for f in controller.failures {
        print("  ! \(f.url.lastPathComponent): \(f.reason)")
    }
    if controller.packs.isEmpty {
        print("  drop a character folder into \(AppController.packsDirectory.path)")
    }
    print("menu bar item installed; nothing polls until you open the menu")

    app.run()
    exit(0)
}
