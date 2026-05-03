import Foundation

/// Centralized configuration for runtime values that will eventually be
/// editable in the settings UI (Phase 4). Reads from `UserDefaults` so the
/// settings UI can write here once it lands.
enum AppConfiguration {
    private static let serverURLKey = "rains.serverURL"
    private static let defaultServerURL = "http://localhost:11434"

    static var serverURL: URL {
        let raw = UserDefaults.standard.string(forKey: serverURLKey) ?? defaultServerURL
        return URL(string: raw) ?? URL(string: defaultServerURL)!
    }
}
