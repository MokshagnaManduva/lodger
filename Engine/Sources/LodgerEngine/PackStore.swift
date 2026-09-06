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

    public func discover() -> [Loaded] {
        var byID: [String: Loaded] = [:]
        var order: [String] = []
        for (i, dir) in searchPaths.enumerated() {
            let origin = i == 0 && searchPaths.count > 1 ? "bundled" : "installed"
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let loaded = try? load(root: entry, origin: origin) else { continue }
                if byID[loaded.pack.identity.id] == nil { order.append(loaded.pack.identity.id) }
                byID[loaded.pack.identity.id] = loaded          // later shadows earlier
            }
        }
        return order.compactMap { byID[$0] }
    }

    public func load(root: URL, origin: String = "installed") throws -> Loaded {
        let data = try Data(contentsOf: root.appendingPathComponent("pack.json"))
        let pack = try JSONDecoder().decode(Pack.self, from: data)
        return Loaded(pack: pack, root: root, origin: origin)
    }

    public func hitMask(for loaded: Loaded, texture: String) throws -> HitMask? {
        guard let rel = loaded.pack.hitMasks[texture] else { return nil }
        return try HitMask(data: Data(contentsOf: loaded.root.appendingPathComponent(rel)))
    }
}
