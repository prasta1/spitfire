import Foundation
import Observation

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// App-wide state held in the SwiftUI environment. Owns the live
/// `OllamaClient` so that views always reach the current configuration —
/// when `serverURL` changes, the client is rebuilt in place.
@Observable
@MainActor
final class AppState {
    private static let defaultServerURL = "http://localhost:11434"

    private enum Keys {
        static let serverURL = "spitfire.serverURL"
        static let theme = "spitfire.theme"
    }

    var serverURL: URL {
        didSet {
            UserDefaults.standard.set(serverURL.absoluteString, forKey: Keys.serverURL)
            client = OllamaClient(baseURL: serverURL)
        }
    }

    var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme)
        }
    }

    private(set) var client: OllamaClient

    init() {
        let urlRaw = UserDefaults.standard.string(forKey: Keys.serverURL) ?? Self.defaultServerURL
        let url = URL(string: urlRaw) ?? URL(string: Self.defaultServerURL)!
        self.serverURL = url

        let themeRaw = UserDefaults.standard.string(forKey: Keys.theme) ?? AppTheme.system.rawValue
        self.theme = AppTheme(rawValue: themeRaw) ?? .system

        self.client = OllamaClient(baseURL: url)
    }
}
