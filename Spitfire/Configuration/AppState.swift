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

enum ActiveBackend: String, CaseIterable, Identifiable {
    case ollama
    case openRouter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .openRouter: return "OpenRouter"
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
        static let activeBackend = "spitfire.activeBackend"
        static let openRouterAPIKey = "spitfire.openRouterAPIKey"
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

    var activeBackend: ActiveBackend {
        didSet {
            UserDefaults.standard.set(activeBackend.rawValue, forKey: Keys.activeBackend)
        }
    }

    /// OpenRouter API key. Stored in UserDefaults for simplicity — move to
    /// Keychain if stricter security is needed in a future pass.
    var openRouterAPIKey: String {
        didSet {
            UserDefaults.standard.set(openRouterAPIKey, forKey: Keys.openRouterAPIKey)
        }
    }

    /// The Ollama client — used directly for Ollama-only operations (pull, delete, unload).
    private(set) var client: OllamaClient

    /// Set by the menubar popover to request the main window navigate to a specific chat.
    /// `ContentView` observes this and clears it after navigating.
    var pendingSelection: ChatRecord?

    /// The active backend client — use this in views/view models for chat and model listing.
    var activeClient: any SpitfireClient {
        switch activeBackend {
        case .ollama:
            return client
        case .openRouter:
            return OpenRouterClient(apiKey: openRouterAPIKey)
        }
    }

    init() {
        let urlRaw = UserDefaults.standard.string(forKey: Keys.serverURL) ?? Self.defaultServerURL
        let url = URL(string: urlRaw) ?? URL(string: Self.defaultServerURL)!
        self.serverURL = url

        let themeRaw = UserDefaults.standard.string(forKey: Keys.theme) ?? AppTheme.system.rawValue
        self.theme = AppTheme(rawValue: themeRaw) ?? .system

        let backendRaw = UserDefaults.standard.string(forKey: Keys.activeBackend) ?? ActiveBackend.ollama.rawValue
        self.activeBackend = ActiveBackend(rawValue: backendRaw) ?? .ollama

        self.openRouterAPIKey = UserDefaults.standard.string(forKey: Keys.openRouterAPIKey) ?? ""

        self.client = OllamaClient(baseURL: url)
    }
}
