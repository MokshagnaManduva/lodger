import Foundation

struct FeedRelease {
    let version: String
    let url: URL

    static func components(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0 >= "0" && $0 <= "9" } })
        else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        return numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    static func newer(_ lhs: String, than rhs: String) -> Bool {
        guard let left = components(lhs), let right = components(rhs) else { return false }
        return right.lexicographicallyPrecedes(left)
    }

    static func httpsURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        return url
    }
}

/// Supports current Sparkle item elements and legacy enclosure version attributes.
/// Choosing the highest compatible version makes feed ordering irrelevant.
final class FeedParser: NSObject, XMLParserDelegate {
    private static let sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    private let systemVersion: String
    private var release: FeedRelease?
    private var inItem = false
    private var version = ""
    private var minimum = "0"
    private var url: URL?
    private var field: String?
    private var text = ""

    init(systemVersion: String) { self.systemVersion = systemVersion }

    static func parse(data: Data, systemVersion: String) -> FeedRelease? {
        guard data.count <= 1_048_576 else { return nil }
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        let delegate = FeedParser(systemVersion: systemVersion)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.release
    }

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if name == "item" {
            inItem = true; version = ""; minimum = "0"; url = nil
        } else if inItem && name == "enclosure" {
            url = attributes["url"].flatMap(FeedRelease.httpsURL)
            if version.isEmpty { version = attributes["sparkle:version"] ?? "" }
        } else if inItem && namespaceURI == Self.sparkle
                    && ["version", "minimumSystemVersion"].contains(name) {
            field = name; text = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if field != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String,
                namespaceURI: String?, qualifiedName: String?) {
        if name == field {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "version" { version = value } else { minimum = value }
            field = nil
        }
        if name == "item" {
            inItem = false
            guard let url, FeedRelease.components(version) != nil,
                  FeedRelease.components(minimum) != nil,
                  !FeedRelease.newer(minimum, than: systemVersion) else { return }
            if release == nil || FeedRelease.newer(version, than: release!.version) {
                release = FeedRelease(version: version, url: url)
            }
        }
    }
}
