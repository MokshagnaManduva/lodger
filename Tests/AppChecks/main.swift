import AppKit
import LodgerEngine

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let temporary = root.appendingPathComponent("build/app-checks-" + UUID().uuidString)
try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
let suite = "com.mokshagna.lodger.tests." + UUID().uuidString
Preferences.defaults = UserDefaults(suiteName: suite)!
defer { Preferences.defaults.removePersistentDomain(forName: suite); try? fm.removeItem(at: temporary) }
var count = 0
func check(_ value: @autoclosure () -> Bool, _ name: String) {
    guard value() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
    count += 1; print("PASS: \(name)")
}
let controller = AppController(extraSearchPaths: [root.appendingPathComponent("Packs")],
                               installationDirectory: temporary.appendingPathComponent("Packs"), trash: { source in
    let trash = temporary.appendingPathComponent("Trash")
    try fm.createDirectory(at: trash, withIntermediateDirectories: true)
    try fm.moveItem(at: source, to: trash.appendingPathComponent(source.lastPathComponent))
})
controller.reload()
let menuBar = MenuBar(app: controller, onQuit: {})
let menu = NSMenu()
menuBar.menuNeedsUpdate(menu)
let originalItems = menu.items
let soundItem = originalItems.first { $0.title == "Sound" }!
let originalSoundState = soundItem.state
menuBar.menuWillOpen(menu)
Preferences.audioEnabled.toggle()
for _ in 0..<3 { menuBar.menuNeedsUpdate(menu) }
check(menu.items.count == originalItems.count && zip(menu.items, originalItems).allSatisfy { $0 === $1 },
      "open menu preserves item identities across update requests")
check(soundItem.state == originalSoundState, "open menu keeps its displayed snapshot stable")
menuBar.menuDidClose(menu)
menuBar.menuNeedsUpdate(menu)
check(menu.items.first { $0.title == "Sound" }!.state != originalSoundState,
      "reopened menu refreshes changed preferences")
Preferences.audioEnabled.toggle()
let ids = controller.packs.map { $0.pack.identity.id }
check(ids.count >= 2, "both development packs discover")
let first = ids[0], second = ids[1]
controller.activate(id: first)
let pack = controller.pet!.loaded.pack
let pos = CGPoint(x: controller.pet!.world.left + 60, y: controller.pet!.world.floor)
controller.pet!.place(at: pos)
let alternate = pack.stage.scaleSteps.first { $0 != pack.stage.defaultScale }!
controller.setScale(alternate, for: first)
check(controller.pet!.pointer.scale == CGFloat(alternate), "resize applies")
check(abs(controller.pet!.feet.x - pos.x) < 1, "resize preserves position")
controller.activate(id: second); controller.activate(id: first)
check(controller.pet!.pointer.scale == CGFloat(alternate), "switch preserves per-character size")
let relaunched = AppController(extraSearchPaths: [root.appendingPathComponent("Packs")], installationDirectory: controller.installationDirectory)
relaunched.reload()
check(relaunched.scale(for: first) == alternate, "new controller reads saved size")
Preferences.setScale(99, for: first)
check(controller.scale(for: first) == pack.stage.defaultScale, "obsolete saved scale resolves to default")
controller.reset(id: first)
check(controller.pet!.pointer.scale == CGFloat(pack.stage.defaultScale), "reset restores scale")
check(abs(controller.pet!.feet.x - pos.x) < 1, "reset preserves position")
Preferences.volume = 2
check(Preferences.volume == 1, "volume clamped")
Preferences.volume = 0.3
check(Preferences.volume == 0.3, "volume stored")
if let name = pack.tuning.keys.sorted().first, let knob = pack.tuning[name] {
    controller.setTuning(knob.max + 10, name: name, for: first)
    check(controller.pet!.tuning[name] == knob.max, "personality clamped and applied")
    controller.reset(id: first)
    check(controller.pet!.tuning[name] == knob.defaultValue, "reset restores personality")
}
let before = controller.pet!
let invalid = temporary.appendingPathComponent("invalid")
try fm.createDirectory(at: invalid, withIntermediateDirectories: true)
try Data("{}".utf8).write(to: invalid.appendingPathComponent("pack.json"))
check(!controller.installPacks(from: [invalid]).isEmpty, "invalid import reports rejection")
check(controller.pet === before, "invalid import retains running pet")
let source = controller.packs.first { $0.pack.identity.id == second }!.root
check(controller.installPacks(from: [source]).isEmpty, "valid import succeeds")
check(controller.pet === before, "unrelated import retains running pet")
check(controller.removablePack(for: second) != nil, "installed pack removable")
check(controller.removablePack(for: first) == nil, "source pack protected")
let savedBytes = try Data(contentsOf: controller.removablePack(for: second)!.appendingPathComponent("pack.json"))
check(!controller.installPacks(from: [source, source]).isEmpty, "batch duplicate reports rejection")
let afterBytes = try Data(contentsOf: controller.removablePack(for: second)!.appendingPathComponent("pack.json"))
check(afterBytes == savedBytes, "duplicate import preserves valid bytes")
let activeSource = controller.pet!.loaded.root
check(controller.installPacks(from: [activeSource]).isEmpty, "active pack import succeeds")
check(controller.pet !== before && controller.activeID == first, "active replacement reloads selection")
check(abs(controller.pet!.feet.x - pos.x) < 1, "active replacement preserves position")
let settings = SettingsWindowController(app: controller)
check(settings.window != nil, "settings constructs with pack controls")
controller.activate(id: second)
settings.refresh()
if let view = settings.window?.contentView {
    view.layoutSubtreeIfNeeded()
    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: root.appendingPathComponent("build/settings-preview.png"))
    }
}
let tunable = controller.pet!.loaded.pack
if let name = tunable.tuning.keys.sorted().first, let knob = tunable.tuning[name] {
    controller.setTuning(knob.max + 10, name: name, for: second)
    check(controller.pet!.tuning[name] == knob.max, "personality clamped and applied")
    controller.activate(id: first); controller.activate(id: second)
    check(controller.pet!.tuning[name] == knob.max, "personality survives switching")
    controller.reset(id: second)
    check(controller.pet!.tuning[name] == knob.defaultValue, "reset restores personality")
}
try controller.remove(id: second)
check(controller.activeID == second && controller.removablePack(for: second) == nil, "remove active override falls back to source")
check(fm.fileExists(atPath: temporary.appendingPathComponent("Trash/" + second).path), "removal preserves recoverable bytes")
do { try controller.remove(id: second); check(false, "source removal rejected") }
catch { check(true, "source removal rejected") }
controller.activate(id: first)
try controller.remove(id: first)
check(controller.activeID == first && controller.removablePack(for: first) == nil, "second override removal falls back")
let empty = AppController(installationDirectory: temporary.appendingPathComponent("Empty"))
empty.reload(); empty.activate(id: nil)
let emptySettings = SettingsWindowController(app: empty)
check(empty.pet == nil && emptySettings.window != nil, "zero-pack settings supported")
controller.pet?.stop()
print("\(count)/\(count) app checks passed")
