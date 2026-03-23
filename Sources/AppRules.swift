import AppKit
import Foundation

// MARK: - Rule types

enum AppRule: Codable {
    case askAlways
    case alwaysUse(entryID: String, browserName: String)

    enum CodingKeys: String, CodingKey { case type, entryID, browserName }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "alwaysUse":
            self = .alwaysUse(entryID: try c.decode(String.self, forKey: .entryID),
                              browserName: try c.decode(String.self, forKey: .browserName))
        default:
            self = .askAlways
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .askAlways:
            try c.encode("askAlways", forKey: .type)
        case .alwaysUse(let eid, let bn):
            try c.encode("alwaysUse", forKey: .type)
            try c.encode(eid,         forKey: .entryID)
            try c.encode(bn,          forKey: .browserName)
        }
    }
}

// MARK: - Storage

class AppRules: ObservableObject {
    static let shared = AppRules()
    // @Published so any SwiftUI view observing this object re-renders on change
    @Published private(set) var rules: [String: AppRule] = [:]
    private let key = "appRules_v1"

    init() { load() }

    func rule(for appBundleID: String) -> AppRule? { rules[appBundleID] }

    func setAlwaysUse(entry: BrowserEntry, for appBundleID: String) {
        rules[appBundleID] = .alwaysUse(entryID: entry.id, browserName: entry.displayName)
        save()
    }

    func setAskAlways(for appBundleID: String) {
        rules[appBundleID] = .askAlways
        save()
    }

    func clear(for appBundleID: String) {
        rules.removeValue(forKey: appBundleID)
        save()
    }

    func clearAll() { rules.removeAll(); save() }

    /// Returns all saved rules as (appBundleID, rule) pairs, sorted by app name
    var allEntries: [(bundleID: String, name: String, icon: NSImage?, rule: AppRule)] {
        rules.map { (bundleID: $0.key, name: appName(for: $0.key), icon: appIcon(for: $0.key), rule: $0.value) }
             .sorted { $0.name < $1.name }
    }

    private func appName(for bundleID: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
            ?? (NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                    .flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleDisplayName"] as? String })
            ?? bundleID
    }

    private func appIcon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 20, height: 20)
        return icon
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: AppRule].self, from: data)
        else { return }
        rules = decoded
    }
}
