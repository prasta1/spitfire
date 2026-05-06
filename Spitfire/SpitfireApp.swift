import SwiftData
import SwiftUI

@main
struct SpitfireApp: App {
    let modelContainer: ModelContainer
    @State private var appState = AppState()

    init() {
        do {
            self.modelContainer = try SpitfireModelContainer.makeShared()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appState)
                .preferredColorScheme(appState.theme.colorScheme)
                #if os(macOS)
                .frame(minWidth: 700, minHeight: 450)
                #endif
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .defaultSize(width: 900, height: 600)
        #endif

        #if os(macOS)
        MenuBarExtra("Spitfire", image: "MenuBarIcon") {
            MenuBarQuickQueryView()
                .environment(appState)
        }
        .modelContainer(modelContainer)
        .menuBarExtraStyle(.window)
        #endif
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
