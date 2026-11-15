import Foundation
import LodgerEngine

func runPackValidationChecks() throws {
    section("runtime pack validation and installation recovery")
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("lodger-import-tests-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let original = fixtures.appendingPathComponent("test.solidsquare")
    let loader = PackStore(searchPaths: [])
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: original.appendingPathComponent("pack.json"))) as! [String: Any]
    func copy(_ name: String) throws -> URL {
        let url = base.appendingPathComponent(name, isDirectory: true)
        try fm.copyItem(at: original, to: url)
        return url
    }
    func write(_ object: [String: Any], _ url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url.appendingPathComponent("pack.json"))
    }
    func changed(_ path: [String], _ value: Any, in input: [String: Any]) -> [String: Any] {
        var result = input
        if path.count == 1 { result[path[0]] = value }
        else { result[path[0]] = changed(Array(path.dropFirst()), value, in: result[path[0]] as! [String: Any]) }
        return result
    }
    let invalid = try copy("invalid")
    let cases: [(String, [String], Any)] = [
        ("unknown properties", ["typo"], true),
        ("boolean format", ["format"], true),
        ("unsupported format", ["format"], 3),
        ("unsupported engine version", ["engineMin"], "999.0.0"),
        ("invalid ID", ["identity", "id"], "../escape"),
        ("unknown capability", ["requires"], ["scripts"]),
        ("removed capability", ["requires"], ["windowEdges"]),
        ("zero cell size", ["stage", "cell", "w"], 0),
        ("huge cell size", ["stage", "cell", "w"], 1_000_000_000),
        ("overflowing integer", ["stage", "cell", "w"], 1e30),
        ("empty scale choices", ["stage", "scaleSteps"], []),
        ("duplicate scale choices", ["stage", "scaleSteps"], [1, 2, 2]),
        ("default outside scales", ["stage", "defaultScale"], 8),
        ("negative frame duration", ["stage", "defaultFrameMs"], -1),
        ("unknown initial state", ["initialState"], "missing"),
        ("unknown clip", ["states", "resting", "clip"], "missing"),
        ("unknown motion", ["states", "resting", "motion"], "teleport"),
        ("unknown event", ["states", "resting", "interrupts"], [["on": "execute", "state": "resting"]]),
        ("multi-key event", ["states", "resting", "interrupts"], [["on": ["pointer.near": 10, "user.idle": 20], "state": "resting"]]),
        ("unknown target", ["states", "resting", "interrupts"], [["on": "pointer.click", "state": "missing"]]),
        ("invalid guard", ["states", "resting", "interrupts"], [["on": "pointer.click", "state": "resting", "when": ["random": 2]]]),
        ("invalid clock", ["states", "resting", "interrupts"], [["on": "pointer.click", "state": "resting", "when": ["timeOfDay": ["from": "99:99", "to": "08:00"]]]]),
        ("removed nested guard", ["states", "resting", "interrupts"], [["on": "pointer.click", "state": "resting", "when": ["not": ["perched": true]]]]),
        ("unknown texture", ["clips", "still", "texture"], "missing"),
        ("empty frames", ["clips", "still", "frames"], []),
        ("out of range frame", ["clips", "still", "frames"], [["cell": 1]]),
        ("unknown frame sound", ["clips", "still", "frames"], [["cell": 0, "sound": "missing"]]),
        ("zero grid", ["textures", "sq", "columns"], 0),
        ("wrong atlas shape", ["textures", "sq", "columns"], 2),
        ("absolute asset path", ["textures", "sq", "file"], "/tmp/outside.png"),
        ("parent traversal", ["textures", "sq", "file"], "../outside.png"),
        ("dot path component", ["textures", "sq", "file"], "atlas/./sq.png"),
        ("unknown mask texture", ["hitMasks"], ["missing": "mask.bin"]),
        ("missing preview", ["identity", "preview"], "missing.png"),
        ("no body", ["parts"], [["name": "face", "bind": ["mode": "overlay", "clip": "still"]]]),
        ("duplicate body", ["parts"], [["name": "body", "bind": ["mode": "body"]], ["name": "body", "bind": ["mode": "body"]]]),
        ("unknown parent", ["parts"], [["name": "body", "bind": ["mode": "body"]], ["name": "face", "bind": ["mode": "overlay", "clip": "still", "parent": "missing"]]]),
        ("missing anchor", ["parts"], [["name": "body", "bind": ["mode": "body"]], ["name": "orb", "bind": ["mode": "float", "clip": "still", "anchor": "missing"]]]),
        ("invalid knob range", ["tuning"], ["speed": ["label": "Speed", "min": 2, "max": 1, "default": 1]])
    ]
    for (name, path, value) in cases {
        try write(changed(path, value, in: manifest), invalid)
        check((try? loader.load(root: invalid)) == nil, "reject \(name)")
    }
    // Controls: every reference must name a control of the right kind.
    let slider: [String: Any] = ["label": "S", "min": 0.5, "max": 2, "default": 1]
    let zeroSlider: [String: Any] = ["label": "Z", "min": 0, "max": 2, "default": 1]
    let toggle: [String: Any] = ["type": "toggle", "label": "T", "default": true]
    func controls(format: Int, tuning: [String: Any], interrupts: [[String: Any]]) -> [String: Any] {
        var m = changed(["states", "resting", "interrupts"], interrupts, in: manifest)
        m["format"] = format; m["tuning"] = tuning
        return m
    }
    func click(_ when: [String: Any]) -> [[String: Any]] { [["on": "pointer.click", "state": "resting", "when": when]] }
    func flag(_ name: String) -> [String: Any] { ["flag": ["name": name, "value": true]] }
    let both: [String: Any] = ["s": slider, "z": zeroSlider, "t": toggle]
    let controlCases: [(String, Bool, [String: Any])] = [
        ("accept a toggle read by a flag guard", true, controls(format: 2, tuning: both, interrupts: click(flag("t")))),
        ("accept a nested flag guard", true, controls(format: 2, tuning: both, interrupts: click(["not": ["all": [flag("t")]]]))),
        ("accept a knob threshold", true, controls(format: 2, tuning: both, interrupts: [["on": ["user.idle": ["knob": "s"]], "state": "resting"]])),
        ("reject a flag naming an undeclared control", false, controls(format: 2, tuning: both, interrupts: click(flag("missing")))),
        ("reject a nested flag naming a slider", false, controls(format: 2, tuning: both, interrupts: click(["any": [["not": flag("s")]]]))),
        ("reject a knob threshold naming a toggle", false, controls(format: 2, tuning: both, interrupts: [["on": ["user.idle": ["knob": "t"]], "state": "resting"]])),
        ("reject a knob threshold naming an undeclared control", false, controls(format: 2, tuning: both, interrupts: [["on": ["pointer.near": ["knob": "missing"]], "state": "resting"]])),
        ("reject a knob threshold whose slider can reach zero", false, controls(format: 2, tuning: both, interrupts: [["on": ["user.idle": ["knob": "z"]], "state": "resting"]])),
        ("reject a knob on an unparameterised event", false, controls(format: 2, tuning: both, interrupts: [["on": ["pointer.click": ["knob": "s"]], "state": "resting"]])),
        ("reject a toggle with a range", false, controls(format: 2, tuning: ["t": ["type": "toggle", "label": "T", "default": true, "min": 0]], interrupts: click(flag("t")))),
        ("reject a toggle with a numeric default", false, controls(format: 2, tuning: ["t": ["type": "toggle", "label": "T", "default": 1]], interrupts: click(flag("t")))),
        ("reject a slider default outside its range", false, controls(format: 2, tuning: ["s": ["label": "S", "min": 0, "max": 1, "default": 2]], interrupts: click(["lowPower": true]))),
        ("format 1 keeps permissive undeclared flags", true, controls(format: 1, tuning: ["s": slider], interrupts: click(flag("anything")))),
        ("format 1 rejects typed controls", false, controls(format: 1, tuning: both, interrupts: click(["lowPower": true]))),
        ("format 1 rejects slider metadata", false, controls(format: 1, tuning: ["s": ["label": "S", "min": 0.5, "max": 2, "default": 1, "group": "G"]], interrupts: click(["lowPower": true]))),
        ("format 1 rejects knob thresholds", false, controls(format: 1, tuning: ["s": slider], interrupts: [["on": ["user.idle": ["knob": "s"]], "state": "resting"]]))
    ]
    for (name, valid, document) in controlCases {
        try write(document, invalid)
        var reason = ""
        do { _ = try loader.load(root: invalid) } catch { reason = String(describing: error) }
        check(reason.isEmpty == valid, name, reason)
    }
    let canonical = String(data: try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]), encoding: .utf8)!
    let repeated = canonical.replacingOccurrences(of: "\"cell\":0", with: "\"cell\":-1,\"cell\":0")
    try Data(repeated.utf8).write(to: invalid.appendingPathComponent("pack.json"))
    if let repeatedPack = try? loader.load(root: invalid) {
        check(repeatedPack.pack.clips["still"]!.frames[0].cell == 0, "model uses the same repeated-key interpretation as validation")
    } else { check(true, "repeated-key manifest rejected") }
    let arbitraryNames = canonical.replacingOccurrences(of: "resting", with: "perched")
    try Data(arbitraryNames.utf8).write(to: invalid.appendingPathComponent("pack.json"))
    check((try? loader.load(root: invalid)) != nil, "state names remain arbitrary even when they resemble removed vocabulary")
    var active = changed(["states", "resting", "quiescent"], false, in: manifest)
    active = changed(["states", "resting", "duration"], ["minMs": 500, "maxMs": 100], in: active)
    try write(active, invalid)
    check((try? loader.load(root: invalid)) == nil, "reject reversed state duration")
    active = changed(["states", "resting", "duration"], ["minMs": 100, "maxMs": 500, "scaleBy": "missing"], in: active)
    try write(active, invalid)
    check((try? loader.load(root: invalid)) == nil, "reject unknown duration knob")
    try write(changed(["states", "resting", "duration"], "clip", in: manifest), invalid)
    check((try? loader.load(root: invalid)) == nil, "reject quiescent timer")
    try write(manifest, invalid)
    let pixels = invalid.appendingPathComponent("atlas/sq.png")
    try Data("not an image".utf8).write(to: pixels)
    check((try? loader.load(root: invalid)) == nil, "reject corrupt texture")
    try fm.removeItem(at: pixels)
    try fm.createSymbolicLink(at: pixels, withDestinationURL: original.appendingPathComponent("atlas/sq.png"))
    check((try? loader.load(root: invalid)) == nil, "reject external texture symlink")
    try fm.removeItem(at: pixels)
    try fm.copyItem(at: original.appendingPathComponent("atlas/sq.png"), to: pixels)
    try fm.createSymbolicLink(atPath: invalid.appendingPathComponent("inside.png").path, withDestinationPath: "atlas/sq.png")
    try write(changed(["textures", "sq", "file"], "inside.png", in: manifest), invalid)
    check((try? loader.load(root: invalid)) == nil, "reject internal texture symlink")
    let rootLink = base.appendingPathComponent("root-link")
    try fm.createSymbolicLink(at: rootLink, withDestinationURL: original)
    check((try? loader.load(root: rootLink)) == nil, "reject symlink pack root")
    let masked = try copy("masked")
    try write(changed(["hitMasks"], ["sq": "mask.bin"], in: manifest), masked)
    let maskURL = masked.appendingPathComponent("mask.bin")
    try encodeMask([(0..<256).map { (2..<14).contains($0 % 16) && (2..<14).contains($0 / 16) }], 16, 16).write(to: maskURL)
    check((try? loader.load(root: masked)) != nil, "accept matching alpha mask")
    try encodeMask([[Bool](repeating: false, count: 256)], 16, 16).write(to: maskURL)
    check((try? loader.load(root: masked)) == nil, "reject incorrect mask silhouette")
    try encodeMask([[true]], 1, 1).write(to: maskURL)
    check((try? loader.load(root: masked)) == nil, "reject wrong mask dimensions")
    let badMasks: [(String, Data)] = [
        ("overflowing varint", Data(Array("LMSK".utf8) + [1] + Array(repeating: 255, count: 16))),
        ("zero dimensions", Data(Array("LMSK".utf8) + [1, 0, 1, 1, 1, 1])),
        ("oversized run", Data(Array("LMSK".utf8) + [1, 1, 1, 1, 1, 127])),
        ("excessive run count", Data(Array("LMSK".utf8) + [1, 1, 1, 1, 127])),
        ("trailing bytes", encodeMask([[true]], 1, 1) + Data([0]))
    ]
    for (name, data) in badMasks { check((try? HitMask(data: data)) == nil, "reject mask \(name)") }

    let installed = base.appendingPathComponent("installed", isDirectory: true)
    let installer = PackInstaller(directory: installed)
    let first = try installer.install(from: original)
    check(first.installed.root.lastPathComponent == "test.solidsquare", "install directory derives from pack ID")
    let previous = try Data(contentsOf: first.installed.root.appendingPathComponent("pack.json"))
    let update = try copy("different-download-name")
    try write(changed(["identity", "version"], "2.0.0", in: manifest), update)
    let replaced = try installer.install(from: update)
    check(replaced.installed.root.path == first.installed.root.path && replaced.installed.pack.identity.version == "2.0.0", "same ID replaces despite different source folder name", "first=\(first.installed.root.path) replacement=\(replaced.installed.root.path) version=\(replaced.installed.pack.identity.version)")
    _ = try installer.install(from: original)
    try write(changed(["initialState"], "missing", in: manifest), invalid)
    check((try? installer.install(from: invalid)) == nil, "invalid replacement is rejected")
    check(try Data(contentsOf: first.installed.root.appendingPathComponent("pack.json")) == previous, "invalid replacement preserves previous bytes")
    let other = try copy("other-download")
    try write(changed(["identity", "id"], "test.other", in: manifest), other)
    let otherResult = try installer.install(from: other)
    check(otherResult.installed.root != first.installed.root, "different IDs coexist")
    let duplicate = installed.appendingPathComponent("duplicate")
    try fm.copyItem(at: first.installed.root, to: duplicate)
    check((try? installer.install(from: update)) == nil, "ambiguous duplicate installed IDs block replacement")
    let scan = PackStore(searchPaths: [installed]).scan()
    check(scan.packs.count == 1 && scan.failures.count == 2, "discovery reports both ambiguous copies")
    try fm.removeItem(at: duplicate)
    let hidden = installed.appendingPathComponent(".backup-hidden")
    try fm.copyItem(at: first.installed.root, to: hidden)
    check(PackStore(searchPaths: [installed]).discover().count == 2, "hidden transaction folders are never discovered")
    check(PackStore(searchPaths: [installed]).scan().failures.contains { $0.url.lastPathComponent == ".backup-hidden" }, "preserved backup gets a recovery notice")
    try fm.removeItem(at: hidden)
    let collision = installed.appendingPathComponent("test.collision")
    try fm.createDirectory(at: collision, withIntermediateDirectories: false)
    try write(changed(["identity", "id"], "test.collision", in: manifest), other)
    check((try? installer.install(from: other)) == nil && fm.fileExists(atPath: collision.path), "unreadable destination collision remains untouched")
    let legacyRoot = base.appendingPathComponent("legacy-installed", isDirectory: true)
    try fm.createDirectory(at: legacyRoot, withIntermediateDirectories: false)
    let legacy = legacyRoot.appendingPathComponent("old-folder-name", isDirectory: true)
    try fm.copyItem(at: original, to: legacy)
    let legacyResult = try PackInstaller(directory: legacyRoot).install(from: update)
    check(legacyResult.installed.root.lastPathComponent == "old-folder-name" && legacyResult.installed.pack.identity.version == "2.0.0", "replacement preserves legacy folder while matching ID")
    try fm.removeItem(at: legacy.appendingPathComponent("atlas/sq.png"))
    let repaired = try PackInstaller(directory: legacyRoot).install(from: original)
    check((try? loader.load(root: repaired.installed.root)) != nil, "replacement repairs installed artwork while retaining ID ownership")
    let directoryLink = try copy("directory-link")
    try fm.removeItem(at: directoryLink.appendingPathComponent("atlas"))
    try fm.createSymbolicLink(at: directoryLink.appendingPathComponent("atlas"), withDestinationURL: original.appendingPathComponent("atlas"))
    check((try? loader.load(root: directoryLink)) == nil, "reject symlink directory in asset path")
    let sourceInstallRoot = base.appendingPathComponent("recursive-source", isDirectory: true)
    try fm.copyItem(at: original, to: sourceInstallRoot)
    check((try? PackInstaller(directory: sourceInstallRoot.appendingPathComponent("nested-install")).install(from: sourceInstallRoot)) == nil, "reject source containing destination tree")
    let unusedLink = update.appendingPathComponent("unused-link")
    try fm.createSymbolicLink(at: unusedLink, withDestinationURL: original)
    check((try? installer.install(from: update)) == nil, "import rejects even unreferenced symlinks")
    try fm.removeItem(at: unusedLink)
    enum Injected: Error { case diskFailure }
    let commitFailure = PackInstaller(directory: installed, move: { from, to in
        if from.lastPathComponent == "candidate" { throw Injected.diskFailure }
        try fm.moveItem(at: from, to: to)
    })
    check((try? commitFailure.install(from: update)) == nil, "commit failure is surfaced")
    check(try Data(contentsOf: first.installed.root.appendingPathComponent("pack.json")) == previous, "commit failure restores previous bytes")
    let restoreFailure = PackInstaller(directory: installed, move: { from, to in
        if from.lastPathComponent == "candidate" || from.lastPathComponent.hasPrefix(".backup-") { throw Injected.diskFailure }
        try fm.moveItem(at: from, to: to)
    })
    var errorText = ""
    do { _ = try restoreFailure.install(from: update) } catch { errorText = String(describing: error) }
    let backups = try fm.contentsOfDirectory(at: installed, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".backup-") }
    check(backups.count == 1 && errorText.contains(backups[0].path) && errorText.contains("restoration also failed"), "restore failure reports preserved backup path", "backups=\(backups.map(\.path)); error=\(errorText)")
    if let backup = backups.first {
        check(try Data(contentsOf: backup.appendingPathComponent("pack.json")) == previous, "restore failure retains byte-identical previous pack")
    }
    // Real pack acceptance uses caller-provided paths, keeping character names
    // and assets out of the engine library and its fixtures.
    for path in ProcessInfo.processInfo.environment["LODGER_TEST_PACKS"]?.split(separator: ":") ?? [] {
        do { _ = try loader.load(root: URL(fileURLWithPath: String(path))); check(true, "runtime accepts \(path)") }
        catch { check(false, "runtime accepts \(path)", String(describing: error)) }
    }
}
