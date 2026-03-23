import Foundation

class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    var lastUsedEntryID: String? {
        get { defaults.string(forKey: "lastUsedEntryID") }
        set { defaults.set(newValue, forKey: "lastUsedEntryID") }
    }
}
