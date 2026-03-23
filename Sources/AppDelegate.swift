import Cocoa
import AppKit
import Carbon
import SwiftUI
import UserNotifications

// Apple Event constants
private let kInternetEventClass: AEEventClass = 0x4755524C  // 'GURL'
private let kAEGetURL: AEEventID             = 0x4755524C  // 'GURL'
private let keyDirectObject: AEKeyword       = 0x2D2D2D2D  // '----'

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var pickerWindowController: PickerWindowController?
    private var rulesWindowController: NSWindowController?

    // MARK: - Launch

    // ── Register the GURL handler as early as possible ───────────────────────
    // Apple Events that launch the app (e.g. a URL click when OpenIn is quit)
    // are queued and dispatched on the FIRST run-loop cycle after launch.
    // applicationWillFinishLaunching fires BEFORE that first cycle, so
    // registering here guarantees the handler is ready for the queued event.
    // If we wait until applicationDidFinishLaunching the event is delivered to
    // the default (no-op) handler and lost — producing the "first click silent" bug.
    func applicationWillFinishLaunching(_ notification: Notification) {
        registerURLHandler()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: quit silently if another OpenIn is already running
        // (happens when LaunchAgent boots a copy while the user already has one open)
        let siblings = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        )
        if siblings.count > 1 {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)

        if let bundleURL = Bundle.main.bundleURL as CFURL? {
            LSRegisterURL(bundleURL, true)
        }

        setupStatusBar()
        UpdateChecker.shared.checkInBackground()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                    appIcon.draw(in: rect); return true
                }
                button.image = img
            } else {
                button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "OpenIn")
            }
            button.toolTip = "OpenIn"
        }

        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()

        // ── Default browser — always clickable ───────────────────────
        let isDefault = isDefaultBrowser()
        let browserItem = NSMenuItem(
            title: isDefault
                ? "✓ OpenIn is Default Browser"
                : "⚠  Set as Default Browser…",
            action: #selector(openDefaultBrowserSettings),
            keyEquivalent: ""
        )
        browserItem.target = self
        browserItem.toolTip = isDefault
            ? "Click to change default browser in Settings"
            : "Click to set OpenIn as your default browser"
        menu.addItem(browserItem)

        menu.addItem(.separator())

        // ── App rules — always visible ───────────────────────────────
        let rulesCount = AppRules.shared.allEntries.count
        let rulesLabel = rulesCount > 0 ? "Manage App Rules (\(rulesCount))…" : "Manage App Rules…"
        let manage = NSMenuItem(title: rulesLabel,
                                action: #selector(showRulesWindow),
                                keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)

        // ── Open at Login ────────────────────────────────────────────
        let loginItem = NSMenuItem(title: "Open at Login",
                                   action: #selector(toggleLoginItem),
                                   keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        // ── Reset ────────────────────────────────────────────────────
        let reset = NSMenuItem(title: "Reset All Preferences…",
                               action: #selector(resetPreferences),
                               keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        // ── Update ───────────────────────────────────────────────────
        if let info = UpdateChecker.shared.availableUpdate {
            let upd = NSMenuItem(
                title: "⬆ Update Available — v\(info.version)",
                action: #selector(openUpdatePage),
                keyEquivalent: ""
            )
            upd.target = self
            menu.addItem(upd)
        } else {
            let check = NSMenuItem(title: "Check for Updates",
                                   action: #selector(checkForUpdates),
                                   keyEquivalent: "")
            check.target = self
            menu.addItem(check)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit OpenIn",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)

        self.statusItem?.menu = menu
    }

    @objc private func checkForUpdates() {
        UpdateChecker.shared.checkNow { [weak self] in
            DispatchQueue.main.async { self?.rebuildMenu() }
        }
    }

    @objc private func openUpdatePage() {
        if let urlStr = UpdateChecker.shared.availableUpdate?.downloadURL,
           let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func resetPreferences() {
        let alert = NSAlert()
        alert.messageText = "Reset All Preferences?"
        alert.informativeText = "This clears all saved app rules and your last-used browser selection. OpenIn will ask which browser to use every time."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            AppRules.shared.clearAll()
            Preferences.shared.lastUsedEntryID = nil
            rebuildMenu()
        }
    }

    // MARK: - Default Browser Check

    private func isDefaultBrowser() -> Bool {
        guard let testURL = URL(string: "https://example.com"),
              let appURL  = NSWorkspace.shared.urlForApplication(toOpen: testURL)
        else { return false }
        return Bundle(url: appURL)?.bundleIdentifier?.lowercased() == "com.personal.openin"
    }

    @objc private func openDefaultBrowserSettings() {
        // Open Desktop & Dock — this is where "Default web browser" lives on macOS 13+
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
    }

    // MARK: - Login Item (LaunchAgent plist — works for ad-hoc signed apps)

    private var launchAgentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.personal.openin.plist")
    }

    private func isLoginItemEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
    }

    @objc private func toggleLoginItem() {
        if isLoginItemEnabled() {
            disableLoginItem()
        } else {
            enableLoginItem()
        }
        rebuildMenu()
    }

    private func enableLoginItem() {
        // ── Write the LaunchAgent plist only — do NOT call launchctl load ──────
        // launchctl load would immediately spawn a second OpenIn instance while
        // the current one is already running (causing two menu-bar icons).
        // launchd discovers the plist automatically on next login and starts OpenIn.
        let execPath = "/Applications/OpenIn.app/Contents/MacOS/OpenIn"
        let plist: [String: Any] = [
            "Label":            "com.personal.openin",
            "ProgramArguments": [execPath],
            "RunAtLoad":        true,
            "KeepAlive":        false,
        ]
        do {
            let dir = launchAgentPlistURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: launchAgentPlistURL)
            showLoginItemNotification(enabled: true)
        } catch {
            NSLog("OpenIn: enableLoginItem error: %@", error.localizedDescription)
        }
    }

    private func disableLoginItem() {
        // Just delete the plist — launchd won't load it on next login
        try? FileManager.default.removeItem(at: launchAgentPlistURL)
        showLoginItemNotification(enabled: false)
    }

    private func showLoginItemNotification(enabled: Bool) {
        let body   = enabled
            ? "OpenIn will launch automatically at next login."
            : "OpenIn has been removed from login items."
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            let send = {
                let content       = UNMutableNotificationContent()
                content.title     = "OpenIn"
                content.body      = body
                // Unique ID each time so macOS always delivers it (same ID = deduped)
                let req = UNNotificationRequest(
                    identifier: "openin.loginItem.\(Int(Date().timeIntervalSince1970))",
                    content: content, trigger: nil
                )
                center.add(req)
            }
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                send()
            case .notDetermined:
                center.requestAuthorization(options: [.alert]) { granted, _ in
                    if granted { send() }
                }
            default: break
            }
        }
    }

    // MARK: - Rules Window

    @objc private func showRulesWindow() {
        if rulesWindowController?.window?.isVisible == true {
            rulesWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        panel.title = "App Rules"
        panel.minSize = NSSize(width: 400, height: 200)

        let view = RulesView(onDismiss: { [weak self] in
            self?.rulesWindowController?.close()
            self?.rebuildMenu()
        })
        panel.contentView = NSHostingView(rootView: view)
        panel.center()

        rulesWindowController = NSWindowController(window: panel)
        rulesWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - URL Event Handling

    private func registerURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: kInternetEventClass,
            andEventID: kAEGetURL
        )
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        // Use the Apple Event's sender PID attribute ('spid') — much more reliable than
        // frontmostApplication, which is already OpenIn by the time this handler runs
        // because macOS activates the URL-handler app before delivering the event.
        let keySenderPIDAttr: AEKeyword = 0x73706964  // 'spid'
        var sourceApp: NSRunningApplication? = nil
        if let pidDesc = event.attributeDescriptor(forKeyword: keySenderPIDAttr) {
            let pid = pid_t(pidDesc.int32Value)
            if pid > 0 {
                let candidate = NSRunningApplication(processIdentifier: pid)
                if candidate?.bundleIdentifier != Bundle.main.bundleIdentifier {
                    sourceApp = candidate
                }
            }
        }

        guard
            let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString)
        else { return }

        DispatchQueue.main.async { self.handleURL(url, from: sourceApp) }
    }

    // MARK: - URL Routing

    private func handleURL(_ url: URL, from sourceApp: NSRunningApplication?) {
        // Check per-app rule
        if let bundleID = sourceApp?.bundleIdentifier {
            switch AppRules.shared.rule(for: bundleID) {
            case .alwaysUse(let entryID, _):
                let entries = BrowserManager.shared.buildEntries()
                if let entry = entries.first(where: { $0.id == entryID }) {
                    BrowserManager.shared.open(url, with: entry)
                    return  // ← skip picker entirely
                }
                // Saved entry no longer exists — fall through to picker
            case .askAlways, .none:
                break
            }
        }

        showPicker(for: url, from: sourceApp)
    }

    private func showPicker(for url: URL, from sourceApp: NSRunningApplication?) {
        pickerWindowController?.close()

        let entries = BrowserManager.shared.buildEntries()
        guard !entries.isEmpty else { return }

        pickerWindowController = PickerWindowController(
            url: url,
            entries: entries,
            sourceApp: sourceApp,
            onSelect: { [weak self] entry, remember, incognito in
                BrowserManager.shared.open(url, with: entry, incognito: incognito)
                if remember, let bundleID = sourceApp?.bundleIdentifier {
                    AppRules.shared.setAlwaysUse(entry: entry, for: bundleID)
                }
                self?.pickerWindowController?.close()
                self?.pickerWindowController = nil
            },
            onCancel: { [weak self] in
                self?.pickerWindowController?.close()
                self?.pickerWindowController = nil
            }
        )

        pickerWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Rules management SwiftUI View

struct RulesView: View {
    let onDismiss: () -> Void
    // Observing AppRules means this view re-renders automatically whenever
    // clearAll() / clear(for:) / setAlwaysUse() is called — even from outside
    @ObservedObject private var appRules = AppRules.shared

    private var entries: [(bundleID: String, name: String, icon: NSImage?, rule: AppRule)] {
        appRules.allEntries
    }

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No app rules saved yet")
                        .font(.title3)
                    Text("When you open a link and check\n\"Always open [App] links here\",\nit will appear here.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(entries, id: \.bundleID) { entry in
                        HStack(spacing: 10) {
                            if let icon = entry.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(.system(size: 13, weight: .medium))
                                ruleLabel(entry.rule)
                            }
                            Spacer()
                            Button("Clear") {
                                AppRules.shared.clear(for: entry.bundleID)
                                // No manual refresh needed — @ObservedObject handles it
                            }
                            .controlSize(.small)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                if !entries.isEmpty {
                    Button("Clear All") {
                        AppRules.shared.clearAll()
                    }
                    .foregroundColor(.red)
                }
                Spacer()
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func ruleLabel(_ rule: AppRule) -> some View {
        switch rule {
        case .askAlways:
            Text("Ask every time")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        case .alwaysUse(_, let name):
            Text("Always open in \(name)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}
