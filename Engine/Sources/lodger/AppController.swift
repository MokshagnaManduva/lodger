import AppKit
import LodgerEngine

/// Owns the running character and the list of installed ones.
///
/// Everything host-specific lives here - defaults, the Application Support
/// directory, the menu bar - so `Engine/` stays free of it.
final class AppController {

    private(set) var packs: [PackStore.Loaded] = []
    private(set) var pet: Pet?
    private(set) var failures: [(url: URL, reason: String)] = []

    let store: PackStore

    /// Where a user drops a character. A real, openable directory - not a sandbox
    /// container - which is the whole reason Lodger is distributed with a Developer
    /// ID rather than through the App Store. See CLAUDE.md 2.
    static var packsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("Lodger/Packs", isDirectory: true)
    }

    /// Packs bundled inside the app. Klien ships here so Lodger is never empty on
    /// first run - loaded through the identical code path as anything installed.
    static var bundledPacksDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Packs", isDirectory: true)
    }

    init(extraSearchPaths: [URL] = []) {
        try? FileManager.default.createDirectory(at: Self.packsDirectory,
                                                 withIntermediateDirectories: true)
        // Order matters: later paths shadow earlier ones, so a user pack replaces a
        // bundled pack with the same id.
        var paths: [URL] = []
        if let b = Self.bundledPacksDirectory { paths.append(b) }
        paths.append(contentsOf: extraSearchPaths)
        paths.append(Self.packsDirectory)
        store = PackStore(searchPaths: paths)
    }

    // MARK: packs

    func reload() {
        packs = store.discover()
        failures = collectFailures()
    }

    /// Directories that look like packs but would not load, so the UI can say why
    /// instead of silently ignoring them.
    private func collectFailures() -> [(url: URL, reason: String)] {
        var out: [(URL, String)] = []
        let good = Set(packs.map(\.root.standardizedFileURL.path))
        for dir in store.searchPaths {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
            for entry in entries where entry.hasDirectoryPath {
                guard !good.contains(entry.standardizedFileURL.path) else { continue }
                guard FileManager.default.fileExists(
                    atPath: entry.appendingPathComponent("pack.json").path) else { continue }
                do {
                    _ = try store.load(root: entry)
                } catch {
                    out.append((entry, Self.describe(error)))
                }
            }
        }
        // The same pack can sit in more than one search path - a bundled copy and a
        // working-tree copy, say - and reporting one problem twice is just noise.
        var seen = Set<String>()
        return out.filter { seen.insert("\($0.0.lastPathComponent)|\($0.1)").inserted }
    }

    private static func describe(_ error: Error) -> String {
        if let f = error as? PackStore.Failure { return f.description }
        guard let e = error as? DecodingError else { return error.localizedDescription }
        switch e {
        case .keyNotFound(let k, let ctx):
            return "missing '\(k.stringValue)' at \(path(ctx))"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
            return "wrong type at \(path(ctx))"
        case .dataCorrupted(let ctx):
            return ctx.debugDescription
        @unknown default:
            return "\(e)"
        }
    }

    private static func path(_ ctx: DecodingError.Context) -> String {
        ctx.codingPath.map(\.stringValue).joined(separator: ".").isEmpty
            ? "the top level" : ctx.codingPath.map(\.stringValue).joined(separator: ".")
    }

    // MARK: the running character

    func activate(id: String?) {
        pet?.stop()
        pet = nil
        let chosen = packs.first { $0.pack.identity.id == id } ?? packs.first
        guard let chosen else { return }
        Preferences.packID = chosen.pack.identity.id

        let p = Pet(loaded: chosen)
        p.tuning = Preferences.resolvedTuning(for: chosen.pack)
        p.audio.enabled = Preferences.audioEnabled && chosen.pack.requires.contains("audio")
        p.audio.volume = Preferences.volume
        p.perchMode = Preferences.perchMode
        p.start()
        p.panel.orderFrontRegardless()
        pet = p
    }

    func setPerchMode(_ on: Bool) {
        Preferences.perchMode = on
        pet?.setPerchMode(on)
    }

    var activeID: String? { pet?.loaded.pack.identity.id }
}
