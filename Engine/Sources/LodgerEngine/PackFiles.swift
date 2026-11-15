import Foundation
import Darwin

/// All pack paths are relative regular files; symbolic links and special files
/// are forbidden, including unused files copied during an import.
enum PackFiles {
    static let maxFileBytes = 64 * 1024 * 1024
    static func root(_ url: URL) throws -> URL {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        guard a[.type] as? FileAttributeType == .typeDirectory else {
            throw PackStore.Failure.invalid("pack root must be a directory, not a symbolic link")
        }
        // Foundation can abbreviate /private/var back to /var while directory
        // enumeration returns /private/var. Use one physical path for all comparisons.
        guard let resolved = realpath(url.path, nil) else {
            throw PackStore.Failure.invalid("cannot resolve pack directory \(url.path)")
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    static func file(_ relative: String, in root: URL, limit: Int = maxFileBytes) throws -> URL {
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !relative.contains("\\"), !relative.hasPrefix("/") else {
            throw PackStore.Failure.invalid("unsafe pack path: \(relative)")
        }
        var url = try self.root(root)
        for (i, component) in components.enumerated() {
            url.appendPathComponent(String(component))
            let attributes: [FileAttributeKey: Any]
            do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
            catch { throw PackStore.Failure.missingFiles([relative]) }
            let last = i == components.count - 1
            guard attributes[.type] as? FileAttributeType == (last ? .typeRegular : .typeDirectory) else {
                throw PackStore.Failure.invalid("\(relative): symbolic links and special files are not allowed")
            }
            if last, let size = attributes[.size] as? NSNumber, size.int64Value > limit {
                throw PackStore.Failure.invalid("\(relative): exceeds \(limit) byte limit")
            }
        }
        return url
    }

    static func data(_ relative: String, in root: URL, limit: Int = maxFileBytes) throws -> Data {
        let url = try file(relative, in: root, limit: limit)
        // A bounded read also protects against a regular file growing after stat.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw PackStore.Failure.invalid("\(relative): exceeds byte limit") }
        return data
    }

    static func validateTree(_ source: URL) throws {
        let base = try root(source)
        var bytes: Int64 = 0, count = 0
        func visit(_ directory: URL, depth: Int) throws {
            guard depth <= 32 else { throw PackStore.Failure.invalid("pack folders are nested too deeply") }
            for entry in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                count += 1
                guard count <= 4096 else { throw PackStore.Failure.invalid("pack contains more than 4096 entries") }
                let a = try FileManager.default.attributesOfItem(atPath: entry.path)
                switch a[.type] as? FileAttributeType {
                case .typeDirectory: try visit(entry, depth: depth + 1)
                case .typeRegular:
                    let size = (a[.size] as? NSNumber)?.int64Value ?? 0
                    bytes += size
                    guard size <= maxFileBytes, bytes <= 256 * 1024 * 1024 else {
                        throw PackStore.Failure.invalid("pack exceeds file or total size limit")
                    }
                default: throw PackStore.Failure.invalid("\(entry.lastPathComponent): symbolic links and special files are not allowed")
                }
            }
        }
        try visit(base, depth: 0)
    }
}
