import Foundation

/// Synchronous, serialized by the app's main thread. Each replacement is staged
/// on the destination volume, fully validated, then committed by rename.
public struct PackInstaller {
    public let directory: URL
    /// An injectable rename operation lets the self-test exercise disk failures
    /// at commit and rollback using real temporary directories.
    private let move: (URL, URL) throws -> Void
    public init(directory: URL, move: @escaping (URL, URL) throws -> Void = {
        try FileManager.default.moveItem(at: $0, to: $1)
    }) {
        self.directory = directory
        self.move = move
    }

    public struct Result {
        public let installed: PackStore.Loaded
        public let warnings: [String]
    }

    /// A surviving backup is never deleted on a failed restore. Its path is
    /// included in the error so it can be recovered even after restarting.
    public func install(from source: URL) throws -> Result {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let directory = try PackFiles.root(directory)
        let sourceRoot = try PackFiles.root(source)
        try PackFiles.validateTree(sourceRoot)
        let loader = PackStore(searchPaths: [])
        let sourcePack = try loader.load(root: sourceRoot)
        let id = sourcePack.pack.identity.id
        let entries = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var matches: [URL] = []
        for entry in entries {
            // Even a damaged installed pack still owns its declared ID. Do not
            // hide a duplicate just because its artwork no longer loads.
            if let data = try? PackFiles.data("pack.json", in: entry, limit: 2 * 1024 * 1024),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let identity = object["identity"] as? [String: Any], identity["id"] as? String == id {
                matches.append(entry)
            }
        }
        guard matches.count <= 1 else { throw PackStore.Failure.invalid("duplicate installed ID \(id); remove the extra copies before replacing it") }
        let destination = matches.first ?? directory.appendingPathComponent(id, isDirectory: true)
        if matches.isEmpty, fm.fileExists(atPath: destination.path) {
            throw PackStore.Failure.invalid("destination \(destination.path) is occupied by another or unreadable pack")
        }
        // Staging inside the source would recursively copy the destination.
        guard sourceRoot != directory, !directory.path.hasPrefix(sourceRoot.path + "/") else {
            throw PackStore.Failure.invalid("the source folder contains the installation directory")
        }
        let staging = directory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let candidate = staging.appendingPathComponent("candidate", isDirectory: true)
        let backup = directory.appendingPathComponent(".backup-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: sourceRoot, to: candidate)
        try PackFiles.validateTree(candidate)
        let validated = try loader.load(root: candidate)
        guard validated.pack.identity.id == id else { throw PackStore.Failure.invalid("pack ID changed during import") }
        let replacing = fm.fileExists(atPath: destination.path)
        if replacing { try move(destination, backup) }
        do { try move(candidate, destination) }
        catch {
            let commitError = error
            if replacing {
                do { try move(backup, destination) }
                catch {
                    throw PackStore.Failure.invalid("installation failed: \(commitError); restoration also failed: \(error). Previous pack is preserved at \(backup.path); restore it to \(destination.path).")
                }
            }
            throw PackStore.Failure.invalid("installation failed; previous pack unchanged: \(commitError)")
        }
        var warnings: [String] = []
        if replacing {
            do { try fm.removeItem(at: backup) }
            catch { warnings.append("Pack installed, but the previous copy could not be removed at \(backup.path): \(error)") }
        }
        return Result(installed: PackStore.Loaded(pack: validated.pack, root: destination, origin: "installed"), warnings: warnings)
    }
}
