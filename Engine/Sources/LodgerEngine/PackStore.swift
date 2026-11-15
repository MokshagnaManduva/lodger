import Foundation

/// Discovers and loads packs.
///
/// The bundled default pack and a folder the user dropped in yesterday travel
/// **the same code path**. There is deliberately no `if bundled` anywhere in this
/// file: the bundled pack is discovered, decoded and validated exactly like a
/// stranger's, and a user pack with the same id shadows it. See CLAUDE.md 8a.
public struct PackStore: Sendable {
    public let searchPaths: [URL]

    public init(searchPaths: [URL]) { self.searchPaths = searchPaths }

    /// Bundled packs first, user packs second, so later entries shadow earlier ones.
    public static func standard(bundled: URL?, applicationSupport: URL?) -> PackStore {
        PackStore(searchPaths: [bundled, applicationSupport].compactMap { $0 })
    }

    public struct Loaded: Sendable {
        public let pack: Pack
        public let root: URL
        /// Where it came from, for display only. Nothing branches on this.
        public let origin: String
    }

    public struct Scan {
        public let packs: [Loaded]
        public let failures: [(url: URL, reason: String)]
    }

    public func discover() -> [Loaded] { scan().packs }

    /// Duplicate IDs in one search directory are ambiguous and rejected. Across
    /// search directories the documented later-directory override still applies.
    public func scan() -> Scan {
        var byID: [String: Loaded] = [:]
        var failures: [(url: URL, reason: String)] = []
        for (i, dir) in searchPaths.enumerated() {
            let origin = i == 0 && searchPaths.count > 1 ? "bundled" : "installed"
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
            var group: [String: [Loaded]] = [:]
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if entry.lastPathComponent.hasPrefix(".backup-") {
                    failures.append((entry, "Preserved replacement backup at \(entry.path). Reveal this folder to recover the previous pack or remove it after verifying the installed copy."))
                    continue
                }
                guard !entry.lastPathComponent.hasPrefix(".") else { continue }
                guard FileManager.default.fileExists(atPath: entry.appendingPathComponent("pack.json").path) else { continue }
                do {
                    let loaded = try load(root: entry, origin: origin)
                    group[loaded.pack.identity.id, default: []].append(loaded)
                } catch { failures.append((entry, String(describing: error))) }
            }
            for (id, copies) in group {
                if copies.count == 1 { byID[id] = copies[0] }
                else { for copy in copies { failures.append((copy.root, "duplicate pack ID \(id) in \(dir.path)")) } }
            }
        }
        return Scan(packs: byID.values.sorted { $0.pack.identity.id < $1.pack.identity.id },
                    failures: failures.sorted { $0.url.path < $1.url.path })
    }

    /// Why a directory that looks like a pack would not load.
    public enum Failure: Error, CustomStringConvertible {
        case missingFiles([String])
        case unsupportedFormat(Int)
        case invalid(String)
        public var description: String {
            switch self {
            case .invalid(let reason): return reason
            case .missingFiles(let f):
                return f.count == 1 ? "missing \(f[0])"
                                    : "missing \(f.count) files, first \(f[0])"
            case .unsupportedFormat(let v):
                return "unsupported pack format \(v)"
            }
        }
    }

    public func load(root: URL, origin: String = "installed") throws -> Loaded {
        let root = try PackFiles.root(root)
        let data = try PackFiles.data("pack.json", in: root, limit: 2 * 1024 * 1024)
        let raw = try JSONSerialization.jsonObject(with: data)
        try PackSchemaValidator.validate(raw)
        if let textures = (raw as? [String: Any])?["textures"] as? [String: [String: Any]],
           textures.values.contains(where: { $0["strip"] != nil }) {
            throw Failure.invalid("source texture strips must be compiled with packtool build before installation")
        }
        // Decode the exact object that passed schema validation. Foundation JSON
        // parsers can disagree about repeated keys in the original bytes.
        let canonical = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys])
        let pack = try JSONDecoder().decode(Pack.self, from: canonical)
        guard pack.format == 1 else { throw Failure.unsupportedFormat(pack.format) }
        try PackValidation.validate(pack, manifest: raw as! [String: Any], root: root)

        return Loaded(pack: pack, root: root, origin: origin)
    }

    /// Recheck containment at preview read time, just as for runtime assets.
    public func previewData(for loaded: Loaded) throws -> Data? {
        guard let file = loaded.pack.identity.preview else { return nil }
        return try PackFiles.data(file, in: loaded.root)
    }

    public func hitMask(for loaded: Loaded, texture: String) throws -> HitMask? {
        guard let rel = loaded.pack.hitMasks[texture] else { return nil }
        return try HitMask(data: PackFiles.data(rel, in: loaded.root))
    }
}
