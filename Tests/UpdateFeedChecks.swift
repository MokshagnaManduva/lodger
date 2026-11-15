import Foundation

@main
struct UpdateFeedChecks {
    static func main() {
        func parse(_ items: String) -> FeedRelease? {
            let xml = """
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel>\(items)</channel></rss>
            """
            return FeedParser.parse(data: Data(xml.utf8), systemVersion: "14.4")
        }
        func item(_ version: String, minimum: String = "14.0", url: String = "https://example.com/app.zip") -> String {
            return """
            <item><sparkle:version>\(version)</sparkle:version>
            <sparkle:minimumSystemVersion>\(minimum)</sparkle:minimumSystemVersion>
            <enclosure url="\(url)" /></item>
            """
        }
        precondition(parse(item("2.0") + item("1.0"))?.version == "2.0")
        precondition(parse(item("1.0") + item("2.0"))?.version == "2.0")
        precondition(parse(item("3.0", minimum: "15.0") + item("2.0"))?.version == "2.0")
        precondition(parse(item("2.0", url: "http://example.com/app.zip")) == nil)
        precondition(parse(item("2.0", url: "https://user:pass@example.com/app.zip")) == nil)
        precondition(parse(item("bad")) == nil)
        precondition(parse(item("2.0", minimum: "bad")) == nil)
        precondition(parse("<item><enclosure sparkle:version=\"1.5\" url=\"https://example.com/app.zip\" /></item>")?.version == "1.5")
        precondition(parse("<item><broken>") == nil)
        precondition(!FeedRelease.newer("1.0.0", than: "1"))
        precondition(FeedRelease.newer("1.10", than: "1.9"))
        precondition(FeedParser.parse(data: Data(repeating: 32, count: 1_048_577), systemVersion: "14") == nil)
        print("12 update-feed checks passed")
    }
}
