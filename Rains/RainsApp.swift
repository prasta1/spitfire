import SwiftData
import SwiftUI

@main
struct RainsApp: App {
    let modelContainer: ModelContainer
    @State private var appState = AppState()

    init() {
        do {
            self.modelContainer = try RainsModelContainer.makeShared()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(appState.theme.colorScheme)
        }
        .modelContainer(modelContainer)
    }
}

extension AppTheme {
    /// SwiftUI ColorScheme override; nil means "follow the OS".
    var colorScheme: SwiftUI.ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
