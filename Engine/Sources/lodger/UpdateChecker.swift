import AppKit
import Foundation

/// Small dependency-free update check for the hand-built app bundle. It reads a
/// HTTPS appcast, reports the newest version, and opens the archive URL in a
/// browser. Installation remains an explicit user action; no executable is
/// downloaded or replaced by Lodger itself.
final class UpdateChecker {
    private var checking = false

    func check() {
        guard !checking else { return }
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feed = FeedRelease.httpsURL(raw) else {
            show(title: "Updates are not configured",
                 message: "This development build has no HTTPS update feed.")
            return
        }
        checking = true
        let request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 20)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let os = ProcessInfo.processInfo.operatingSystemVersion
            let systemVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  http.url?.scheme == "https",
                  (200..<300).contains(http.statusCode),
                  let data,
                  let release = FeedParser.parse(data: data, systemVersion: systemVersion) else {
                DispatchQueue.main.async {
                    self.checking = false
                    self.show(title: "Could not check for updates",
                              message: "The update feed was unavailable or invalid.")
                }
                return
            }
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            DispatchQueue.main.async {
                self.checking = false
                if FeedRelease.newer(release.version, than: current) {
                    let alert = NSAlert()
                    alert.messageText = "Lodger \(release.version) is available"
                    alert.informativeText = "Open the release download in your browser?"
                    alert.addButton(withTitle: "Download")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(release.url)
                    }
                } else {
                    self.show(title: "Lodger is up to date", message: "You are running \(current).")
                }
            }
        }.resume()
    }

    private func show(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
