import AppKit
import Foundation

// MARK: - Models

struct BrowserProfile: Identifiable {
    let id: String          // "Default", "Profile 1", path segment for Firefox, etc.
    let displayName: String
    let email: String?
}

struct Browser: Identifiable {
    let id: String          // bundle identifier
    let name: String
    let bundleIdentifier: String
    let appURL: URL
    let icon: NSImage
    let profiles: [BrowserProfile]
}

struct BrowserEntry: Identifiable {
    let id: String          // unique: bundleID or bundleID:profileID
    let browser: Browser
    let profile: BrowserProfile?

    var displayName: String {
        if let p = profile, browser.profiles.count > 1 {
            return "\(browser.name)  —  \(p.displayName)"
        }
        return browser.name
    }

    var subtitle: String? {
        guard browser.profiles.count > 1,
              let email = profile?.email, !email.isEmpty
        else { return nil }
        return email
    }
}

// MARK: - BrowserManager

class BrowserManager {
    static let shared = BrowserManager()

    private let knownBundleIDs: [String] = [
        "com.apple.Safari",
        "com.brave.Browser",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser",
        "com.google.Chrome.beta",
        "com.brave.Browser.nightly",
        "com.apple.SafariTechnologyPreview",
    ]

    private let chromiumDirs: [String: String] = [
        "com.google.Chrome":         "Google/Chrome",
        "com.google.Chrome.beta":    "Google/Chrome Beta",
        "com.brave.Browser":         "BraveSoftware/Brave-Browser",
        "com.brave.Browser.nightly": "BraveSoftware/Brave-Browser-Nightly",
        "com.microsoft.edgemac":     "Microsoft Edge",
        "com.vivaldi.Vivaldi":       "Vivaldi",
        "com.operasoftware.Opera":   "com.operasoftware.Opera",
    ]

    // MARK: Build flat entry list

    func buildEntries() -> [BrowserEntry] {
        let browsers = detectBrowsers()
        var entries: [BrowserEntry] = []

        for browser in browsers {
            if browser.profiles.count <= 1 {
                entries.append(BrowserEntry(
                    id: browser.bundleIdentifier,
                    browser: browser,
                    profile: browser.profiles.first
                ))
            } else {
                for profile in browser.profiles {
                    entries.append(BrowserEntry(
                        id: "\(browser.bundleIdentifier):\(profile.id)",
                        browser: browser,
                        profile: profile
                    ))
                }
            }
        }

        // Promote last-used to top
        if let lastID = Preferences.shared.lastUsedEntryID,
           let idx = entries.firstIndex(where: { $0.id == lastID }),
           idx > 0 {
            let entry = entries.remove(at: idx)
            entries.insert(entry, at: 0)
        }

        return entries
    }

    // MARK: Open URL

    func open(_ url: URL, with entry: BrowserEntry, incognito: Bool = false) {
        Preferences.shared.lastUsedEntryID = entry.id

        let bid    = entry.browser.bundleIdentifier
        let appURL = entry.browser.appURL

        // Safari (and Safari Tech Preview) is sandboxed — its executable cannot be
        // spawned directly, and it has no CLI flag for private browsing anyway.
        // Fall back to a normal open for Safari regardless of the incognito flag.
        let safariIDs: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
        let useIncognito = incognito && !safariIDs.contains(bid)

        if useIncognito {
            openIncognito(url: url, entry: entry, bundleID: bid, appURL: appURL)
        } else {
            openNormal(url: url, entry: entry, bundleID: bid, appURL: appURL)
        }
    }

    private func openNormal(url: URL, entry: BrowserEntry, bundleID: String, appURL: URL) {
        let config = NSWorkspace.OpenConfiguration()

        if let profile = entry.profile,
           entry.browser.profiles.count > 1,
           chromiumDirs[bundleID] != nil {
            config.arguments = ["--profile-directory=\(profile.id)"]
        }

        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, error in
            if let e = error { NSLog("OpenIn open error: %@", e.localizedDescription) }
        }
    }

    private func openIncognito(url: URL, entry: BrowserEntry, bundleID: String, appURL: URL) {
        var args: [String] = []

        // Profile (Chromium)
        if let profile = entry.profile,
           entry.browser.profiles.count > 1,
           chromiumDirs[bundleID] != nil {
            args.append("--profile-directory=\(profile.id)")
        }

        // Incognito/private flag per engine
        if chromiumDirs[bundleID] != nil {
            args.append("--incognito")
        } else if bundleID == "org.mozilla.firefox" {
            args.append("--private-window")
        } else if bundleID == "com.microsoft.edgemac" {
            args.append("--inprivate")
        }
        // Safari: no CLI private-mode flag — opens normally
        args.append(url.absoluteString)

        // ── Launch via the real executable, not NSWorkspace ──────────────────
        // NSWorkspace.openApplication(at:configuration:) silently drops 'arguments'
        // when the browser is already running (it just activates the existing process).
        // Spawning the executable directly causes the running browser's singleton to
        // receive the args via IPC and open the incognito / private window correctly.
        if let execName = Bundle(url: appURL)?.infoDictionary?["CFBundleExecutable"] as? String {
            let execURL = appURL.appendingPathComponent("Contents/MacOS/\(execName)")
            if FileManager.default.fileExists(atPath: execURL.path) {
                let task = Process()
                task.executableURL = execURL
                task.arguments = args
                do { try task.run(); return } catch {
                    NSLog("OpenIn: Process.run failed: %@", error.localizedDescription)
                }
            }
        }

        // Fallback (Safari, or any browser whose executable can't be found)
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = args
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, err in
            if let e = err { NSLog("OpenIn incognito fallback: %@", e.localizedDescription) }
        }
    }

    // MARK: - Detection

    private func detectBrowsers() -> [Browser] {
        var result: [Browser] = []
        for bid in knownBundleIDs {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { continue }
            let name = appDisplayName(at: appURL) ?? bid
            let icon: NSImage = {
                let img = NSWorkspace.shared.icon(forFile: appURL.path)
                img.size = NSSize(width: 32, height: 32)
                return img
            }()
            result.append(Browser(
                id: bid, name: name, bundleIdentifier: bid,
                appURL: appURL, icon: icon,
                profiles: detectProfiles(bundleID: bid)
            ))
        }
        return result
    }

    private func appDisplayName(at url: URL) -> String? {
        let b = Bundle(url: url)
        return (b?.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (b?.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Profile detection

    private func detectProfiles(bundleID: String) -> [BrowserProfile] {
        if bundleID == "org.mozilla.firefox" { return firefoxProfiles() }
        if let dir = chromiumDirs[bundleID]  { return chromiumProfiles(in: dir) }
        return []
    }

    private func chromiumProfiles(in relPath: String) -> [BrowserProfile] {
        guard let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return [] }

        let localState = appSupport.appendingPathComponent(relPath).appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localState),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profileSection = root["profile"] as? [String: Any],
              let infoCache = profileSection["info_cache"] as? [String: Any]
        else { return [] }

        var profiles: [BrowserProfile] = []
        for (key, value) in infoCache {
            guard let info = value as? [String: Any] else { continue }
            let name  = info["name"] as? String ?? key
            let email = info["user_name"] as? String
            profiles.append(BrowserProfile(
                id: key, displayName: name,
                email: (email?.isEmpty == false) ? email : nil
            ))
        }

        profiles.sort {
            if $0.id == "Default" { return true }
            if $1.id == "Default" { return false }
            return $0.displayName < $1.displayName
        }
        return profiles
    }

    private func firefoxProfiles() -> [BrowserProfile] {
        guard let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return [] }

        let iniURL = appSupport.appendingPathComponent("Firefox/profiles.ini")
        guard let content = try? String(contentsOf: iniURL, encoding: .utf8) else { return [] }

        // Firefox profiles live in ~/Library/Application Support/Firefox/Profiles/
        let profilesBase = appSupport.appendingPathComponent("Firefox/Profiles")

        var result: [BrowserProfile] = []
        var currentName: String?
        var currentPath: String?
        var isRelative = true
        var inProfileSection = false

        func commitProfile() {
            guard let name = currentName, let path = currentPath else { return }
            let profileDir: URL
            if isRelative {
                profileDir = profilesBase.appendingPathComponent(path)
            } else {
                profileDir = URL(fileURLWithPath: path)
            }
            // Only include profiles whose directory actually exists and has user data
            let prefsFile = profileDir.appendingPathComponent("prefs.js")
            if FileManager.default.fileExists(atPath: prefsFile.path) {
                result.append(BrowserProfile(id: path, displayName: name, email: nil))
            }
        }

        for raw in content.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("[") {
                if inProfileSection { commitProfile() }
                currentName = nil; currentPath = nil; isRelative = true
                inProfileSection = line.hasPrefix("[Profile")
            } else if inProfileSection {
                if line.hasPrefix("Name=") {
                    currentName = String(line.dropFirst(5))
                } else if line.hasPrefix("Path=") {
                    currentPath = String(line.dropFirst(5))
                } else if line.hasPrefix("IsRelative=") {
                    isRelative = line.hasSuffix("1")
                }
            }
        }
        if inProfileSection { commitProfile() }

        return result
    }
}
