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
if let name = pack.tuning.keys.sorted().first(where: { pack.tuning[$0]?.isToggle == false }), let knob = pack.tuning[name] {
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
if let name = tunable.tuning.keys.sorted().first(where: { tunable.tuning[$0]?.isToggle == false }), let knob = tunable.tuning[name] {
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
// Pack-declared controls, on a synthetic pack so no character is assumed.
let controlSource = temporary.appendingPathComponent("control-source")
try fm.copyItem(at: root.appendingPathComponent("Tests/Fixtures/test.solidsquare"), to: controlSource)
var controlManifest = try JSONSerialization.jsonObject(with: Data(contentsOf: controlSource.appendingPathComponent("pack.json"))) as! [String: Any]
controlManifest["format"] = 2
var controlIdentity = controlManifest["identity"] as! [String: Any]
controlIdentity["id"] = "test.controls"; controlManifest["identity"] = controlIdentity
controlManifest["tuning"] = [
    "wait": ["label": "Wait", "min": 60, "max": 600, "default": 300, "unit": "seconds", "group": "Rest"],
    "alert": ["type": "toggle", "label": "Alert", "default": true, "description": "Responds to clicks"],
    "unused": ["label": "Unused", "min": 0, "max": 1, "default": 0.5]]
controlManifest["states"] = ["resting": ["clip": "still", "quiescent": true, "interrupts": [
    ["on": "pointer.click", "state": "resting", "when": ["flag": ["name": "alert", "value": true]]],
    ["on": "controls.changed", "state": "dozing", "when": ["flag": ["name": "alert", "value": false]]],
    ["on": ["user.idle": ["knob": "wait"]], "state": "resting"]]],
    "dozing": ["clip": "still", "quiescent": true, "interrupts": [
    ["on": "controls.changed", "state": "resting", "when": ["flag": ["name": "alert", "value": true]]]]]]
try JSONSerialization.data(withJSONObject: controlManifest).write(to: controlSource.appendingPathComponent("pack.json"))
let controlMessages = controller.installPacks(from: [controlSource])
check(controlMessages.isEmpty, "pack with controls installs")
let cid = "test.controls"
controller.activate(id: cid)
let controlled = controller.pet!
check(controlled.flags == ["alert": true] && controlled.tuning["wait"] == 300, "pack defaults apply on first activation")
check(controlled.userIdle.isArmed && controlled.userIdle.threshold == 300, "a tuned threshold arms its watcher at the default")
controller.setTuning(120, name: "wait", for: cid)
check(controller.pet === controlled && controlled.userIdle.threshold == 120, "changing a threshold slider re-arms without restarting")
controller.setFlag(false, name: "alert", for: cid)
check(controller.pet === controlled && controlled.flags["alert"] == false, "toggle applies live without restarting")
check(controlled.director.flags["alert"] == false, "toggle reaches the guard evaluator")
check(controlled.director.current == "dozing", "a pack can respond to the switch itself, even from a quiescent state")
controller.setFlag(false, name: "alert", for: cid)
controller.setFlag(true, name: "alert", for: cid)
check(controlled.director.current == "resting", "and respond again when it is switched back")
controller.setFlag(false, name: "alert", for: cid)
controller.setFlag(true, name: "wait", for: cid); controller.setTuning(1, name: "alert", for: cid)
check(Preferences.flags(for: cid)["wait"] == nil && Preferences.tuning(for: cid)["alert"] == nil, "a control cannot be set as the wrong kind")
let reread = AppController(extraSearchPaths: [], installationDirectory: controller.installationDirectory)
reread.reload()
let rereadPack = reread.packs.first { $0.pack.identity.id == cid }!.pack
check(Preferences.resolvedFlags(for: rereadPack)["alert"] == false && Preferences.resolvedTuning(for: rereadPack)["wait"] == 120,
      "new controller reads saved controls")
controller.activate(id: second); controller.activate(id: cid)
check(controller.pet!.flags["alert"] == false && controller.pet!.tuning["wait"] == 120, "controls survive switching")
let controlSettings = SettingsWindowController(app: controller)
func find(_ view: NSView, _ id: String) -> NSView? {
    if view.identifier?.rawValue == id { return view }
    for child in view.subviews { if let hit = find(child, id) { return hit } }
    return nil
}
let controlRoot = controlSettings.window!.contentView!
check((find(controlRoot, "alert") as? NSButton)?.state == .off, "settings shows a checkbox for a used toggle")
check((find(controlRoot, "wait") as? NSSlider)?.doubleValue == 120, "settings shows a slider for a used knob")
check((find(controlRoot, "readout.wait") as? NSTextField)?.stringValue == "2 min", "slider readout follows the unit hint")
check(find(controlRoot, "unused") == nil, "an unused control is not shown")
check(ControlFormat.string(45, unit: "seconds") == "45 s" && ControlFormat.string(5400, unit: "seconds") == "1 h 30 min"
      && ControlFormat.string(1.5, unit: "percent") == "150%" && ControlFormat.string(1.5, unit: nil) == "1.50", "value formats")
// A value saved under the other kind must not be misread.
Preferences.setTuning(["alert": 0, "wait": 120], for: cid)
Preferences.setFlags(["wait": true], for: cid)
check(Preferences.resolvedFlags(for: rereadPack) == ["alert": true] && Preferences.resolvedTuning(for: rereadPack)["wait"] == 120,
      "a value saved as the wrong kind falls back to the pack default")
controller.reset(id: cid)
check(controller.pet!.flags["alert"] == true && controller.pet!.tuning["wait"] == 300, "reset restores control defaults")
Preferences.packID = nil
let preferred = AppController(extraSearchPaths: [root.appendingPathComponent("Packs")],
                              installationDirectory: temporary.appendingPathComponent("Preferred"), defaultPackID: second)
preferred.reload(); preferred.activate(id: nil)
check(preferred.activeID == second, "first run honours the configured default character")
preferred.pet?.stop()
let fallback = AppController(extraSearchPaths: [root.appendingPathComponent("Packs")],
                             installationDirectory: temporary.appendingPathComponent("Fallback"), defaultPackID: "missing.pack")
fallback.reload(); fallback.activate(id: nil)
check(fallback.activeID == first, "a missing default falls back to the first character")
fallback.pet?.stop()
let empty = AppController(installationDirectory: temporary.appendingPathComponent("Empty"))
empty.reload(); empty.activate(id: nil)
let emptySettings = SettingsWindowController(app: empty)
check(empty.pet == nil && emptySettings.window != nil, "zero-pack settings supported")
controller.pet?.stop()
print("\(count)/\(count) app checks passed")
