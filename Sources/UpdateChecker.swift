import Foundation
import AppKit

// MARK: - Update manifest model
// Host a JSON file at UPDATE_MANIFEST_URL with this shape:
// {
//   "version":      "1.1.0",
//   "download_url": "https://github.com/you/OpenIn/releases/download/v1.1.0/OpenIn.dmg",
//   "release_notes":"Bug fixes and improvements"
// }

struct UpdateInfo {
    let version:      String
    let downloadURL:  String
    let releaseNotes: String
}

// MARK: - Checker

class UpdateChecker {
    static let shared = UpdateChecker()

    // ── Configure these when you host the app ────────────────────────────────
    // Replace with your actual manifest URL once you have a hosting location.
    // GitHub Gist (raw) or GitHub Pages are the easiest free options.
    private let manifestURL = "https://raw.githubusercontent.com/mindgame0909/openin/main/latest.json"

    // Current app version — read from bundle (set in Info.plist)
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Set when a newer version has been found
    private(set) var availableUpdate: UpdateInfo?

    // MARK: - Public API

    /// Silent background check on launch — rebuilds menu if update found
    func checkInBackground() {
        Task(priority: .background) { await check(notify: false) }
    }

    /// Explicit "Check for Updates" menu action — shows result in alert
    func checkNow(completion: @escaping () -> Void) {
        Task {
            let found = await check(notify: true)
            if !found {
                await MainActor.run {
                    NSApp.activate(ignoringOtherApps: true)
                    let a = NSAlert()
                    a.messageText     = "OpenIn is up to date"
                    a.informativeText = "Version \(currentVersion) is the latest."
                    a.addButton(withTitle: "OK")
                    a.runModal()
                }
            }
            completion()
        }
    }

    // MARK: - Internal

    @discardableResult
    private func check(notify: Bool) async -> Bool {
        guard let url = URL(string: manifestURL),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let remoteVersion = json["version"],
              let downloadURL   = json["download_url"]
        else { return false }

        guard isNewer(remoteVersion, than: currentVersion) else { return false }

        let notes = json["release_notes"] ?? ""
        let info  = UpdateInfo(version: remoteVersion, downloadURL: downloadURL, releaseNotes: notes)
        availableUpdate = info

        if notify {
            await MainActor.run { showUpdateAlert(info) }
        }
        return true
    }

    private func showUpdateAlert(_ info: UpdateInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText     = "OpenIn \(info.version) is available"
        a.informativeText = info.releaseNotes.isEmpty
            ? "A new version of OpenIn is ready to download."
            : info.releaseNotes
        a.addButton(withTitle: "Download")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: info.downloadURL) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Simple semver-style comparison (1.2.3 > 1.1.9 etc.)
    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(r.count, l.count)
        for i in 0..<maxLen {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }
}
