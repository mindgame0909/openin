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

    private let manifestURL = "https://raw.githubusercontent.com/mindgame0909/openin/main/latest.json"

    // Current app version — read from bundle (set in Info.plist)
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Set when a newer version has been found
    private(set) var availableUpdate: UpdateInfo?

    // MARK: - Public API

    /// Silent background check on launch — calls completion if update found so the menu can be rebuilt
    func checkInBackground(onUpdateFound: (() -> Void)? = nil) {
        Task(priority: .background) {
            let found = await check(notify: false)
            if found { onUpdateFound?() }
        }
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
        a.informativeText = (info.releaseNotes.isEmpty
            ? "A new version of OpenIn is ready to install."
            : info.releaseNotes) + "\n\nOpenIn will update and restart automatically."
        a.addButton(withTitle: "Install & Restart")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn {
            Task { await downloadAndInstall(info) }
        }
    }

    // MARK: - Auto-install

    /// Downloads the DMG, mounts it, replaces /Applications/OpenIn.app, unmounts, relaunches.
    func downloadAndInstall(_ info: UpdateInfo) async {
        guard let downloadURL = URL(string: info.downloadURL) else { return }

        // ── 1. Show progress window ───────────────────────────────────────────
        let progress = await MainActor.run { ProgressWindowController() }
        await MainActor.run { progress.show(status: "Downloading update…") }

        // ── 2. Download DMG to a temp file ───────────────────────────────────
        let dmgURL: URL
        do {
            let (tmpURL, _) = try await URLSession.shared.download(from: downloadURL)
            let dest = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("OpenIn-update-\(info.version).dmg")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmpURL, to: dest)
            dmgURL = dest
        } catch {
            await MainActor.run {
                progress.close()
                showError("Download failed: \(error.localizedDescription)")
            }
            return
        }

        // ── 3. Mount DMG ─────────────────────────────────────────────────────
        await MainActor.run { progress.show(status: "Mounting disk image…") }
        guard let mountPoint = mountDMG(at: dmgURL) else {
            await MainActor.run {
                progress.close()
                showError("Could not mount the disk image.")
            }
            return
        }

        // ── 4. Find OpenIn.app inside the mounted volume ──────────────────────
        let sourceApp = URL(fileURLWithPath: mountPoint).appendingPathComponent("OpenIn.app")
        guard FileManager.default.fileExists(atPath: sourceApp.path) else {
            detachDMG(mountPoint: mountPoint)
            await MainActor.run {
                progress.close()
                showError("OpenIn.app not found in disk image.")
            }
            return
        }

        // ── 5. Replace /Applications/OpenIn.app ──────────────────────────────
        await MainActor.run { progress.show(status: "Installing…") }
        let destApp = URL(fileURLWithPath: "/Applications/OpenIn.app")
        do {
            if FileManager.default.fileExists(atPath: destApp.path) {
                try FileManager.default.removeItem(at: destApp)
            }
            try FileManager.default.copyItem(at: sourceApp, to: destApp)
        } catch {
            detachDMG(mountPoint: mountPoint)
            await MainActor.run {
                progress.close()
                showError("Install failed: \(error.localizedDescription)")
            }
            return
        }

        // ── 6. Unmount DMG ───────────────────────────────────────────────────
        detachDMG(mountPoint: mountPoint)
        try? FileManager.default.removeItem(at: dmgURL)

        // ── 7. Relaunch new version ───────────────────────────────────────────
        // Spawn a shell that waits for this process to exit, then opens the new app.
        await MainActor.run {
            progress.show(status: "Restarting…")
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments  = ["-c", "sleep 1.2 && open /Applications/OpenIn.app"]
            try? task.run()
            NSApp.terminate(nil)
        }
    }

    // MARK: - DMG helpers

    /// Mounts a DMG and returns the first HFS/APFS mount point found.
    private func mountDMG(at url: URL) -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/hdiutil"
        task.arguments  = ["attach", url.path, "-nobrowse", "-noautoopen", "-readonly"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = Pipe()  // suppress stderr

        try? task.run()
        task.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // hdiutil output lines: "/dev/diskXsY  <type>  /Volumes/SomeName"
        // We want the line that has a /Volumes/ mount point.
        for line in output.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            if let mountPt = parts.last, mountPt.hasPrefix("/Volumes/") {
                return mountPt
            }
        }
        return nil
    }

    private func detachDMG(mountPoint: String) {
        let task = Process()
        task.launchPath = "/usr/bin/hdiutil"
        task.arguments  = ["detach", mountPoint, "-quiet"]
        try? task.run()
        task.waitUntilExit()
    }

    // MARK: - Error helper

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText     = "Update Failed"
        a.informativeText = message
        a.alertStyle      = .warning
        a.addButton(withTitle: "OK")
        a.runModal()
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

// MARK: - Progress window

/// Tiny floating window that shows install status ("Downloading…", "Installing…", "Restarting…")
class ProgressWindowController: NSWindowController {
    private let label = NSTextField(labelWithString: "")

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 72),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.title              = "OpenIn Update"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level              = .floating
        panel.isReleasedWhenClosed = false

        super.init(window: panel)

        label.font      = .systemFont(ofSize: 13)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let spinner = NSProgressIndicator()
        spinner.style             = .spinning
        spinner.controlSize       = .small
        spinner.isIndeterminate   = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing     = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: panel.contentView!.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: panel.contentView!.centerYAnchor),
        ])

        panel.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(status: String) {
        label.stringValue = status
        if window?.isVisible == false {
            showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
