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
    let installationDirectory: URL
    var onChange: (() -> Void)?
    private let trash: (URL) throws -> Void
    /// The character to show when nothing has been chosen yet. Supplied by the
    /// bundle's Info.plist, so the build decides it and no pack ID lives in source.
    let defaultPackID: String?

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

    init(extraSearchPaths: [URL] = [], installationDirectory: URL = AppController.packsDirectory,
         defaultPackID: String? = Bundle.main.object(forInfoDictionaryKey: "LodgerDefaultPack") as? String,
         trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.trash = trash
        self.defaultPackID = defaultPackID
        self.installationDirectory = installationDirectory
        try? FileManager.default.createDirectory(at: installationDirectory,
                                                 withIntermediateDirectories: true)
        // Order matters: later paths shadow earlier ones, so a user pack replaces a
        // bundled pack with the same id.
        var paths: [URL] = []
        if let b = Self.bundledPacksDirectory { paths.append(b) }
        paths.append(contentsOf: extraSearchPaths)
        paths.append(installationDirectory)
        store = PackStore(searchPaths: paths)
    }

    // MARK: packs

    func reload() {
        let scan = store.scan()
        packs = scan.packs
        failures = scan.failures
        onChange?()
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
        let previousFeet = pet?.feet
        pet?.stop()
        pet = nil
        let chosen = packs.first { $0.pack.identity.id == id }
            ?? packs.first { $0.pack.identity.id == defaultPackID }
            ?? packs.first
        guard let chosen else { Preferences.packID = nil; onChange?(); return }
        Preferences.packID = chosen.pack.identity.id

        let allowedScales = chosen.pack.stage.scaleSteps
        let savedScale = Preferences.scale(for: chosen.pack.identity.id,
                                           defaultValue: chosen.pack.stage.defaultScale)
        let scale = allowedScales.contains(savedScale) ? savedScale : chosen.pack.stage.defaultScale
        let p = Pet(loaded: chosen, scale: scale)
        p.tuning = Preferences.resolvedTuning(for: chosen.pack)
        p.flags = Preferences.resolvedFlags(for: chosen.pack)
        p.audio.enabled = Preferences.audioEnabled && chosen.pack.requires.contains("audio")
        p.audio.volume = Preferences.volume
        if let previousFeet { p.place(at: previousFeet) }
        p.start()
        p.panel.orderFrontRegardless()
        pet = p
        onChange?()
    }

    var activeID: String? { pet?.loaded.pack.identity.id }

    func scales(for id: String) -> [Int] {
        packs.first { $0.pack.identity.id == id }?.pack.stage.scaleSteps ?? []
    }

    func scale(for id: String) -> Int {
        guard let pack = packs.first(where: { $0.pack.identity.id == id }) else { return 1 }
        let value = Preferences.scale(for: id, defaultValue: pack.pack.stage.defaultScale)
        return pack.pack.stage.scaleSteps.contains(value) ? value : pack.pack.stage.defaultScale
    }

    func setScale(_ scale: Int, for id: String) {
        guard scales(for: id).contains(scale) else { return }
        Preferences.setScale(scale, for: id)
        if activeID == id { activate(id: id) }
    }

    func reset(id: String) {
        Preferences.reset(packID: id)
        if activeID == id { activate(id: id) } else { onChange?() }
    }

    func setTuning(_ value: Double, name: String, for id: String) {
        guard value.isFinite, let pack = packs.first(where: { $0.pack.identity.id == id }),
              let knob = pack.pack.tuning[name], !knob.isToggle else { return }
        var values = Preferences.tuning(for: id)
        values[name] = min(knob.max, max(knob.min, value))
        Preferences.setTuning(values, for: id)
        if activeID == id { pet?.tuning = Preferences.resolvedTuning(for: pack.pack) }
    }

    /// Applies to the running pet at its next event or timeout; it is not restarted.
    func setFlag(_ value: Bool, name: String, for id: String) {
        guard let pack = packs.first(where: { $0.pack.identity.id == id }),
              pack.pack.tuning[name]?.isToggle == true else { return }
        var values = Preferences.flags(for: id)
        values[name] = value
        Preferences.setFlags(values, for: id)
        if activeID == id { pet?.flags = Preferences.resolvedFlags(for: pack.pack) }
    }

    func removablePack(for id: String) -> URL? {
        guard let loaded = packs.first(where: { $0.pack.identity.id == id }),
              loaded.root.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
                == installationDirectory.standardizedFileURL.resolvingSymlinksInPath().path else { return nil }
        return loaded.root
    }

    /// Trash is reversible; bundled and development source packs cannot be removed.
    func remove(id: String) throws {
        guard let root = removablePack(for: id) else {
            throw PackStore.Failure.invalid("Only user-installed characters can be removed.")
        }
        try trash(root)
        let wasActive = activeID == id
        reload()
        if wasActive { activate(id: id) }
    }

    /// Validate into a staging directory before replacing an installed pack.
    /// A failed copy or decode leaves the existing installation untouched.
    @discardableResult
    func installPacks(from sources: [URL]) -> [String] {
        var errors: [String] = []
        let selectedID = activeID
        let installer = PackInstaller(directory: installationDirectory)
        var installedIDs = Set<String>()
        var seen = Set<String>()
        for source in sources {
            do {
                let loaded = try store.load(root: source)
                guard seen.insert(loaded.pack.identity.id).inserted else {
                    throw PackStore.Failure.invalid("duplicate ID in this import batch: \(loaded.pack.identity.id)")
                }
                let result = try installer.install(from: source)
                installedIDs.insert(result.installed.pack.identity.id)
                errors += result.warnings
            } catch { errors.append("\(source.lastPathComponent): \(Self.describe(error))") }
        }
        reload()
        if selectedID == nil || installedIDs.contains(selectedID ?? "") { activate(id: selectedID) }
        return errors
    }
}
